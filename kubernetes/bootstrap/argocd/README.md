# ArgoCD Bootstrap

This directory contains ArgoCD installation and configuration.

## Installation

```bash
# Create namespace and basic config
kubectl apply -f install.yaml

# Install ArgoCD using Helm
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Or using Kustomize
kubectl kustomize --load-restrictor LoadRestrictionsNone . | kubectl apply -f -
```

## Access ArgoCD UI

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at https://localhost:8080
# Username: admin
# Password: <from-command-above>
```

## Configure Git Repository

1. Create a GitHub personal access token with repo access
2. Create a Kubernetes secret with the token:

```bash
kubectl create secret generic argocd-repo-credentials \
  --from-literal=username=<github-username> \
  --from-literal=password=<github-token> \
  --namespace argocd
```

3. Update the `argocd-cm` ConfigMap with your repository URL

## Apps of Apps Pattern

ArgoCD uses the "Apps of Apps" pattern for managing multiple applications:

1. Create an Application that points to a directory of Application manifests
2. ArgoCD automatically creates and manages all referenced applications
3. This enables GitOps management of all applications from a single source

## Production Checklist

- [ ] Change admin password
- [ ] Configure SSO/OAuth
- [ ] Set up repository credentials
- [ ] Configure RBAC
- [ ] Enable notifications
- [ ] Set resource quotas
- [ ] Configure backup
