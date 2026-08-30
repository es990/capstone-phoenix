############################################
# Root module
# Wires network -> security_group -> compute together and renders
# infra/ansible/inventory/hosts.ini from the resulting IPs, so
# Terraform and Ansible can never drift out of sync.
############################################

module "network" {
  source = "./modules/network"

  project_name        = var.project_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
}

module "security_group" {
  source = "./modules/security_group"

  project_name        = var.project_name
  vpc_id              = module.network.vpc_id
  vpc_cidr            = module.network.vpc_cidr
  allowed_admin_cidrs = var.allowed_admin_cidrs
}

module "compute" {
  source = "./modules/compute"

  project_name         = var.project_name
  subnet_ids           = module.network.public_subnet_ids
  server_sg_id         = module.security_group.server_sg_id
  agent_sg_id          = module.security_group.agent_sg_id
  ssh_public_key       = var.ssh_public_key
  server_instance_type = var.server_instance_type
  agent_instance_type  = var.agent_instance_type
  agent_count          = var.agent_count
  root_volume_size_gb  = var.root_volume_size_gb
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.ini"

  content = templatefile("${path.module}/templates/inventory.tpl", {
    server_public_ip  = module.compute.server_public_ip
    server_private_ip = module.compute.server_private_ip
    agent_public_ips  = module.compute.agent_public_ips
    ssh_user          = var.ssh_user
  })
}
