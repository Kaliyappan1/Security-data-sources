output "used_key_name" {
  value = aws_key_pair.this.key_name
}

output "pem_file_path" {
  value = local_file.pem_file.filename
}

output "instance_public_ip" {
  value = aws_instance.ossec.public_ip
}
