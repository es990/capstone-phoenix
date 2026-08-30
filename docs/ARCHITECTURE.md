# Architecture

## 1. Topology diagram

```
                              Internet
                                 │
                          DNS via nip.io
                (no real domain / Route 53 needed -
                 taskapp.amara.<server-public-ip>.nip.io
                 resolves straight back to the server's
                 Elastic IP)
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │  k3s-server (control-    │
                    │  plane, t3.medium)       │
                    │  Traefik (k3s bundled)   │──TLS terminated by
                    │  cert-manager ClusterIssuer   cert-manager +
                    │  Argo CD                 │  Let's Encrypt (HTTP01)
                    └────────────┬─────────────┘
                                 │
              ┌──────────────────┴──────────────────┐
              ▼                                      ▼
   frontend Service (:80)                   backend Service (:5000)
   → frontend Pods (2, spread            → backend Pods (2-6 via HPA,
     across agent-1/agent-2)               spread across nodes)
              │                                      │
              │  nginx proxies /api internally        │
              └──────────────────────────────────────▶│
                                                        ▼
                                        postgres Service (headless)
                                        → postgres-0 (StatefulSet,
                                          PVC on whichever node it's
                                          scheduled to - local-path)
```

Three nodes total: one `k3s-server` (control-plane, also schedulable -
not tainted, since a 3-node cluster doesn't have headroom to dedicate a
whole node to nothing but etcd/API-server duty) and two `agents`
(workers). Frontend and backend replicas spread across nodes via
`topologySpreadConstraints`; Postgres is a single StatefulSet replica -
see §4 for why that's still safe.

## 2. Node & network

- **Nodes:** 1× `k3s-server` (t3.medium, 2 vCPU / 4 GiB - resized up
  from t3.small after a real memory-exhaustion incident, see
  `RUNBOOK.md`), 2× agent (t3.small, 2 vCPU / 2 GiB each). All in
  `eu-north-1` (Stockholm), spread across `eu-north-1a`/`eu-north-1b`.
- **CIDR / subnets:** VPC `10.20.0.0/16`, two public subnets
  (`10.20.1.0/24`, `10.20.2.0/24`), one per AZ. Public subnets were a
  deliberate choice for a 3-node capstone cluster - nodes need public
  IPs for SSH/Ansible and to serve ingress traffic directly, with no
  separate load-balancer tier. Access is locked down at the security-group
  and NetworkPolicy layers instead of the subnet layer.
- **Firewall (what's open, what's not, and why 6443 stays closed):**
  - `80`/`443` - open to `0.0.0.0/0` on the server. This is the actual
    front door; nothing else needs to be public.
  - `22` - open only to the operator's current admin IP (kept in sync via
    Terraform on IP changes, and mirrored at the UFW/host level too via an
    Ansible task that re-detects the current IP on every run - defense in
    depth, not just one layer).
  - `6443` (Kubernetes API) - **never public.** Open only from the agent
    security group (so agents can join the cluster) and the admin IP
    (so `kubectl`/Ansible work from the operator's machine). This is
    enforced at three independent layers that all have to agree: the AWS
    security group, UFW on the host, and (implicitly) the fact that
    nothing routes API traffic through the public Ingress at all.
  - Node-to-node ports (Flannel VXLAN `8472/udp`, kubelet `10250/tcp`,
    NodePort range `30000-32767`) - scoped to the VPC CIDR only, both at
    the security-group and UFW level.

## 3. Request flow

A browser resolves `taskapp.amara.<server-ip>.nip.io` straight to the
server's Elastic IP (no DNS record ever created - nip.io encodes the IP
in the hostname itself). Traefik (k3s's bundled ingress controller)
terminates TLS using a certificate cert-manager obtained from Let's
Encrypt via an HTTP-01 challenge, then routes the request - based on a
single host rule - to the `frontend` Service on port 80, which
load-balances across the frontend Pods. The frontend's own nginx config
proxies any `/api/*` path internally to `http://backend:5000`, so the
Ingress itself never needs to know the backend Service exists. The
backend connects to Postgres at `postgres:5432` (the StatefulSet's
headless Service, giving `postgres-0` a stable DNS name regardless of
which node it's scheduled to).

## 4. The single-server assumptions we fixed

| Single-server assumption | Why it breaks at scale | How we fixed it |
|---|---|---|
| Migrations run in the app's own entrypoint on boot | 2+ backend replicas would independently race on `alembic upgrade head` against the same database | Standalone `migration-job.yaml`, a `batch/v1` Job wired as an Argo CD **PostSync** hook (not PreSync - see `RUNBOOK.md`'s incident log for why that ordering matters), never baked into the Deployment |
| A named Docker volume on the host for Postgres data | Pods reschedule across nodes; a host-local volume doesn't follow them | `StatefulSet` + `volumeClaimTemplates` on k3s's `local-path` storage class - the PVC is a real Kubernetes object independent of any one node, and re-attaches wherever the Pod is rescheduled |
| `ports:` published directly on the host | Many Pods, many nodes, one public front door needed | `Ingress` (Traefik) + ordinary `ClusterIP` Services - the only thing ever exposed to the internet is 80/443 on the Ingress, not individual container ports |
| A container that just restarts if it dies | No automatic replacement, no awareness of *why* it's unhealthy, no protection during voluntary disruptions (node drains, upgrades) | `Deployment` (self-healing replica count) + liveness/readiness/startup probes against real endpoints (`/api/health`, `/healthz`) + `PodDisruptionBudget` (`minAvailable: 1`) so a node drain can't take out every replica of a tier at once |
| `docker compose up -d` for a new version - brief downtime is fine | Multiple real users hitting the app during a deploy | `RollingUpdate` strategy with `maxUnavailable: 0`, proven live by hitting the Ingress in a loop during a rollout - zero dropped requests |
| `.env` file sitting next to `docker-compose.yml`, committed or not | No real access control, no rotation story, and directly incompatible with "commit everything to git" GitOps | Kubernetes `Secret`, created **out-of-band** (imperative `kubectl create secret`, never committed even as a filled-in template) - deliberately excluded from `kustomization.yaml`'s resource list so Argo CD's `prune`/`selfHeal` never touches it |

## 5. Choices & trade-offs

- **Kustomize, not Helm.** This app has exactly one environment - no
  dev/staging/prod split to templatize. Kustomize's `images:` transformer
  is enough to solve the one thing that actually needed parameterizing
  (the pinned image tag); Helm's templating would be solving a problem
  this project doesn't have.
- **k3s's bundled Traefik, not ingress-nginx.** It's already there, it
  handles ACME HTTP-01 challenges without issue, and swapping controllers
  would be solving a problem that doesn't exist here. Decided early, in
  the Ansible phase, and never revisited.
- **Standard `NetworkPolicy`, no CNI swap to Calico/Cilium.** k3s bundles
  a `kube-router`-based network policy controller, enabled by default -
  confirmed directly against `k3s-io/k3s#1308` and verified the hard way
  on the live cluster (a missing policy for cert-manager's ACME solver Pod
  left a certificate stuck `pending` for 17 hours with no error logged
  anywhere obvious, until the enforcement itself was traced as the cause).
- **Secret created out-of-band, not Sealed Secrets.** Simpler for this
  project's scope, and explicitly sanctioned by the brief as an
  alternative to the Sealed/External Secrets stretch goal. The tradeoff:
  the Secret doesn't automatically survive a cluster rebuild the way
  everything else does - confirmed the hard way during the disaster
  recovery in `RUNBOOK.md`, where it had to be recreated by hand as a
  distinct step every time the cluster's datastore was lost.
