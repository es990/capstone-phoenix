variable "aws_region" {
  description = "AWS region to create the state backend resources in"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Project name used for tagging"
  type        = string
  default     = "capstone-phoenix"
}

variable "environment" {
  description = "Environment name used for tagging (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state (e.g. capstone-phoenix-tfstate-yourname)"
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name used for Terraform state locking"
  type        = string
  default     = "capstone-phoenix-tf-lock"
}
