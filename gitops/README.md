# gitops/ — Argo CD owns the cluster

This is your **Portainer GitOps, leveled up to Kubernetes**. The cluster's desired state
lives in *this git repo*; Argo CD continuously syncs it. Your final, graded state must be
reconciled by Argo — not by you running `kubectl apply` by hand.

**Produce:**
- Install Argo CD (manifest or Helm) — document how in RUNBOOK.md.
- An Argo CD `Application` (this folder) pointing at `manifests/` (or your Helm/kustomize path),
  with `syncPolicy.automated` (prune + selfHeal). App-of-apps if you split platform vs app.

**Acceptance / demo (required for the GitOps points):**
1. `argocd app get taskapp` → `Synced` + `Healthy`.
2. Commit a change (e.g. bump frontend replicas 2→3), push.
3. Show Argo auto-syncing and the new Pod appearing — **no manual apply.**

**Stretch:** a CI job that builds a new image, pushes to GHCR, and bumps the pinned tag in
this repo → Argo deploys it. That closes the loop your `cd.yaml` started in the CI/CD lesson.

> Secrets + GitOps: don't commit a plaintext Secret to satisfy "git owns everything." Use
> Sealed Secrets / External Secrets (stretch) so the encrypted form is safe in git, or create
> the Secret out-of-band and let Argo ignore it. State your choice in ARCHITECTURE.md.

#####################################################################################################################################################################################################################################################################################################################

# gitops/ — Argo CD owns the cluster

Argo CD was already installed back in `platform/README.md`. This folder is
the one piece that actually hands the cluster over to it: an `Application`
pointing at `manifests/`, with automated sync.

## Bootstrap (one-time)

```bash
kubectl apply -f gitops/application.yaml
```

**Verify it picked up and synced:**
```bash
kubectl get application taskapp -n argocd
```
Look for `SYNC STATUS: Synced` and `HEALTH STATUS: Healthy`. If you have the
`argocd` CLI installed instead of just `kubectl`:
```bash
argocd app get taskapp
```

If it's stuck `OutOfSync` or `Progressing` for more than a minute or two,
check what Argo is actually seeing:
```bash
kubectl describe application taskapp -n argocd
```

## From here on: git push replaces kubectl apply

This is the actual behavior change GitOps is asking for. Once the
Application is `Synced`, **stop running `kubectl apply` by hand** for
anything in `manifests/` - commit and push instead, and let Argo reconcile
it. `syncPolicy.automated.selfHeal: true` means if you (or anyone) edits a
live resource directly with `kubectl`, Argo will notice the drift and
revert it back to match git within moments - this is intentional, not a bug,
and it's exactly what "Argo owns the cluster" means in practice.

## Required demo (this is what earns the GitOps grading points)

1. `argocd app get taskapp` (or `kubectl get application taskapp -n argocd`)
   shows `Synced` + `Healthy`.
2. Make a real change - the brief's suggested one is bumping frontend
   replicas:
   ```bash
   # manifests/frontend/deployment.yaml
   spec:
     replicas: 3   # was 2
   ```
3. Commit and push:
   ```bash
   git add manifests/frontend/deployment.yaml
   git commit -m "scale frontend to 3 replicas"
   git push
   ```
4. Watch Argo pick it up on its own - **no `kubectl apply`**:
   ```bash
   kubectl get application taskapp -n argocd -w
   kubectl get pods -n taskapp -l app=frontend -w
   ```
   A third frontend Pod should appear within Argo's polling interval
   (default ~3 minutes, or force it immediately with
   `argocd app sync taskapp` if you have the CLI and don't want to wait).

Screenshot/record this sequence for `docs/EVIDENCE/` - it's the actual proof
the brief is asking for, not just the Application existing.

## Migrations under GitOps

`manifests/migration-job.yaml` is wired as an Argo CD **PreSync hook**
(`argocd.argoproj.io/hook: PreSync`) - Argo runs it automatically before
every sync, and `hook-delete-policy: BeforeHookCreation` deletes the
previous run first. This is what solves the "Jobs are immutable, must
manually delete before reapply" friction permanently: bump the pinned image
tag in `kustomization.yaml`, push, and Argo runs the new migration
automatically as part of the same sync that rolls out the new image -
no manual `kubectl delete job` step required anymore.

## Secrets under GitOps

`taskapp-secret` is deliberately **not** part of what Argo manages - it's
created out-of-band (see `manifests/README.md`) and isn't in
`kustomization.yaml`'s resource list, so Argo's `kustomize build` never
produces it and there's nothing for `prune`/`selfHeal` to touch. This
satisfies the brief's requirement ("don't commit a plaintext Secret... or
create the Secret out-of-band and let Argo ignore it") without needing
Sealed Secrets - state this same choice in `docs/ARCHITECTURE.md`, since
the brief asks for it there too.

## Stretch (not required)

A CI job that builds a new image, pushes to GHCR, and bumps the pinned tag
in this repo automatically - closing the loop so a `git push` to your app
code eventually reaches production with zero manual steps anywhere,
including the tag bump itself. Worth doing later if you want it, not needed
for the required GitOps points above.
