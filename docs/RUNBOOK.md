# Runbook

## Provision from zero

```bash
# 1. Remote state backend (once, ever)
cd infra/terraform/bootstrap
terraform init
terraform apply -var="state_bucket_name=capstone-phoenix-tfstate-<yourname>"

# 2. Infra
cd ../
terraform init \
  -backend-config="bucket=capstone-phoenix-tfstate-<yourname>" \
  -backend-config="dynamodb_table=capstone-phoenix-tf-lock" \
  -backend-config="region=eu-north-1"
cp terraform.tfvars.example terraform.tfvars   # fill in your IP, SSH key
terraform plan -out=capstone
terraform apply capstone
# writes ../ansible/inventory/hosts.ini automatically

# 3. Cluster
cd ../ansible
ansible-galaxy collection install -r requirements.yml
ansible all -m ping                     # confirm SSH works first
ansible-playbook site.yml               # hardening -> k3s-server -> k3s-agent
ansible-playbook fetch-kubeconfig.yml   # saves ../../phoenix-config

# 4. Kubeconfig
export KUBECONFIG=$(pwd)/../../phoenix-config
kubectl get nodes -o wide               # all three should show Ready

# 5. Platform (cert-manager, Argo CD, metrics-server check) - see
#    platform/README.md for the exact commands; summarized:
cd ../../
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager --create-namespace --set crds.enabled=true
kubectl wait --for=condition=available deployment --all -n cert-manager --timeout=120s
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s
kubectl apply -f platform/cluster-issuer.yaml
kubectl top nodes   # confirms metrics-server (bundled with k3s) is working

# 6. GitOps takes over
kubectl apply -f gitops/application.yaml
kubectl get application taskapp -n argocd -w   # watch for Synced + Healthy

# 7. The one thing Argo never creates for you - the Secret, on purpose
DB_PASS="$(openssl rand -base64 24)"
kubectl create secret generic taskapp-secret -n taskapp \
  --from-literal=POSTGRES_USER=taskapp \
  --from-literal=POSTGRES_PASSWORD="$DB_PASS" \
  --from-literal=SECRET_KEY="$(openssl rand -base64 32)" \
  --from-literal=DATABASE_URL="postgresql://taskapp:${DB_PASS}@postgres:5432/taskapp" \
  --from-literal=DATABASE_USER=taskapp \
  --from-literal=DATABASE_PASSWORD="$DB_PASS"
# save $DB_PASS somewhere real - a password manager, not a shell history file
```

## Day-2 operations

