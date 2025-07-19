variable "aws_access_key" {
  description = "AWS Access Key"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Key"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Base name for the key pair"
  type        = string
}

variable "sg_name" {
  description = "Security group name to check or create"
  type        = string
  default     = "mysql-sg"
}

variable "mysql_root_password" {
  type        = string
}

variable "splunk_user" {
  type        = string
}

variable "splunk_user_password" {
  type        = string
}