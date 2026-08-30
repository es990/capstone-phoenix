variable "project_name" {
  description = "Project name used for resource naming/tagging"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs to place instances in (round-robin across agents)"
  type        = list(string)
}

variable "server_sg_id" {
  description = "Security group ID for the server (control-plane) instance"
  type        = string
}

variable "agent_sg_id" {
  description = "Security group ID for the agent (worker) instances"
  type        = string
}

variable "ssh_public_key" {
  description = "Public key material (e.g. contents of ~/.ssh/id_ed25519.pub) used for the AWS key pair"
  type        = string
}

variable "server_instance_type" {
  description = "EC2 instance type for the server (control-plane) node. One k3s server is fine - no HA control plane needed."
  type        = string
  default     = "t3.medium"
}

variable "agent_instance_type" {
  description = "EC2 instance type for agent (worker) nodes"
  type        = string
  default     = "t3.small"
}

variable "agent_count" {
  description = "Number of agent (worker) nodes - the brief requires 2+ real, separate nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.agent_count >= 2
    error_message = "agent_count must be at least 2 - a single-node cluster does not satisfy the capstone requirement."
  }
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB for each instance"
  type        = number
  default     = 20
}

variable "ami_id_override" {
  description = "Pin to a specific AMI ID instead of always tracking the latest Ubuntu 22.04 build. Currently pinned to what's already running, so a `terraform apply` for something unrelated (like a resize) never forces a surprise full instance replacement just because Canonical published a newer AMI."
  type        = string
  default     = "ami-0742c3087b4157050"
}
