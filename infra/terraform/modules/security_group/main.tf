############################################
# Module: security_group
#
# Enforces the capstone's hard constraint directly:
#   "world-open only 80/443; 22 from your IP; 6443 and node ports NOT public."
#
# Two groups:
#   - server: the k3s control-plane node
#   - agent:  the k3s worker nodes
#
# Rules that reference "the other" group are declared as standalone
# aws_security_group_rule resources to avoid a circular dependency
# between the two aws_security_group resources.
############################################

resource "aws_security_group" "server" {
  name        = "${var.project_name}-server-sg"
  description = "Security group for the k3s server (control-plane) node"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-server-sg"
    Project = var.project_name
  }
}

resource "aws_security_group" "agent" {
  name        = "${var.project_name}-agent-sg"
  description = "Security group for k3s agent (worker) nodes"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-agent-sg"
    Project = var.project_name
  }
}

# --- Server (control-plane) ingress ----------------------------------

resource "aws_security_group_rule" "server_ssh" {
  type              = "ingress"
  description       = "SSH - your IP only"
  security_group_id = aws_security_group.server.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.allowed_admin_cidrs
}

resource "aws_security_group_rule" "server_http" {
  type              = "ingress"
  description       = "HTTP - world-open (ingress + ACME HTTP-01 challenge)"
  security_group_id = aws_security_group.server.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "server_https" {
  type              = "ingress"
  description       = "HTTPS - world-open (TaskApp on your real domain)"
  security_group_id = aws_security_group.server.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "server_k8s_api_from_agents" {
  type                     = "ingress"
  description              = "Kubernetes API (6443) - agents only, never public"
  security_group_id        = aws_security_group.server.id
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.agent.id
}

resource "aws_security_group_rule" "server_k8s_api_from_admin" {
  type              = "ingress"
  description       = "Kubernetes API (6443) - your IP only, for kubectl/Ansible, never public"
  security_group_id = aws_security_group.server.id
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = var.allowed_admin_cidrs
}

resource "aws_security_group_rule" "server_flannel_vxlan_from_agents" {
  type                     = "ingress"
  description              = "Flannel VXLAN overlay traffic from agents - node port, not public"
  security_group_id        = aws_security_group.server.id
  from_port                = 8472
  to_port                  = 8472
  protocol                 = "udp"
  source_security_group_id = aws_security_group.agent.id
}

resource "aws_security_group_rule" "server_kubelet_from_agents" {
  type                     = "ingress"
  description              = "Kubelet API from agents - node port, not public"
  security_group_id        = aws_security_group.server.id
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.agent.id
}

# --- Agent (worker) ingress --------------------------------------------

resource "aws_security_group_rule" "agent_ssh" {
  type              = "ingress"
  description       = "SSH - your IP only"
  security_group_id = aws_security_group.agent.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.allowed_admin_cidrs
}

resource "aws_security_group_rule" "agent_flannel_vxlan_from_server" {
  type                     = "ingress"
  description              = "Flannel VXLAN overlay traffic from server - node port, not public"
  security_group_id        = aws_security_group.agent.id
  from_port                = 8472
  to_port                  = 8472
  protocol                 = "udp"
  source_security_group_id = aws_security_group.server.id
}

resource "aws_security_group_rule" "agent_flannel_vxlan_between_agents" {
  type              = "ingress"
  description       = "Flannel VXLAN overlay traffic between agents - node port, not public"
  security_group_id = aws_security_group.agent.id
  from_port         = 8472
  to_port           = 8472
  protocol          = "udp"
  self              = true
}

resource "aws_security_group_rule" "agent_kubelet_from_server" {
  type                     = "ingress"
  description              = "Kubelet API from server - node port, not public"
  security_group_id        = aws_security_group.agent.id
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.server.id
}

resource "aws_security_group_rule" "agent_nodeport_range_internal" {
  type              = "ingress"
  description       = "NodePort range - internal VPC only, not public"
  security_group_id = aws_security_group.agent.id
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}
