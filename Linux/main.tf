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

resource "aws_security_group" "linux_sg" {
  name        = "linux-redhat-${random_id.sg_suffix.hex}"
  description = "linux redhat security group"

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

resource "aws_instance" "linux" {
  ami                    = data.aws_ami.rhel_96.id
  instance_type          = var.instance_type
  key_name               = data.external.check_key.result.final_key_name
  vpc_security_group_ids = [aws_security_group.linux_sg.id]

  root_block_device {
    volume_size = var.storage_size
  }

  # Ensure we don't proceed if key creation failed
  depends_on = [
    aws_key_pair.generated_key_pair,
    aws_s3_object.upload_pem_key
  ]


  tags = {
    Name          = "Linux (Red Hat)"
    AutoStop      = true
    ServiceType   = var.servicetype
    Owner         = var.usermail
    UserEmail     = var.usermail
    RunQuotaHours = var.quotahours
    HoursPerDay   = var.hoursperday
    Category      = var.category
    PlanStartDate = var.planstartdate
  }
}

# Outputs
output "pem_s3_url" {
  value = (
    length(aws_s3_object.upload_pem_key) > 0 ?
    "s3://${aws_s3_object.upload_pem_key[0].bucket}/${aws_s3_object.upload_pem_key[0].key}" :
    "Key not uploaded (already exists in S3)"
  )
}

output "public_ip" {
  value = aws_instance.linux.public_ip
}

output "instance_id" {
  value = aws_instance.linux.id
}