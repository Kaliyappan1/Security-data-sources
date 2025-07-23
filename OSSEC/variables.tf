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
  default     = "ossec-sg"
}

variable "ossec_webui_admin_pass" {
  type        = string
}

variable "ossec_webui_admin_user" {
  type        = string
}

variable "usermail" {
  type        = string
}

variable "quotahours" {
  description = "Total allowed running hours for the EC2 instance"
  type        = number
}

variable "hoursperday" {
  description = "Maximum allowed hours per day"
  type        = number
}

variable "category" {
  description = "Custom category for the instance"
  type        = string
}

variable "planstartdate" {
  description = "Start date of the EC2 plan in ISO format"
  type        = string
}

variable "servicetype" {
  type        = string
}