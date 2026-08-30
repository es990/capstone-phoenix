variable "project_name" {
  description = "Project name used for resource naming/tagging"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ used"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}
