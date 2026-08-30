# infra/terraform/ — provision the nodes

Seed this from your single-EC2 Terraform and grow it to a small fleet.

**Must produce:**
- 1 control-plane VM + **2+ worker VMs** (small instances are fine).
- Modules: `network`, `security_group`/firewall, `compute`.
- **Remote state** (S3 + DynamoDB lock, GCS, etc.) — no `*.tfstate` in git.
- Firewall: world-open only `80`/`443`; `22` from your IP; `6443` and node ports NOT public.
- `outputs.tf`: control-plane + worker IPs (public for SSH, private for k3s join) for Ansible.
- Everything parameterized in `variables.tf`; ship a `terraform.tfvars.example` (real one gitignored).

**Acceptance:** `terraform apply` from clean → you can SSH to every node; `terraform destroy`
leaves nothing behind. Re-running `plan` after apply shows no drift.

> Keep infra lean: one k3s server is fine — you do NOT need a multi-master/HA control plane.
> The difficulty in this capstone lives in Kubernetes, not the control plane.


##################################################################################################################################

# infra/terraform/ — provision the nodes

## Layout

```
infra/terraform/
├── bootstrap/            # one-time: S3 bucket + DynamoDB table for remote state
├── modules/
│   ├── network/          # VPC, public subnets, IGW, routing
│   ├── security_group/   # firewall for server (control-plane) + agents (workers)
│   └── compute/          # EC2 instances, key pair, Elastic IPs
├── templates/
│   └── inventory.tpl     # renders infra/ansible/inventory/hosts.ini from TF outputs
├── providers.tf
├── versions.tf
├── main.tf               # wires the modules together
├── variables.tf
├── outputs.tf
└── terraform.tfvars.example
```

## Usage

**Step 1 — bootstrap the remote state backend (once, ever):**

```bash
cd bootstrap
terraform init
terraform apply -var="state_bucket_name=capstone-phoenix-tfstate-<yourname>"
# note the outputs: state_bucket_name, lock_table_name
```

**Step 2 — point the root module at that backend:**

```bash
cd ..
terraform init \
  -backend-config="bucket=capstone-phoenix-tfstate-<yourname>" \
  -backend-config="dynamodb_table=capstone-phoenix-tf-lock" \
  -backend-config="region=us-east-1"
```

**Step 3 — configure your variables:**

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: your IP for allowed_admin_cidrs, your SSH public key, etc.
```

**Step 4 — plan and apply:**

```bash
terraform plan
terraform apply
```

This creates the VPC, security groups, and EC2 instances (1 server + 2+
agents), and writes `../ansible/inventory/hosts.ini` automatically —
Ansible picks up exactly where this leaves off.

**Step 5 — verify (acceptance criteria from the brief):**

```bash
terraform output
ssh $(terraform output -raw ssh_server_command | cut -d' ' -f2)   # SSH works
terraform plan                                                     # no drift after apply
terraform destroy                                                  # leaves nothing behind
```

## How this satisfies the brief's firewall requirement

> "Firewall: world-open only `80`/`443`; `22` from your IP; `6443` and node ports NOT public."

- `80`/`443` — open to `0.0.0.0/0` on the server (Traefik/ingress-nginx + ACME challenge).
- `22` — open only to `var.allowed_admin_cidrs` on both server and agents.
- `6443` (k3s API) — open only from the agent security group (cluster join) and
  `allowed_admin_cidrs` (your kubectl/Ansible) — never `0.0.0.0/0`.
- Node-to-node ports (Flannel VXLAN `8472/udp`, kubelet `10250`) are scoped to the
  cluster's own security groups.
- NodePort range `30000-32767` is scoped to the VPC CIDR only, not the internet.

## Notes

- One k3s server is intentional — the brief explicitly says you do not need a
  multi-master/HA control plane for this capstone.
- `agent_count` has a validation rule requiring ≥2, since a single-node "cluster"
  fails the hard constraint in the brief.
- The AMI is looked up dynamically via `data "aws_ami"` (latest Ubuntu 22.04),
  never hardcoded.
