variable "region" {
  type        = string
  description = "AWS region to deploy resources"
}

variable "my_ip" {
  type        = string
  description = "Your public IP in CIDR notation (10.89.76.93/32)"
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket for Terraform remote state"
}

variable "state_key" {
  type        = string
  description = "Key (path) for storing the Terraform state file inside the S3 bucket"
}

variable "dynamodb_table" {
  type        = string
  description = "DynamoDB table for Terraform state locking"
}

variable "aws_profile" {
  type        = string
  description = "Optional AWS CLI profile to use"
  default     = ""
}

variable "project" {
  type        = string
  description = "Short project/prefix used for resource names"
  default     = "assign1"
}

variable "athena_results_prefix" {
  type        = string
  description = "S3 prefix for Athena query results"
  default     = "athena-results/"
}
variable "create_athena_workgroup" {
  type    = bool
  default = false
}
