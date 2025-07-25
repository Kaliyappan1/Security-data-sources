variable "aws_region" {
  description = "AWS Region"
  type        = string
}

variable "instance_name" {
  description = "Base name for the EC2 instances"
  type        = string
}

variable "usermail" {
  description = "User email for tagging and S3 folder"
  type        = string
}

variable "key_name" {
  description = "Base name for the key pair"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "storage_size" {
  description = "Size of the root EBS volume"
  type        = number
}

variable "quotahours" {
  description = "Maximum allowed runtime hours"
  type        = number
}

variable "hoursperday" {
  description = "Allowed hours per day"
  type        = number
}

variable "category" {
  description = "Instance category"
  type        = string
}

variable "planstartdate" {
  description = "Plan start date"
  type        = string
}

variable "servicetype" {
  type        = string
}