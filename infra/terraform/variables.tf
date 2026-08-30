variable "project_name" {
  description = "Project name used for resource naming/tagging"
  type        = string
  default     = "capstone-phoenix"
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-north-1"
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

variable "allowed_admin_cidrs" {
  description = "CIDR blocks allowed to SSH in and reach the k3s API (6443). Set to your own IP/32 - never 0.0.0.0/0."
  type        = list(string)
}

variable "ssh_public_key" {
  description = "Public key material for the AWS key pair (e.g. `file(\"~/.ssh/id_ed25519.pub\")`)"
  type        = string
}

variable "ssh_user" {
  description = "SSH username for the AMI (Ubuntu AMIs use 'ubuntu')"
  type        = string
  default     = "ubuntu"
}

variable "server_instance_type" {
  description = "EC2 instance type for the server (control-plane) node"
  type        = string
  default     = "t3.medium"
}

variable "agent_instance_type" {
  description = "EC2 instance type for agent (worker) nodes"
  type        = string
  default     = "t3.small"
}

variable "agent_count" {
  description = "Number of agent (worker) nodes - 2+ required"
  type        = number
  default     = 2
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB for each instance"
  type        = number
  default     = 20
}
