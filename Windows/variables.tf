variable "region" {
    description = "The AWS region to deploy resources"
    type        = string
}

variable "key_name" {
  description = "The key name for the EC2 instances"
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