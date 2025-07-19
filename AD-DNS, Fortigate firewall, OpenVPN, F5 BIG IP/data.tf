data "aws_instances" "existing_instances" {
  filter {
    name   = "tag:Name"
    values = ["FortiGate Firewall", "F5 BIG-IP", "OpenVPN", "AD & DNS"]
  }
}


data "aws_security_groups" "existing_fortigate_firewall_sg" {
  filter {
    name   = "group-name"
    values = ["Terraform-fortigate-firewall-sg"]
  }
}

data "aws_security_groups" "existing_sg_f5" {
  filter {
    name   = "group-name"
    values = ["Terraform-f5-bigip-sg"]
  }
}

data "aws_security_groups" "existing_openvpn_sg" {
  filter {
    name   = "group-name"
    values = ["Terraform-openvpn-sg"]
  }
}

data "aws_security_groups" "existing_ad_dns_sg" {
  filter {
    name   = "group-name"
    values = ["Terraform-ad-dns-sg"]
  }
}

data "aws_ami" "windows_2022" {
  most_recent = true

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["801119661308"] # Amazon's official Windows AMI owner ID
}
