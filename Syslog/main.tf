provider "aws" {
  region     = var.aws_region
}

# Get Latest RHEL 9 AMI (HVM, EBS-backed)
data "aws_ami" "rhel9_latest" {
  most_recent = true

  filter {
    name   = "name"
    values = ["RHEL-9.*x86_64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["309956199498"] # Red Hat official account
}

# --- Generate Random Suffix (for key name uniqueness) ---
resource "random_integer" "suffix" {
  min = 1
  max = 99
}

# --- Define Final Key Name ---
locals {
  key_name_final = "${var.key_name}-${random_integer.suffix.result}"
}

# --- Generate Key Pair Locally ---
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload PEM to S3
resource "aws_s3_object" "upload_pem_key" {
  bucket  = "splunk-deployment-test"
  key     = "clients/${var.usermail}/keys/${local.key_name_final}.pem"
  content = tls_private_key.this.private_key_pem
}

# --- Save PEM File Locally ---
resource "local_file" "pem_file" {
  content              = tls_private_key.this.private_key_pem
  filename             = "keys/${local.key_name_final}.pem"
  file_permission      = "0600"
  directory_permission = "0700"
}

# --- Create AWS Key Pair ---
resource "aws_key_pair" "this" {
  key_name   = local.key_name_final
  public_key = tls_private_key.this.public_key_openssh
}

# --- Check if Security Group Already Exists ---
data "aws_security_groups" "existing" {
  filter {
    name   = "group-name"
    values = [var.sg_name]
  }
}

# --- Create Security Group If Not Exists ---
resource "aws_security_group" "syslog_sg" {
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
    from_port   = 5514
    to_port     = 5514
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
resource "aws_instance" "syslog" {
  ami                    = data.aws_ami.rhel9_latest.id
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = (
  length(data.aws_security_groups.existing.ids) > 0
    ? data.aws_security_groups.existing.ids
    : [aws_security_group.syslog_sg[0].id]
)

  root_block_device {
    volume_size = 30
  }

  tags = {
    Name = "syslog"
  }

}

resource "local_file" "ansible_inventory" {
  content  = <<-EOT
  [syslog]
  ${aws_instance.syslog.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=./keys/${local.key_name_final}.pem ansible_python_interpreter=/usr/bin/python3
  EOT
  filename = "${path.module}/inventory.ini"
}

resource "local_file" "ansible_vars" {
  count = var.splunk_forward_ip != "" && var.splunk_forward_port != null ? 1 : 0

  content = <<-EOT
  ---
  splunk_forward_ip: "${var.splunk_forward_ip}"
  splunk_forward_port: ${var.splunk_forward_port}
  EOT

  filename        = "${path.module}/group_vars/all.yml"
  file_permission = "0644"
}

