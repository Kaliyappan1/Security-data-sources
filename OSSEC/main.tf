provider "aws" {
  region     = var.aws_region
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

# Get next available key name
data "external" "key_check" {
  program = ["${path.module}/scripts/check_key.sh", var.key_name, var.aws_region]
}

locals {
  raw_key_name    = data.external.key_check.result.final_key_name
  final_key_name  = replace(local.raw_key_name, " ", "-")
}

# Generate PEM key
resource "tls_private_key" "generated_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create EC2 Key Pair
resource "aws_key_pair" "generated_key_pair" {
  key_name   = local.final_key_name
  public_key = tls_private_key.generated_key.public_key_openssh
}

# Upload PEM to S3
resource "aws_s3_object" "upload_pem_key" {
  bucket  = "splunk-deployment-test"
  key     = "clients/${var.usermail}/keys/${local.final_key_name}.pem"
  content = tls_private_key.generated_key.private_key_pem
}

# Save PEM file locally
resource "local_file" "pem_file" {
  filename        = "${path.module}/keys/${local.final_key_name}.pem"
  content         = tls_private_key.generated_key.private_key_pem
  file_permission = "0400"
}

resource "random_id" "sg_suffix" {
  byte_length = 2
}

# --- Check if Security Group Already Exists ---
data "aws_security_groups" "existing" {
  filter {
    name   = "group-name"
    values = [var.sg_name]
  }
}

# --- Create Security Group If Not Exists ---
resource "aws_security_group" "ossec_sg" {
  count       = length(data.aws_security_groups.existing.ids) == 0 ? 1 : 0
  name        = var.sg_name

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 514
    to_port     = 514
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9997
    to_port     = 9997
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

# --- Launch EC2 Instance ---
resource "aws_instance" "ossec" {
  ami                    = data.aws_ami.ubuntu_latest.id
  instance_type          = "t3.medium"
  key_name = aws_key_pair.generated_key_pair.key_name
  vpc_security_group_ids = (
  length(data.aws_security_groups.existing.ids) > 0
    ? data.aws_security_groups.existing.ids
    : [aws_security_group.ossec_sg[0].id]
)

  root_block_device {
    volume_size = 30
  }

  tags = {
    Name = "OSSEC"
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
  [ossec]
  ${aws_instance.ossec.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=./keys/${local.final_key_name}.pem ansible_python_interpreter=/usr/bin/python3
  EOT
  filename = "${path.module}/inventory.ini"
}

resource "local_file" "ansible_vars" {
  content = <<-EOT
  ---
  ossec_webui_admin_user: "${var.ossec_webui_admin_user}"
  ossec_webui_admin_pass: "${var.ossec_webui_admin_pass}"
  EOT

  filename = "${path.module}/group_vars/all.yml"
  file_permission = "0644"
}