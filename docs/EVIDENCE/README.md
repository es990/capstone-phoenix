# EVIDENCE

Screenshots/logs proving each requirement, with the exact command to
capture for this specific deployment. Drop the actual files in this
folder using these names - a grader (or future you) shouldn't have to
guess what each one proves.

- **`nodes-ready.png`** — multi-node cluster:
  ```bash
  kubectl get nodes -o wide
  ```
  All three (`k3s-server` + 2 agents) showing `Ready`.

- **`pods-spread.png`** — replicas actually on different physical nodes,
  not just "2 replicas" on paper:
  ```bash
  kubectl get pods -n taskapp -o wide -l app=backend
  kubectl get pods -n taskapp -o wide -l app=frontend
  ```
  Confirm the `NODE` column differs between replicas of the same tier -
  proof `topologySpreadConstraints` is actually doing something.

- **`tls-valid.png`** — real, non-self-signed certificate:
  ```bash
  curl -vI https://taskapp.amara.<server-public-ip>.nip.io 2>&1 | grep -A5 "Server certificate"
  ```
  Look for `issuer: ... Let's Encrypt`, not a Traefik default/self-signed
  cert - this is the exact failure mode this build hit once (see
  `RUNBOOK.md`'s incident log) before the missing `NetworkPolicy` for
  cert-manager's ACME solver was found and fixed.

- **`pvc-persist.log`** — data survives a Pod kill, not just a container
  restart:
  ```bash
  kubectl exec -n taskapp postgres-0 -- psql -U <user> -d <db> -c "SELECT count(*) FROM <a real table>;"
  kubectl delete pod postgres-0 -n taskapp
  kubectl wait --for=condition=ready pod postgres-0 -n taskapp --timeout=120s
  kubectl exec -n taskapp postgres-0 -- psql -U <user> -d <db> -c "SELECT count(*) FROM <a real table>;"
  ```
  Same count both times, captured as one continuous log/terminal
  recording (not two separate screenshots) so the "before, delete, after"
  sequence is unambiguous.

- **`zero-downtime.log`** — unbroken 200s during a rolling update:
  ```bash
  while true; do curl -o /dev/null -s -w "%{http_code}\n" https://taskapp.amara.<server-public-ip>.nip.io; sleep 1; done
  ```
  Run this in one terminal, and in another, bump the pinned tag in
  `manifests/kustomization.yaml` and push (or `kubectl rollout restart
  deployment/backend -n taskapp` for a quicker local test). Capture the
  loop's output showing unbroken `200`s throughout - proof of
  `maxUnavailable: 0`.

- **`hpa-scale.png`** — replicas climbing under real load:
  ```bash
  kubectl get hpa backend -n taskapp -w
  ```
  Alongside a load generator against the backend (`hey`, `k6`, or even a
  tight `curl` loop) - capture `REPLICAS` climbing from 2 toward 6 as
  `TARGETS` (CPU%/memory%) rises past the 70%/80% thresholds.

- **`argocd-synced.png`** — GitOps actually owns the cluster:
  ```bash
  kubectl get application taskapp -n argocd
  ```
  `SYNC STATUS: Synced`, `HEALTH STATUS: Healthy`. Stronger evidence than
  a single screenshot: capture the full demo sequence from
  `gitops/README.md` - bump a replica count in git, push, and show Argo
  picking it up with **no `kubectl apply`** anywhere in between.

- **`failover.png`** — app stays up after a node drain:
  ```bash
  kubectl drain <agent-node-name> --ignore-daemonsets --delete-emptydir-data
  curl -I https://taskapp.amara.<server-public-ip>.nip.io
  kubectl get pods -n taskapp -o wide
  ```
  Site still responds, and Pods that were on the drained node show up
  rescheduled onto the remaining node(s). Uncordon afterward:
  `kubectl uncordon <agent-node-name>`.
