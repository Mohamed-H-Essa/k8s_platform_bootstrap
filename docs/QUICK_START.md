# Quick Start Guide

Get your production-grade EKS cluster up and running in under 12 minutes!

## Prerequisites Check

```bash
# Verify all required tools are installed
terraform version    # >= 1.5.0
kubectl version     # >= 1.28
helm version        # >= 3.12
aws --version       # >= 2.13
```

## Step 1: Clone and Configure (2 minutes)

```bash
# Clone repository
git clone https://github.com/your-org/k8s-platform-bootstrap.git
cd k8s-platform-bootstrap

# Configure AWS credentials
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_REGION="us-west-2"

# Or use AWS CLI
aws configure
```

## Step 2: Deploy Infrastructure (10 minutes)

```bash
# Navigate to production environment
cd terraform/environments/prod

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy (this takes ~10 minutes)
terraform apply -auto-approve
```

## Step 3: Configure kubectl (1 minute)

```bash
# Get cluster name from outputs
CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)

# Configure kubectl
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# Verify connection
kubectl cluster-info
kubectl get nodes
```

## Step 4: Install ArgoCD (2 minutes)

```bash
# Go back to root directory
cd ../../..

# Install ArgoCD
kubectl apply -f kubernetes/bootstrap/argocd/install.yaml
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Step 5: Deploy Applications (1 minute)

```bash
# Deploy root application (GitOps)
kubectl apply -f kubernetes/bootstrap/argocd/app-of-apps.yaml

# Watch applications sync
kubectl get applications -n argocd -w
```

## Step 6: Access ArgoCD UI (1 minute)

```bash
# Port forward to access locally
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Open in browser
open https://localhost:8080

# Login credentials
Username: admin
Password: <from-step-4>
```

## Verify Everything is Working

```bash
# Check all pods are running
kubectl get pods -A

# Check ArgoCD applications
kubectl get applications -n argocd

# Check monitoring stack
kubectl get pods -n monitoring

# Check ingress controller
kubectl get pods -n ingress-nginx
```

## Next Steps

1. **Configure your domain**: Update ingress hosts with your domain
2. **Set up TLS**: Configure Let's Encrypt certificates
3. **Add your applications**: Deploy your workloads
4. **Configure monitoring**: Set up alerts and dashboards

## Common Commands

```bash
# Scale cluster
cd terraform/environments/prod
# Edit terraform.tfvars to change node counts
terraform apply

# Access Grafana
kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80

# View logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Destroy cluster (when done)
./scripts/destroy.sh destroy prod
```

## Troubleshooting

**Issue**: `terraform apply` fails
**Solution**: Check AWS credentials and permissions

**Issue**: kubectl can't connect
**Solution**: Run `aws eks update-kubeconfig` again

**Issue**: ArgoCD not syncing
**Solution**: Check repository credentials and access

**Issue**: Pods pending
**Solution**: Check node resources and resource quotas

## Getting Help

- 📖 [Full Documentation](docs/DEPLOYMENT.md)
- 🐛 [Report Issues](https://github.com/your-org/k8s-platform-bootstrap/issues)
- 💬 [Discussions](https://github.com/your-org/k8s-platform-bootstrap/discussions)

---

**Total Time**: ~12 minutes to full production-ready EKS cluster! 🚀
