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
  default     = "syslog-sg"
}

variable "splunk_forward_ip" {
  type        = string
  default     = ""
  description = "Optional: IP address of the Splunk forwarder"
}

variable "splunk_forward_port" {
  type        = number
  default     = null
  description = "Optional: TCP port to forward logs to Splunk"
}
