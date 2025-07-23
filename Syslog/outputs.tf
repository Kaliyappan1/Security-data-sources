output "instance_public_ip" {
  value = aws_instance.syslog.public_ip
}

output "pem_s3_url" {
  value = "s3://${aws_s3_object.upload_pem_key.bucket}/${aws_s3_object.upload_pem_key.key}"
}

output "instance_id" {
  value = aws_instance.syslog.id
}