variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Base name for the key pair"
  type        = string
  default     = "mssql-key"
}

variable "sg_name" {
  description = "Security group name to check or create"
  type        = string
  default     = "mssql-sg"
}

variable "sa_password" {
  type        = string
  description = "MSSQL SA password"
}

variable "splunk_user_password" {
  type        = string
  description = "MSSQL SA password"
}

variable "usermail" {
  type        = string
}


