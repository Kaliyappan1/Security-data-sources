output "used_key_name" {
  value = aws_key_pair.this.key_name
}

output "pem_file_path" {
  value = local_file.pem_file.filename
}

output "instance_public_ip" {
  value = aws_instance.mysql.public_ip
}

output "pem_s3_url" {
  value = "s3://${aws_s3_object.upload_pem_key.bucket}/${aws_s3_object.upload_pem_key.key}"
}

output "instance_id" {
  value = aws_instance.mysql.id
}