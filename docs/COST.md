# Cost

Figures below are current on-demand AWS pricing (US baseline; `eu-north-1`
typically runs close to, occasionally a few percent above, these numbers -
check AWS Cost Explorer for your account's actual billed amount, since
this is a methodology, not a guaranteed invoice).

## Monthly itemized cost

| Item | Spec | Qty | $/mo |
|---|---|---:|---:|
| control-plane VM | t3.medium (2 vCPU / 4 GiB), eu-north-1 | 1 | ~$30.37 |
| worker VMs | t3.small (2 vCPU / 2 GiB), eu-north-1 | 2 | ~$30.37 |
| load balancer / elastic IP | 3 Elastic IPs, all attached to running instances (AWS only charges for an *unattached* EIP, ~$0.005/hr each) | 3 | $0 |
| block storage (PVC) | 60 GB gp3 root volumes (20 GB × 3 nodes) + 5 Gi Postgres PVC, at $0.08/GB-month | ~65 GB | ~$5.20 |
| object storage (state, backups) | S3 bucket for Terraform state (a few KB) + DynamoDB pay-per-request lock table (a handful of requests per `apply`) | — | ~$0.05 |
| DNS / domain | nip.io wildcard-DNS-by-IP - no domain registration, no Route 53 hosted zone, no propagation wait | 0 | $0 |
| **Total** | | | **~$66/mo** |

Compute is ~92% of the bill - the dominant lever if this needs to get
cheaper is instance choice, not storage or networking.

## Compared to the single-server Compose+Portainer deploy

- That stack (one VM running the app, DB, and reverse proxy together via
  Docker Compose) costs roughly **~$17/mo**: one `t3.small`
  (~$15.18) + a small EBS root volume (~$1.60) + one attached Elastic IP
  ($0). I don't have your exact figure from that earlier assignment on
  hand - swap this estimate for your real number if you have it.
- This cluster costs **~$66/mo** - roughly **3.9× more**.
- **What the extra ~$49/mo buys:** a control plane that survives a single
  node dying (proven for real during this build's disaster-recovery
  incident - see `RUNBOOK.md`); backend that autoscales 2→6 replicas
  under load instead of falling over; zero-downtime deploys instead of a
  few seconds of `docker compose up -d` downtime; and a GitOps pipeline
  where the recovery procedure is "reapply an Application resource," not
  "remember every manual step by hand." **When it's genuinely not
  worth it:** a low-traffic personal project, an internal tool with a
  handful of known users, or anything where an occasional few seconds of
  downtime during a deploy is a non-issue - for those, the single-server
  Compose deploy is the more honest choice, not a lesser one.

## How I'd halve this

The single biggest lever is the control-plane resize we ended up needing
mid-project: taint `k3s-server` against scheduling ordinary workload
Pods (so Argo CD and the app never share memory with the control plane
again), then downsize it back to `t3.small` - the resize to `t3.medium`
was a reaction to memory pressure *caused by* co-scheduling, not an
inherent requirement of running k3s's control plane alone. That alone
claws back roughly $15/mo. Beyond that: the two agent nodes are prime
candidates for Spot pricing (up to ~70% off on-demand) since they're
stateless, self-healing `Deployment` replicas behind an HPA - a Spot
interruption just means the scheduler reschedules onto the remaining
node, no different in kind from the node-drain scenario already handled
in `RUNBOOK.md`. Postgres and the control plane, by contrast, are poor
Spot candidates given their singleton, stateful nature.
