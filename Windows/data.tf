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
