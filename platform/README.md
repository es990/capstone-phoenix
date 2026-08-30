# platform/ — cluster-wide components (install once)

These aren't part of the TaskApp itself - they're shared infrastructure the
app's manifests depend on. Install once per cluster, before applying
manifests/.

## 1. Ingress controller — already have it, no install needed

We kept k3s's bundled **Traefik** rather than disabling it (decision made
back in `infra/ansible/roles/k3s-server/defaults/main.yml` - see that file's
comments, and mirror this same justification in `docs/ARCHITECTURE.md`).
Nothing to install here.

## 2. cert-manager
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

Wait for it to be ready:
```bash
kubectl wait --for=condition=available deployment --all -n cert-manager --timeout=120s
```

Then apply the ClusterIssuer (edit the email first):
```bash
kubectl apply -f platform/cluster-issuer.yaml
kubectl describe clusterissuer letsencrypt-prod   # READY: True once ACME account registers
```

## 3. metrics-server — check before assuming you need to install it

k3s bundles metrics-server as a default addon. Confirm it's actually there
and working before wiring up the HPA:
```bash
kubectl get deployment metrics-server -n kube-system
kubectl top nodes
```
If `kubectl top nodes` returns real numbers, you're done - skip straight to
Argo CD. If the deployment is missing or `kubectl top` errors, install it
manually:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```
On k3s specifically, metrics-server sometimes needs `--kubelet-insecure-tls`
added to its args (self-signed kubelet certs) - if `kubectl top nodes`
still fails after installing, patch it:
```bash
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

## 4. Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s
```

Get the initial admin password (delete this secret once you've changed it):
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

Access the UI for now via port-forward (fine for setup - you'll front it
with a real Ingress + your domain later if you want it reachable without a
tunnel):
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

The actual `Application` resource pointing Argo CD at `manifests/` belongs
in `gitops/` - that's the next phase, not this one.
