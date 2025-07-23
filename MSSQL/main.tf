provider "aws" {
  region     = var.aws_region
}

# --- Get Latest RHEL 8 + SQL Server 2022 Std Edition AMI ---
data "aws_ami" "rhel_sql" {
  most_recent = true

  filter {
    name   = "name"
    values = ["RHEL_8.10-x86_64-SQL_2022_Standard*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["amazon"]
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
resource "aws_security_group" "mssql_sg" {
  count       = length(data.aws_security_groups.existing.ids) == 0 ? 1 : 0
  name        = var.sg_name
  description = "Allow MSSQL + HTTP/HTTPS + SSH"

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
    from_port   = 1433
    to_port     = 1433
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
resource "aws_instance" "mssql" {
  ami                    = data.aws_ami.rhel_sql.id
  instance_type          = "t3.xlarge"
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = (
  length(data.aws_security_groups.existing.ids) > 0
    ? data.aws_security_groups.existing.ids
    : [aws_security_group.mssql_sg[0].id]
)

  root_block_device {
    volume_size = 30
  }

  tags = {
    Name = "MSSQL"
    AutoStop      = true
    ServiceType   = var.servicetype
    Owner         = var.usermail
    UserEmail     = var.usermail
    RunQuotaHours = var.quotahours
    HoursPerDay   = var.hoursperday
    Category      = var.category
    PlanStartDate = var.planstartdate
  }

   # ✅ Install Python3 automatically at boot
    user_data = <<-EOF
            #!/bin/bash
            sudo dnf install python3.12 -y
        EOF

}

resource "local_file" "ansible_inventory" {
  content  = <<-EOT
  [mssql]
  ${aws_instance.mssql.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=./keys/${local.key_name_final}.pem ansible_python_interpreter=/usr/bin/python3.12
  EOT
  filename = "${path.module}/inventory.ini"
}

resource "local_file" "ansible_vars" {
  content = <<-EOT
  ---
  sa_password: "${var.sa_password}"
  splunk_user_password: "${var.splunk_user_password}"
  EOT

  filename = "${path.module}/group_vars/all.yml"
  file_permission = "0644"
}
