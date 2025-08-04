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
  key_check_error   = try(data.external.check_key.result.error, "")
  key_check_failed  = local.key_check_error != "" ? error("Key check failed: ${local.key_check_error}") : false
  final_key_name    = data.external.check_key.result.final_key_name
  s3_key_exists     = data.external.check_key.result["exists_in_s3"] == "true"
  aws_key_exists    = data.external.check_key.result["exists_in_aws"] == "true"
  need_new_key      = !(local.s3_key_exists && local.aws_key_exists)
}

resource "tls_private_key" "generated_key" {
  count     = local.need_new_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key_pair" {
  count      = local.need_new_key ? 1 : 0
  key_name   = local.final_key_name
  public_key = tls_private_key.generated_key[0].public_key_openssh

  lifecycle {
    ignore_changes = [public_key]
  }
}

resource "aws_s3_object" "upload_pem_key" {
  count   = (local.need_new_key && !local.s3_key_exists) ? 1 : 0
  bucket  = "splunk-deployment-test"
  key     = "clients/${var.usermail}/keys/${local.final_key_name}.pem"
  content = tls_private_key.generated_key[0].private_key_pem

  depends_on = [aws_key_pair.generated_key_pair]
}

resource "local_file" "pem_file" {
  count           = (local.need_new_key && !local.s3_key_exists) ? 1 : 0
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
resource "aws_security_group" "Terraform-ad_dns-sg" {
  count       = length(data.aws_security_groups.existing.ids) == 0 ? 1 : 0
  name        = var.sg_name
  description = "Security group for AD & DNS"

  dynamic "ingress" {
    for_each = [80, 88, 53, 464, 5985, 5986, 3389, 636, 389]
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

resource "aws_instance" "ad_dns" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = "m4.large"
  key_name               = data.external.check_key.result.final_key_name
  associate_public_ip_address = true
  get_password_data      = true

  vpc_security_group_ids = (
  length(data.aws_security_groups.existing.ids) > 0
    ? data.aws_security_groups.existing.ids
    : [aws_security_group.Terraform-ad_dns-sg[0].id]
)

  root_block_device {
    volume_size = 50
  }

  user_data = <<EOF
    <powershell>
    # Enable WinRM
    winrm quickconfig -q
    winrm set winrm/config/service '@{AllowUnencrypted="true"}'
    winrm set winrm/config/service/auth '@{Basic="true"}'
    winrm set winrm/config/listener?Address=*+Transport=HTTP '@{Port="5985"}'
    netsh advfirewall firewall add rule name="WinRM HTTP" dir=in action=allow protocol=TCP localport=5985
    </powershell>
  EOF

  tags = {
    Name           = "Windows(AD&DNS)"
    AutoStop       = true
    ServiceType    = var.servicetype
    Owner          = var.usermail
    UserEmail      = var.usermail
    RunQuotaHours  = var.quotahours
    HoursPerDay    = var.hoursperday
    Category       = var.category
    PlanStartDate  = var.planstartdate
  }
}

resource "local_file" "windows_inventory" {
  depends_on = [aws_instance.ad_dns]
  filename   = "inventory.ini"

  content = <<EOF
[windows]
windows_server ansible_host=${aws_instance.ad_dns.public_ip} ansible_user=Administrator ansible_password="${rsadecrypt(aws_instance.ad_dns.password_data, file("${path.module}/keys/${local.final_key_name}.pem"))}" ansible_connection=winrm ansible_winrm_transport=basic ansible_port=5985 ansible_winrm_server_cert_validation=ignore
EOF
}
