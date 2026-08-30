############################################
# Module: compute
# 1 server (control-plane) + N agent (worker) EC2 instances, each with
# an Elastic IP so addresses survive stop/start. AMI is looked up
# dynamically - never hardcoded - and everything else comes from variables.
############################################

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key
}

# --- Server (control-plane) --------------------------------------------

resource "aws_instance" "server" {
  ami                         = var.ami_id_override
  instance_type               = var.server_instance_type
  subnet_id                   = var.subnet_ids[0]
  vpc_security_group_ids      = [var.server_sg_id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name    = "${var.project_name}-server"
    Project = var.project_name
    Role    = "k3s-server"
  }
}

resource "aws_eip" "server" {
  instance = aws_instance.server.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-server-eip"
    Project = var.project_name
  }
}

# --- Agents (workers) ---------------------------------------------------

resource "aws_instance" "agent" {
  count = var.agent_count

  ami                         = var.ami_id_override
  instance_type               = var.agent_instance_type
  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids      = [var.agent_sg_id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name    = "${var.project_name}-agent-${count.index + 1}"
    Project = var.project_name
    Role    = "k3s-agent"
  }
}

resource "aws_eip" "agent" {
  count = var.agent_count

  instance = aws_instance.agent[count.index].id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-agent-${count.index + 1}-eip"
    Project = var.project_name
  }
}
