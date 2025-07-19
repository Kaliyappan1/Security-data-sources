provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}


resource "aws_instance" "Fortigate-Firewall" {
  count         = var.FORTIGATE_FIREWALL ? 1 : 0
  ami           = lookup(var.ami_map[var.region], "fortigate", "")
  instance_type = "c6i.large"
  key_name      = var.key_name
  security_groups = length(aws_security_group.Terraform-Fortigate-Firewall-sg) > 0 ? [aws_security_group.Terraform-Fortigate-Firewall-sg[0].name] : []
  tags = { Name = "FortiGate Firewall" }

  associate_public_ip_address = true

  user_data = <<-EOF
  # Wait for the system to be ready
      sleep 200
  config system admin
      edit "admin"
          set password SoftMania123!
      next
  end
  EOF

}

resource "aws_eip" "FortiGate-Firewall_eip" {
  count    = var.FORTIGATE_FIREWALL ? 1 : 0
  instance = aws_instance.Fortigate-Firewall[0].id
}

resource "aws_security_group" "Terraform-Fortigate-Firewall-sg" {
  count = (var.FORTIGATE_FIREWALL && length(data.aws_security_groups.existing_fortigate_firewall_sg.ids) == 0) ? 1 : 0


  name        = "Terraform-fortigate-firewall-sg"
  description = "Security group for FortiGate Firewall"

  dynamic "ingress" {
    for_each = [ 22, 80, 443, 541, 3000, 8080]
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

resource "aws_instance" "f5_bigip" {
  count         = var.F5_BIG_IP ? 1 : 0
  ami           = lookup(var.ami_map[var.region], "f5_bigip", "")
  instance_type = "t2.medium"
  key_name      = var.key_name
  security_groups = length(data.aws_security_groups.existing_sg_f5.ids) > 0 ? [data.aws_security_groups.existing_sg_f5.ids[0]] : (var.F5_BIG_IP ? [aws_security_group.Terraform-f5_bigip-sg[0].name] : [])

  tags = { Name = "F5 BIG-IP" }

  associate_public_ip_address = true

  user_data = <<-EOF
      #!/bin/bash
      # Wait for the system to be ready
      sleep 70

      # Run tmsh command to change the password
      tmsh modify auth user admin password SoftMania123

      # Save the configuration
      tmsh save sys config
      EOF

  depends_on = [aws_security_group.Terraform-f5_bigip-sg]
}

resource "aws_eip" "f5_bigip_eip" {
  count    = var.F5_BIG_IP ? 1 : 0
  instance = aws_instance.f5_bigip[0].id
}

resource "aws_security_group" "Terraform-f5_bigip-sg" {
  count = (var.F5_BIG_IP && length(data.aws_security_groups.existing_sg_f5.ids) == 0) ? 1 : 0

  name        = "Terraform-f5-bigip-sg"
  description = "Security group for F5 BIG-IP"

  dynamic "ingress" {
    for_each = [22, 80, 443, 541, 8443]
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

resource "aws_instance" "openvpn" {
  count         = var.OPEN_VPN ? 1 : 0
  ami           = lookup(var.ami_map[var.region], "openvpn", "")
  instance_type = "t2.small"
  key_name      = var.key_name
  security_groups = length(data.aws_security_groups.existing_openvpn_sg.ids) > 0 ? [data.aws_security_groups.existing_openvpn_sg.ids[0]] : (var.OPEN_VPN ? [aws_security_group.Terraform-openvpn-sg[0].name] : [])

  tags = { Name = "OpenVPN" }

  associate_public_ip_address = true

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "openvpnas"
      private_key = file("${var.key_name}.pem")
      host        = self.public_ip
    }

    inline = [
      "echo '${var.ssh_public_key}' >> ~/.ssh/authorized_keys"
    ]
  }
}

resource "aws_eip" "openvpn_eip" {
  count    = var.OPEN_VPN ? 1 : 0
  instance = aws_instance.openvpn[0].id
}

resource "aws_security_group" "Terraform-openvpn-sg" {
  count = (var.OPEN_VPN && length(data.aws_security_groups.existing_openvpn_sg.ids) == 0) ? 1 : 0

  name        = "Terraform-openvpn-sg"
  description = "Security group for OpenVPN"

  dynamic "ingress" {
    for_each = [22, 443, 943, 945]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ad_dns" {
  count         = var.AD_DNS ? 1 : 0
  ami           = data.aws_ami.windows_2022.id
  instance_type = "m4.large"
  key_name      = var.key_name
  security_groups = length(data.aws_security_groups.existing_ad_dns_sg.ids) > 0 ? [data.aws_security_groups.existing_ad_dns_sg.ids[0]] : (var.AD_DNS ? [aws_security_group.Terraform-ad_dns-sg[0].name] : [])

  tags = { Name = "AD & DNS" }

  root_block_device {
    volume_size = 50
  }

  get_password_data           = true # Enable password retrieval

  associate_public_ip_address = true

  # Automatically enable WinRM using PowerShell
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
}

resource "aws_eip" "ad_dns_eip" {
  count    = var.AD_DNS ? 1 : 0
  instance = aws_instance.ad_dns[0].id
}


resource "aws_security_group" "Terraform-ad_dns-sg" {
  count = (var.AD_DNS && length(data.aws_security_groups.existing_ad_dns_sg.ids) == 0) ? 1 : 0

  name        = "Terraform-ad-dns-sg"
  description = "Security group for AD & DNS"

  # Allow WinRM, RDP, and required AD & DNS ports
  dynamic "ingress" {
    for_each = [80, 5985, 5986, 3389, 53, 636, 389, 88, 464]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "time_sleep" "wait_10_seconds" {
  depends_on = [aws_instance.openvpn, aws_eip.openvpn_eip]
  create_duration = "10s"
}

resource "local_file" "ovpn_inventory" {
  count = var.OPEN_VPN ? 1 : 0
  depends_on = [time_sleep.wait_10_seconds]
  filename   = "ovpn.ini"

  content = <<EOF
[openvpn_servers]
openvpn_host ansible_host=${aws_eip.openvpn_eip[0].public_ip} ansible_user=openvpnas
EOF
}

resource "local_file" "windows_inventory" {
  count = var.AD_DNS ? 1 : 0
  depends_on = [aws_instance.ad_dns]
  filename   = "inventory.ini"

  content = <<EOF
[windows]
windows_server ansible_host=${aws_eip.ad_dns_eip[0].public_ip} ansible_user=Administrator ansible_password="${rsadecrypt(aws_instance.ad_dns[0].password_data, file("${var.key_name}.pem"))}" ansible_connection=winrm ansible_winrm_transport=basic ansible_port=5985 ansible_winrm_server_cert_validation=ignore
EOF
}

