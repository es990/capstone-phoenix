# manifests/ — what you must produce

This is a **checklist, not an answer key.** The K8s lesson's reference manifests
(`cicd_dockerized/k8s-lesson/manifests/`) target a single-node laptop cluster. Here you
re-author them for real multi-node infra and add the hardening the brief requires.

Produce (raw YAML, a Helm chart, or kustomize overlays — your call):

**App**
- [ ] `namespace`
- [ ] `ConfigMap` (non-secret) + `Secret` (secret, NOT committed in plaintext — see gitops/ + Sealed Secrets stretch)
- [ ] Postgres `StatefulSet` + headless `Service` + PVC on the cluster's storage class
- [ ] backend `Deployment` (2+ replicas) + `Service` named **`backend`** (the frontend proxies `/api` → `backend:5000`)
- [ ] frontend `Deployment` (2+ replicas) + `Service`
- [ ] migration `Job` (run-once) — replicas must NOT migrate
- [ ] `Ingress` (+ `api.` host or `/api` path) with cert-manager TLS on your real domain

**Make it production, not a demo**
- [ ] `topologySpreadConstraints` / pod anti-affinity so replicas land on different nodes
- [ ] probes (startup/readiness/liveness) + `resources.requests`/`limits` on every container
- [ ] `strategy.rollingUpdate.maxUnavailable: 0`
- [ ] pinned image tags (no `:latest`)
- [ ] ≥3 Advanced: HPA / NetworkPolicy / PDB+graceful-shutdown / observability / securityContext

**Platform (install once, document how):**
- [ ] ingress controller, cert-manager + ClusterIssuer, metrics-server, Argo CD

Every box you tick must have matching evidence in `docs/EVIDENCE/`.

#######################################################################################################################################################################################################################################################################################################


# manifests/ — TaskApp on Kubernetes

Plain YAML + Kustomize (not Helm). Justification: this app has exactly one
environment (no dev/staging/prod split to templatize), and Kustomize's
`images:` transformer is enough to solve the one thing that actually needs
parameterizing - the pinned image tag. Helm's templating would be solving a
problem this project doesn't have. (Mirror this reasoning in
`docs/ARCHITECTURE.md` §5 - the brief asks you to justify it there too.)

## Before you apply anything

**1. Set your real image tags** - the only edit most updates need:
```bash
# manifests/kustomization.yaml
images:
  - name: ghcr.io/ts-a-devops/taskapp-backend
    newTag: "sha-abc1234"      # <- your real pinned tag
  - name: ghcr.io/ts-a-devops/taskapp-frontend
    newTag: "sha-abc1234"
```

**2. Domain** - already set to `taskapp.rogers.13.62.208.81.nip.io` in
`manifests/ingress.yaml`, using nip.io's wildcard-DNS-by-IP trick instead of
a real domain/Route 53 record - no DNS setup needed. If the server's Elastic
IP ever changes, update both occurrences in that file.

**3. Set your real email** - `platform/cluster-issuer.yaml`'s `spec.acme.email`.

**4. Create the real Secret out-of-band** - never commit real credentials.
`secret.example.yaml` is a template only (not applied by kustomize). Create
the real one imperatively:
```bash
kubectl create namespace taskapp --dry-run=client -o yaml | kubectl apply -f -

DB_PASS="$(openssl rand -base64 24)"
kubectl create secret generic taskapp-secret -n taskapp \
  --from-literal=POSTGRES_USER=taskapp \
  --from-literal=POSTGRES_PASSWORD="$DB_PASS" \
  --from-literal=SECRET_KEY="$(openssl rand -base64 32)" \
  --from-literal=DATABASE_URL="postgresql://taskapp:${DB_PASS}@postgres:5432/taskapp" \
  --from-literal=DATABASE_USER=taskapp \
  --from-literal=DATABASE_PASSWORD="$DB_PASS"
```
Save the generated password somewhere (a password manager, not git) - you'll
need it again if you ever have to recreate the Secret.

**5. Verify the assumptions this was built against, against your actual app:**
- Backend listens on port `5000`, health endpoint `/api/health`
- Frontend listens on port `80`, health endpoint `/healthz`
- Frontend's nginx already proxies `/api` → `backend:5000` internally
- Backend image's entrypoint runs `alembic upgrade head` for migrations
- Frontend and backend containers can run as non-root (`securityContext.runAsNonRoot: true`)

