output "server_public_ip" {
  description = "Public (Elastic) IP of the server node - for SSH and kubectl"
  value       = aws_eip.server.public_ip
}

output "server_private_ip" {
  description = "Private IP of the server node - agents join using this"
  value       = aws_instance.server.private_ip
}

output "agent_public_ips" {
  description = "Public (Elastic) IPs of the agent nodes"
  value       = aws_eip.agent[*].public_ip
}

output "agent_private_ips" {
  description = "Private IPs of the agent nodes"
  value       = aws_instance.agent[*].private_ip
}
