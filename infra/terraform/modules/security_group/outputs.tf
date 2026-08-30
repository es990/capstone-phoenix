output "server_sg_id" {
  description = "ID of the server (control-plane) security group"
  value       = aws_security_group.server.id
}

output "agent_sg_id" {
  description = "ID of the agent (worker) security group"
  value       = aws_security_group.agent.id
}