- **Scale a tier:** don't `kubectl scale` by hand - edit `replicas:` in
  the relevant `manifests/*/deployment.yaml`, commit, push. Argo applies
  it within its polling interval (or force it immediately:
  `kubectl patch application taskapp -n argocd --type=merge -p '{"operation":{"sync":{}}}'`).
  Backend's replica count specifically is **excluded** from Argo's
  comparison (`gitops/application.yaml`'s `ignoreDifferences`) since the
  HPA owns that field live - editing `replicas:` in git for backend
  changes the HPA's `minReplicas` floor, not the live count directly.

- **Roll back a bad deploy:** revert the commit that changed the image
  tag in `manifests/kustomization.yaml` and push - Argo rolls the cluster
  back to match automatically (`selfHeal: true` means this works even if
  someone's already tried to patch around it live).

- **Run a new migration safely:** bump the pinned tag in
  `kustomization.yaml`, push. `migration-job.yaml` is wired as a
  `PostSync` Argo CD hook with `hook-delete-policy: BeforeHookCreation` -
  it runs automatically after the new image is applied and is healthy,
  and the previous run is deleted first, so there's never a manual
  delete-then-reapply step needed.

- **Rotate a secret:** delete and recreate `taskapp-secret` with the
  `kubectl create secret` command from step 7 above (using fresh values),
  then `kubectl exec -n taskapp postgres-0 -- psql -U <user> -d <user> -c "ALTER USER \"<user>\" WITH PASSWORD '<new password>';"`
  to update Postgres's actual stored password to match - the Secret and
  Postgres's own credential are two separate things that only agree if
  you update both (see the incident log below for what happens if you
  don't).

## Failure recovery

- **A worker node dies / is drained:**
  ```bash
  kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
  ```
  Backend/frontend Pods on that node get evicted; the `Deployment`
  controller reschedules them onto the remaining nodes, respecting
  `topologySpreadConstraints` where possible. `PodDisruptionBudget`
  (`minAvailable: 1` on both tiers) guarantees the drain itself can't
  evict every replica of a tier simultaneously - expect a few seconds of
  reduced capacity, not an outage. Postgres is a StatefulSet with a
  single replica - if it's on the drained node, expect a real (short)
  gap while it reschedules and its PVC re-attaches; there's no second
  replica to fail over to (see `ARCHITECTURE.md` §4 for why that's an
  accepted tradeoff at this scale).

- **A backend Pod crashloops:**
  ```bash
  kubectl get pods -n taskapp
  kubectl logs <pod> -n taskapp --previous   # the PREVIOUS crashed attempt, not the current restart
  kubectl describe pod <pod> -n taskapp      # check the Events: section specifically
  kubectl get pod <pod> -n taskapp -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'
  ```
  `describe`'s `Events:` catches config/scheduling-level failures
  (`CreateContainerConfigError`, `ImagePullBackOff`); `logs --previous`
  catches application-level crashes the process logged before dying.
  Real examples hit and fixed during this build: a missing ConfigMap key
  the app's actual code expected under a different name than assumed, a
  `NetworkPolicy` silently blocking a Pod's outbound path with no error
  in `describe` at all (had to test connectivity directly from a known-
  good Pod to isolate it), and a `securityContext.runAsNonRoot` mismatch
  against what the image's Dockerfile actually supported.

- **A bad migration:** `alembic downgrade -1` run the same way as an
  ad-hoc migration (temporary Job, or `kubectl exec` into a running
  backend Pod if the schema state allows it), then fix forward with a new
  migration - never hand-edit the schema directly, since that leaves
  Alembic's own version tracking out of sync with reality.

- **Postgres Pod is rescheduled - proving the PVC re-attaches:**
  ```bash
  kubectl exec -n taskapp postgres-0 -- psql -U <user> -d <db> -c "SELECT count(*) FROM <a real table>;"
  kubectl delete pod postgres-0 -n taskapp
  kubectl wait --for=condition=ready pod postgres-0 -n taskapp --timeout=120s
  kubectl exec -n taskapp postgres-0 -- psql -U <user> -d <db> -c "SELECT count(*) FROM <a real table>;"
  ```
  Same row count both times confirms the `StatefulSet`'s
  `volumeClaimTemplates` PVC survived the Pod's deletion and recreation -
  this is the literal proof that "Pods are disposable, data isn't."

## Incident log

**2026-07-29/30 — Control-plane memory exhaustion → corrupted k3s
datastore → full cluster reset**

**Symptom:** SSH to the `k3s-server` node started hanging mid-banner-
exchange (TCP connected, `sshd` never responded), then progressed to
outright `Connection refused`, then `kubectl` reported
`i/o timeout` on port 6443. Confirmed the AWS security group and UFW both
correctly allowed the current IP throughout - this wasn't a firewall/IP-
drift issue, which is what every previous incident that session had
actually been.

**Root cause:** the `k3s-server` node was a single `t3.small` (2 vCPU /
2 GiB) carrying the *entire* control plane (API server, scheduler,
kine/embedded datastore) plus whatever workload Pods landed on it, since
the node was never tainted against scheduling. An HPA-driven scale-up to
6 backend replicas during earlier debugging, combined with Argo CD's own
components (`argocd-server`, `repo-server`, `application-controller`,
`redis`, `dex`), pushed the node into sustained memory pressure severe
enough that `sshd` couldn't fork new sessions and, eventually, k3s's
embedded datastore was caught mid-write during an ungraceful stop - k3s
detected the corruption on next boot and reinitialized a **fresh**
cluster identity (new CA, new node registrations, empty datastore)
rather than refusing to start.

**Diagnosis path (in order):**
1. AWS `describe-instance-status` confirmed `SystemStatus`/`InstanceStatus`
   both `ok` - ruled out a fully wedged/impaired instance.
2. `free -h`/`df -h` post-recovery showed healthy headroom - ruled out
   *ongoing* exhaustion, pointed to a past event instead.
3. `journalctl -u k3s` showed clean, uninterrupted activity for 15+
   minutes post-reboot with zero errors - ruled out a crash-loop.
4. `kubectl get namespaces` / `kubectl get pods -A` post-reconnect showed
   **only** default k3s namespaces (`kube-system` and friends) - confirmed
   a genuine datastore reset, not just a stale kubeconfig/CA mismatch.

**Recovery:**
1. Resized `k3s-server` `t3.small` → `t3.medium` via
   `terraform.tfvars` (`server_instance_type`) - an in-place update, not a
   replacement (confirmed via `terraform plan` showing `~ update in-place`
   for `instance_type`, no `# forces replacement`). Caught and fixed a
   real side issue mid-resize: the `compute` module's `data "aws_ami"`
   lookup tracked "most recent Ubuntu 22.04," which would have forced a
   full replacement of *all three* instances (not just the resized one)
   the moment a newer AMI existed - pinned the AMI to a fixed
   `var.ami_id_override` instead.
2. Reinstalled cert-manager and Argo CD from `platform/README.md` (fresh
   namespace each - the old ones were gone with everything else).
3. Reapplied `platform/cluster-issuer.yaml` and `gitops/application.yaml`
   - Argo pulled the entire `manifests/` tree back down from git
     automatically, proving the GitOps setup's actual disaster-recovery
     value for real, not just in theory.
4. Recreated `taskapp-secret` by hand (the one thing that never comes
   back on its own, by design).
5. Found and fixed **three separate regressions** that had only ever been
   patched *live* on the pre-reset cluster and were never actually
   committed to git - each one silently reappeared once the cluster
   rebuilt from what GitHub actually had:
   - `securityContext.runAsNonRoot` on backend/frontend (the original
     `CreateContainerConfigError` bug) - overwrote both Deployment files
     completely and pushed.
   - `DATABASE_*` ConfigMap keys the app's `migrations/env.py` actually
     reads (as opposed to the `POSTGRES_*` names the Postgres image itself
     needs) - restored and pushed.
   - Two `NetworkPolicy` objects (`allow-ingress-to-frontend`,
     `allow-migration-to-postgres`) - restored and pushed.
6. Found and fixed one **new** structural bug surfaced only by the reset:
   `migration-job.yaml` was wired as a **PreSync** hook, which runs
   *before* Argo applies any regular resources - including the ConfigMap
   the migration Job itself needs via `envFrom`. On a clean rebuild this
   is a genuine deadlock (the Job can't succeed without the ConfigMap; the
   ConfigMap won't get created until the Job succeeds). This had never
   surfaced before because earlier syncs always ran against a cluster that
   already had the ConfigMap from a previous, non-hook-ordered apply.
   Fixed by switching to a **PostSync** hook instead - runs after regular
   Sync-phase resources exist and are healthy.
7. Found and fixed one **Argo CD vs. HPA fight**: `SYNC STATUS` flapping
   `Synced ⟷ OutOfSync` in a tight loop, caused by the HPA actively
   changing `backend`'s `spec.replicas` while git said `2` - both
   controllers correctly doing their job, just fighting over the same
   field. Fixed via `gitops/application.yaml`'s `ignoreDifferences` on
   that one field.

**Total recovery time:** several hours, spread across one long session -
most of it spent on steps 5-7 (finding regressions that only manifested
on a *truly* clean rebuild) rather than the mechanical parts of steps
1-4.

**Follow-up actions taken:** resized the control-plane node (above).
**Follow-up actions still open:** consider tainting the `k3s-server` node
against scheduling ordinary workloads entirely, so control-plane memory
headroom is never shared with application Pods again.
