provider "aws" {
  region = var.aws_region
}

# Get Latest RHEL 9 AMI
data "aws_ami" "rhel9" {
  most_recent = true

  filter {
    name   = "name"
    values = ["RHEL-9.*x86_64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["309956199498"]
}

# Key creation lock table
resource "aws_dynamodb_table" "key_creation_lock" {
  name         = "KeyPairCreationLock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "KeyName"

  attribute {
    name = "KeyName"
    type = "S"
  }

  tags = {
    Purpose = "KeyPair creation locking"
  }
}

# Check key existence
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
  key_check_error = try(coalesce(data.external.check_key.result.error, ""), ""
  key_check_failed = local.key_check_error != "" ? (
    error("Key check failed: ${local.key_check_error}")
  ) : false
  
  final_key_name = replace(
    try(data.external.check_key.result.final_key_name, var.key_name),
    " ", "-"
  )
  
  s3_key_exists   = can(data.external.check_key.result.exists_in_s3) && data.external.check_key.result["exists_in_s3"] == "true"
  aws_key_exists  = can(data.external.check_key.result.exists_in_aws) && data.external.check_key.result["exists_in_aws"] == "true"
  need_new_key    = !(local.s3_key_exists || local.aws_key_exists)
}

# Key material generation
resource "tls_private_key" "generated_key" {
  count     = local.need_new_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS Key Pair
resource "aws_key_pair" "generated_key_pair" {
  count = local.need_new_key ? 1 : 0

  key_name   = local.final_key_name
  public_key = tls_private_key.generated_key[0].public_key_openssh

  lifecycle {
    ignore_changes = [public_key]
  }

  depends_on = [aws_dynamodb_table.key_creation_lock]
}

# Key creation handler
resource "null_resource" "create_key_pair" {
  count = local.need_new_key ? 1 : 0

  triggers = {
    key_name = local.final_key_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      ${path.module}/scripts/create_key.sh \
      "${local.final_key_name}" \
      "${var.aws_region}" \
      "${var.usermail}" \
      "${path.module}/keys"
    EOT
  }

  depends_on = [
    tls_private_key.generated_key,
    aws_key_pair.generated_key_pair
  ]
}

# Store key in S3
resource "aws_s3_object" "upload_pem_key" {
  count  = (local.need_new_key && !local.s3_key_exists) ? 1 : 0
  bucket = "splunk-deployment-test"
  key    = "clients/${var.usermail}/keys/${local.final_key_name}.pem"
  content = tls_private_key.generated_key[0].private_key_pem
  acl    = "private"

  depends_on = [
    null_resource.create_key_pair,
    aws_key_pair.generated_key_pair
  ]
}

# Save key locally
resource "local_file" "pem_file" {
  count = (local.need_new_key && !local.s3_key_exists) ? 1 : 0

  filename        = "${path.module}/keys/${local.final_key_name}.pem"
  content         = tls_private_key.generated_key[0].private_key_pem
  file_permission = "0400"
  directory_permission = "0755"

  depends_on = [
    null_resource.create_key_pair,
    aws_key_pair.generated_key_pair
  ]
}

# Security Group Data
data "aws_security_groups" "existing" {
  filter {
    name   = "group-name"
    values = [var.sg_name]
  }
}

# Security Group Resource
resource "aws_security_group" "mysql_sg" {
  count       = length(data.aws_security_groups.existing.ids) == 0 ? 1 : 0
  name        = var.sg_name
  description = "Allow MYSQL + HTTP/HTTPS + SSH"

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
    from_port   = 3306
    to_port     = 3306
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

# EC2 Instance
resource "aws_instance" "mysql" {
  ami           = data.aws_ami.rhel9.id
  instance_type = "t3.medium"
  key_name      = local.final_key_name

  vpc_security_group_ids = length(data.aws_security_groups.existing.ids) > 0 ? 
    data.aws_security_groups.existing.ids : 
    [aws_security_group.mysql_sg[0].id]

  root_block_device {
    volume_size = 30
    encrypted   = true
  }

  depends_on = [
    aws_key_pair.generated_key_pair,
    aws_s3_object.upload_pem_key,
    null_resource.create_key_pair
  ]

  tags = merge(
    {
      Name        = "MYSQL"
      AutoStop    = "true"
      ServiceType = var.servicetype
      Category    = var.category
    },
    {
      Owner         = var.usermail,
      UserEmail     = var.usermail,
      RunQuotaHours = var.quotahours,
      HoursPerDay   = var.hoursperday,
      PlanStartDate = var.planstartdate
    }
  )

  lifecycle {
    ignore_changes = [
      security_groups,
      key_name
    ]
  }
}
resource "local_file" "ansible_inventory" {
  content  = <<-EOT
  [mysql]
  ${aws_instance.mysql.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=./keys/${local.final_key_name}.pem ansible_python_interpreter=/usr/bin/python3
  EOT
  filename = "${path.module}/inventory.ini"
}

resource "local_file" "ansible_vars" {
  content = <<-EOT
  ---
  mysql_root_password: "${var.mysql_root_password}"
  splunk_user: "${var.splunk_user}"
  splunk_password: "${var.splunk_user_password}"
  root_password_set_marker: "/var/lib/mysql/.mysql_password_set"
  EOT

  filename = "${path.module}/group_vars/all.yml"
  file_permission = "0644"
}
