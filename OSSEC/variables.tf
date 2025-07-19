variable "aws_access_key" {
  description = "AWS Access Key"
  type        = string
  sensitive   = true
}

variable "key_name" {
  description = "Base name for the key pair"
  type        = string
}

variable "sg_name" {
  description = "Security group name to check or create"
  type        = string
  default     = "ossec-sg"
}

variable "ossec_webui_admin_pass" {
  type        = string
}

variable "ossec_webui_admin_user" {
  type        = string
}


