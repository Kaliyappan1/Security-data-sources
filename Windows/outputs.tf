output "instance_id" {
  value = aws_instance.ad_dns.id
}

output "instance_public_ip" {
  value = aws_instance.ad_dns.public_ip
}

output "pem_s3_url" {
  value = (
    length(aws_s3_object.upload_pem_key) > 0 ?
    "s3://${aws_s3_object.upload_pem_key[0].bucket}/${aws_s3_object.upload_pem_key[0].key}" :
    "Key not uploaded (already exists in S3)"
  )
}