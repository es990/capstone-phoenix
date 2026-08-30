output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.network.vpc_id
}

output "server_public_ip" {
  description = "Public (Elastic) IP of the server node - use for kubectl and SSH"
  value       = module.compute.server_public_ip
}

output "server_private_ip" {
  description = "Private IP of the server node"
  value       = module.compute.server_private_ip
}

output "agent_public_ips" {
  description = "Public (Elastic) IPs of the agent nodes"
  value       = module.compute.agent_public_ips
}

output "ssh_server_command" {
  description = "Convenience SSH command for the server node"
  value       = "ssh ${var.ssh_user}@${module.compute.server_public_ip}"
}
