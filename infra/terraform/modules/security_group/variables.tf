variable "project_name" {
  description = "Project name used for resource naming/tagging"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC these security groups belong to"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC, used to scope internal-only rules (e.g. NodePort range)"
  type        = string
}

variable "allowed_admin_cidrs" {
  description = "CIDR blocks allowed to SSH in and reach the k3s API (6443) for kubectl/Ansible. Set this to your own IP/32 - never 0.0.0.0/0."
  type        = list(string)
}