If any of these don't match your actual `taskapp-backend`/`taskapp-frontend`
images, that's expected - I built this from the brief's description of the
app, not your Dockerfiles. Adjust ports/paths/probes to match reality before
you rely on this for grading evidence.

## Platform components first

Install everything in `platform/README.md` (cert-manager, verify
metrics-server, Argo CD) before applying the app - the Ingress needs
cert-manager's ClusterIssuer to exist, and the HPA needs metrics-server.

## Deploy order (manual, for now - see gitops/ for the GitOps handoff)

```bash
cd manifests

# 1. Namespace + Secret first (everything else references them)
kubectl create namespace taskapp --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic taskapp-secret -n taskapp --from-literal=... # see step 4 above

# 2. Everything else
kubectl apply -k .

# 3. Wait for Postgres before migrating
kubectl wait --for=condition=ready pod -l app=postgres -n taskapp --timeout=120s

# 4. Run migrations once
kubectl apply -f migration-job.yaml
kubectl wait --for=condition=complete job/taskapp-migrate -n taskapp --timeout=120s
kubectl delete job taskapp-migrate -n taskapp   # Jobs are immutable - clean up so it can re-run next time

# 5. Confirm
     # backend/frontend spread across different nodes
kubectl get ingress -n taskapp           # ADDRESS populated, TLS cert issuing
```

## Design decisions (justify these same choices in docs/ARCHITECTURE.md §5)

- **Kustomize over Helm** - one environment, one real parameter (image tag).
  See top of this file.
- **Same-origin Ingress, not a separate `api.` subdomain** - the frontend
  image already proxies `/api` to `backend:5000` internally via its own
  nginx config. A single host means one DNS record, one certificate, and
  matches how the app is actually built rather than fighting it.
- **nip.io instead of a real domain / Route 53** - `taskapp.amara.<server
  public IP>.nip.io` resolves straight back to the server's stable Elastic
  IP with zero DNS configuration or propagation delay. Let's Encrypt issues
  a normal (non-wildcard) cert for it without issue.
- **Traefik, not ingress-nginx** - k3s ships it, it's already handling
  ACME HTTP-01 challenges fine, and swapping controllers would be solving a
  problem that doesn't exist here. Decided back in the Ansible phase.
- **Standard NetworkPolicy, no CNI swap to Calico** - k3s bundles a
  kube-router-based policy controller, enabled by default (confirmed against
  `k3s-io/k3s#1308`). Verify it's actually enforcing on your cluster before
  relying on it as evidence - see the comment at the top of `networkpolicy.yaml`.
- **Secret created out-of-band, not committed even as a template with real
  values** - per `gitops/README.md`'s explicitly sanctioned approach. When
  you get to the GitOps phase, configure Argo CD to ignore this resource
  (it won't be in the kustomize resource list, so it won't show as
  OutOfSync/get pruned) rather than adopting Sealed Secrets, unless you want
  the stretch goal.
- **Single Postgres replica, StatefulSet + PVC (not HA Postgres)** - Core
  only requires data survives a Pod delete, which a PVC gives you regardless
  of replica count. Multi-replica Postgres is a Stretch goal.

## What's covered vs. still open

**Core (all boxes):** namespace, ConfigMap/Secret split, Postgres
StatefulSet+PVC, backend/frontend Deployments (2 replicas,
topologySpreadConstraints), migration Job, probes on every container,
resources on every container, `maxUnavailable: 0`, Ingress+TLS, pinned tags
(once you fill in the placeholder).

**Advanced (3 of the 5, covers the "≥3" requirement):** HPA
(`backend/hpa.yaml`), NetworkPolicy (`networkpolicy.yaml`), PDB + graceful
shutdown (`pdb.yaml` + `terminationGracePeriodSeconds` on both Deployments).
Bonus: `securityContext` hardening is also included on backend/frontend
(not on Postgres - see the comment in `postgres/statefulset.yaml` for why).

**Not built here - separate phases:** the `gitops/` Argo CD `Application`
resource, and `docs/` (architecture diagram, runbook, cost, evidence
screenshots). Observability (Advanced #4) isn't included either - you have
3 solid Advanced items already; add it later only if you want a safety
margin or find it interesting.
