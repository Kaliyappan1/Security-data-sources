provider "aws" {
  region     = var.aws_region
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
  bucket = "splunk-deployment-prod"
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

# --- Check if Security Group Already Exists ---
data "aws_security_groups" "existing" {
  filter {
    name   = "group-name"
    values = [var.sg_name]
  }
}

# --- Create Security Group If Not Exists ---
resource "aws_security_group" "openvpn_sg" {
  count       = length(data.aws_security_groups.existing.ids) == 0 ? 1 : 0
  name        = var.sg_name

  dynamic "ingress" {
    for_each = [22, 943, 443, 1194]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Get Latest Ubuntu 22.04 LTS AMI (HVM, EBS-backed)
data "aws_ami" "ubuntu_latest" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "openvpn" {
  ami                         = data.aws_ami.ubuntu_latest.id
  instance_type               = var.instance_type
  key_name                    = data.external.check_key.result.final_key_name
  vpc_security_group_ids      = (
  length(data.aws_security_groups.existing.ids) > 0
    ? data.aws_security_groups.existing.ids
    : [aws_security_group.ossec_sg[0].id]
)


  root_block_device {
    volume_size = storage_size
  }

  # Ensure we don't proceed if key creation failed
  depends_on = [
    aws_key_pair.generated_key_pair,
    aws_s3_object.upload_pem_key
  ]

  tags = {
    Name          = "OpenVPN"
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

resource "local_file" "ansible_inventory" {
  content  = <<-EOT
  [openvpn]
  ${aws_instance.openvpn.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=./keys/${local.final_key_name}.pem
  EOT
  filename = "${path.module}/inventory.ini"
}