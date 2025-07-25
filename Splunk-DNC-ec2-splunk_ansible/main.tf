terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "external" "check_key" {
  program = [
    "bash",
    "${path.module}/scripts/check_key.sh",
    var.key_name,
    var.aws_region,
    var.usermail,
    "${path.module}/keys"
  ]
}

locals {
  key_check_error = try(data.external.check_key.result.error, "")
  key_check_failed = local.key_check_error != "" ? (
    error("Key check failed: ${local.key_check_error}")
  ) : false
  
  final_key_name  = data.external.check_key.result.final_key_name
  s3_key_exists   = data.external.check_key.result["exists_in_s3"] == "true"
  aws_key_exists  = data.external.check_key.result["exists_in_aws"] == "true"
  need_new_key    = !(local.s3_key_exists && local.aws_key_exists)
}

# Generate PEM key only if needed
resource "tls_private_key" "generated_key" {
  count     = local.need_new_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create EC2 Key Pair only if needed
resource "aws_key_pair" "generated_key_pair" {
  count = local.need_new_key ? 1 : 0

  key_name   = local.final_key_name
  public_key = tls_private_key.generated_key[0].public_key_openssh

  lifecycle {
    ignore_changes = [public_key]
  }
}

# Upload PEM to S3 only if it's a new key
resource "aws_s3_object" "upload_pem_key" {
  count  = (local.need_new_key && !local.s3_key_exists) ? 1 : 0
  bucket = "splunk-deployment-test"
  key    = "clients/${var.usermail}/keys/${local.final_key_name}.pem"
  content = tls_private_key.generated_key[0].private_key_pem

  depends_on = [aws_key_pair.generated_key_pair]
}

# Save PEM file locally only if it's a new key
resource "local_file" "pem_file" {
  count = (local.need_new_key && !local.s3_key_exists) ? 1 : 0

  filename        = "${path.module}/keys/${local.final_key_name}.pem"
  content         = tls_private_key.generated_key[0].private_key_pem
  file_permission = "0400"

  depends_on = [aws_key_pair.generated_key_pair]
}

resource "random_id" "sg_suffix" {
  byte_length = 3
}

# Security Group
resource "aws_security_group" "splunk_sg" {
  name        = "splunk-security-group-${random_id.sg_suffix.hex}"
  description = "Security group for Splunk server"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 9999
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "rhel_96" {
  most_recent = true

  filter {
    name   = "name"
    values = ["RHEL-9.6.0*x86_64*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["309956199498"]  # Red Hat official
}

# ✅ Create 3 EC2 Instances: SH, IDX, HF
resource "aws_instance" "Splunk_sh_idx_hf" {
  count                  = 3
  ami                    = data.aws_ami.rhel_96.id
  instance_type          = var.instance_type
  key_name               = data.external.check_key.result.final_key_name
  vpc_security_group_ids = [aws_security_group.splunk_sg.id]

  root_block_device {
    volume_size = var.storage_size
  }

  # Ensure we don't proceed if key creation failed
  depends_on = [
    aws_key_pair.generated_key_pair,
    aws_s3_object.upload_pem_key
  ]

  user_data = file("splunk-setup.sh")

  tags = {
    Name = replace(element(["${var.instance_name}-SearchHead", "${var.instance_name}-Indexer", "${var.instance_name}-HF"], count.index), " ", "-")
    AutoStop      = "true"
    ServiceType   = var.servicetype
    Owner         = var.usermail
    UserEmail     = var.usermail
    RunQuotaHours = var.quotahours
    HoursPerDay   = var.hoursperday
    Category      = var.category
    PlanStartDate = var.planstartdate
  }
}

# ✅ Create EC2 Instance: UF
resource "aws_instance" "Splunk_uf" {
  ami                    = data.aws_ami.rhel_96.id
  instance_type          = var.instance_type
  key_name               = data.external.check_key.result.final_key_name
  vpc_security_group_ids = [aws_security_group.splunk_sg.id]

  root_block_device {
    volume_size = var.storage_size
  }

  # Ensure we don't proceed if key creation failed
  depends_on = [
    aws_key_pair.generated_key_pair,
    aws_s3_object.upload_pem_key
  ]

  user_data = file("splunk-setup-UF.sh")

  tags = {
    Name = "${replace(var.instance_name, " ", "-")}-UF"
    AutoStop      = "true"
    ServiceType   = var.servicetype
    Owner         = var.usermail
    UserEmail     = var.usermail
    RunQuotaHours = var.quotahours
    HoursPerDay   = var.hoursperday
    Category      = var.category
    PlanStartDate = var.planstartdate
  }
}

# ✅ Generate Ansible Inventory File
resource "local_file" "inventory" {
  content = <<EOT
[search_head]
${replace(aws_instance.Splunk_sh_idx_hf[0].tags.Name, " ", "-")} ansible_host=${aws_instance.Splunk_sh_idx_hf[0].public_ip} ansible_user=ec2-user private_ip=${aws_instance.Splunk_sh_idx_hf[0].private_ip} ansible_ssh_private_key_file=./keys/${local.final_key_name}.pem

[indexer]
${replace(aws_instance.Splunk_sh_idx_hf[1].tags.Name, " ", "-")} ansible_host=${aws_instance.Splunk_sh_idx_hf[1].public_ip} ansible_user=ec2-user private_ip=${aws_instance.Splunk_sh_idx_hf[1].private_ip} ansible_ssh_private_key_file=./keys/${local.final_key_name}.pem

[heavy_forwarder]
${replace(aws_instance.Splunk_sh_idx_hf[2].tags.Name, " ", "-")} ansible_host=${aws_instance.Splunk_sh_idx_hf[2].public_ip} ansible_user=ec2-user private_ip=${aws_instance.Splunk_sh_idx_hf[2].private_ip} ansible_ssh_private_key_file=./keys/${local.final_key_name}.pem

[universal_forwarder]
${replace(aws_instance.Splunk_uf.tags.Name, " ", "-")} ansible_host=${aws_instance.Splunk_uf.public_ip} ansible_user=ec2-user private_ip=${aws_instance.Splunk_uf.private_ip} ansible_ssh_private_key_file=./keys/${local.final_key_name}.pem

[splunk:children]
search_head
indexer
heavy_forwarder
EOT

  filename = "${path.module}/inventory.ini"
}

# ✅ Output Public IPs of SH, IDX, HF
output "instance_public_ips" {
  value = aws_instance.Splunk_sh_idx_hf[*].public_ip
}

# ✅ Output Public IP of UF
output "uf_instance_public_ip" {
  value = aws_instance.Splunk_uf.public_ip
}

output "pem_s3_url" {
  value = (
    length(aws_s3_object.upload_pem_key) > 0 ?
    "s3://${aws_s3_object.upload_pem_key[0].bucket}/${aws_s3_object.upload_pem_key[0].key}" :
    "Key not uploaded (already exists in S3)"
  )
}

output "instance_id" {
  value = concat(
    aws_instance.Splunk_sh_idx_hf[*].id,
    [aws_instance.Splunk_uf.id]
  )
}