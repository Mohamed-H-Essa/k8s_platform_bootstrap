# Deployment Guide

This guide walks you through deploying a production-grade EKS cluster with GitOps, observability, and automatic TLS.

## Prerequisites

### Required Tools

- **Terraform** >= 1.5.0
- **kubectl** >= 1.28
- **Helm** >= 3.12
- **AWS CLI** >= 2.13

### Install Tools

#### macOS (using Homebrew)
```bash
brew install terraform kubectl helm awscli
```

#### Linux
```bash
# Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### AWS Account Setup

1. Create an AWS account
2. Create an IAM user with programmatic access
3. Attach the following policies (or create a custom policy):
   - `AmazonEKSClusterPolicy`
   - `AmazonEKSServicePolicy`
   - `AmazonVPCFullAccess`
   - `IAMFullAccess` (for creating service roles)
   - `AmazonS3FullAccess` (for Terraform state)
   - `AmazonDynamoDBFullAccess` (for Terraform locks)

4. Configure AWS credentials:
```bash
aws configure
# Or use environment variables:
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_REGION="us-west-2"
```

### Terraform State Backend

Create an S3 bucket and DynamoDB table for Terraform state:

```bash
# Create S3 bucket
aws s3 mb s3://your-terraform-state-bucket --region us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

Update `terraform/environments/prod/main.tf` with your bucket name.

## Quick Start

### Option 1: Using the Setup Script (Recommended)

```bash
# Clone the repository
git clone https://github.com/your-org/k8s-platform-bootstrap.git
cd k8s-platform-bootstrap

# Make scripts executable
chmod +x scripts/*.sh

# Deploy entire platform
./scripts/setup.sh deploy prod
```

### Option 2: Manual Deployment

#### 1. Initialize Terraform

```bash
cd terraform/environments/prod
terraform init
```

#### 2. Review and Customize Variables

```bash
# Create terraform.tfvars from variables
cp variables.tf terraform.tfvars
# Edit terraform.tfvars with your preferred settings
vim terraform.tfvars
```

#### 3. Plan Deployment

```bash
terraform plan -out=tfplan
```

#### 4. Apply Configuration

```bash
terraform apply tfplan
```

This will create:
- VPC with public/private subnets
- EKS cluster with managed node groups
- IAM roles and policies
- Security groups
- NAT Gateways

**Duration**: 10-15 minutes

#### 5. Configure kubectl

```bash
aws eks update-kubeconfig --name prod-cluster --region us-west-2
```

Verify connection:
```bash
kubectl cluster-info
kubectl get nodes
```

#### 6. Install ArgoCD

```bash
# Create namespace and configuration
kubectl apply -f kubernetes/bootstrap/argocd/install.yaml

# Install ArgoCD
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

#### 7. Deploy Applications

```bash
# Deploy the root application (App of Apps)
kubectl apply -f kubernetes/bootstrap/argocd/app-of-apps.yaml
```

ArgoCD will automatically deploy:
- Namespaces with resource quotas
- Cert-Manager with Let's Encrypt issuers
- NGINX Ingress Controller
- Prometheus Stack (Prometheus + Grafana + AlertManager)

#### 8. Configure Repository Access

Create a GitHub personal access token and add it to ArgoCD:

```bash
# Create secret with GitHub credentials
kubectl create secret generic argocd-repo-credentials \
  --from-literal=username=<github-username> \
  --from-literal=password=<github-token> \
  --namespace argocd

# Update ArgoCD configuration
kubectl edit configmap argocd-cm -n argocd
```

## Post-Deployment Configuration

### 1. Update Domain Names

Update the following files with your domain:
- `kubernetes/bootstrap/argocd/install.yaml` - ArgoCD ingress
- `kubernetes/bootstrap/argocd/apps/prometheus-stack.yaml` - Grafana ingress
- `kubernetes/manifests/cert-manager/cluster-issuers.yaml` - Email address

### 2. Configure DNS

Point your domain to the load balancer:

```bash
# Get load balancer address
kubectl get svc -n ingress-nginx

# Create DNS records:
# argocd.yourdomain.com -> ALB address
# grafana.yourdomain.com -> ALB address
```

### 3. Access Services

#### ArgoCD UI
```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Or use ingress (after DNS configuration)
https://argocd.yourdomain.com
```

#### Grafana
```bash
# Port forward
kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80

# Or use ingress
https://grafana.yourdomain.com

# Default credentials
Username: admin
Password: admin (change this!)
```

### 4. Change Default Passwords

```bash
# ArgoCD
argocd login localhost:8080
argocd account update-password

# Grafana
kubectl edit secret prometheus-stack-grafana -n monitoring
```

## Verify Deployment

### Check Cluster Status

```bash
# Cluster info
kubectl cluster-info

# Nodes
kubectl get nodes -o wide

# All pods
kubectl get pods -A

# Services
kubectl get svc -A
```

### Check ArgoCD Applications

```bash
# List applications
argocd app list

# Or using kubectl
kubectl get applications -n argocd

# Check sync status
argocd app get namespaces
argocd app get cert-manager
argocd app get ingress-nginx
argocd app get prometheus-stack
```

### Check Monitoring Stack

```bash
# Prometheus
kubectl get prometheus -n monitoring
kubectl get servicemonitor -n monitoring

# AlertManager
kubectl get alertmanager -n monitoring

# Grafana
kubectl get grafana -n monitoring
```

## Troubleshooting

### Common Issues

#### 1. Terraform State Lock

```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

#### 2. EKS Cluster Connection Issues

```bash
# Regenerate kubeconfig
aws eks update-kubeconfig --name prod-cluster --region us-west-2 --force

# Check AWS credentials
aws sts get-caller-identity
```

#### 3. ArgoCD Not Syncing

```bash
# Manual sync
argocd app sync <app-name>

# Check app status
argocd app get <app-name>

# View logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

#### 4. Pods Stuck in Pending

```bash
# Check events
kubectl describe pod <pod-name>

# Check node resources
kubectl describe nodes

# Check resource quotas
kubectl describe resourcequota -n <namespace>
```

#### 5. Ingress Not Working

```bash
# Check ingress status
kubectl get ingress -A

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Check ingress controller service
kubectl describe svc -n ingress-nginx
```

## Next Steps

1. **Configure Alerts**: Set up AlertManager notifications
2. **Add Custom Dashboards**: Import Grafana dashboards
3. **Deploy Applications**: Add your application manifests
4. **Set Up CI/CD**: Integrate with your CI/CD pipeline
5. **Configure Backups**: Implement backup strategies
6. **Security Hardening**: Review and enhance security configurations

## Maintenance

### Update Cluster Version

```bash
# Update cluster_version in terraform.tfvars
vim terraform/environments/prod/terraform.tfvars

# Apply changes
terraform plan
terraform apply
```

### Scale Node Groups

```bash
# Edit node_groups in terraform.tfvars
vim terraform/environments/prod/terraform.tfvars

# Apply changes
terraform apply

# Or manually scale
kubectl scale deployment <deployment> --replicas=<count> -n <namespace>
```

### Add New Application

1. Create manifest in `kubernetes/manifests/`
2. Create ArgoCD Application in `kubernetes/bootstrap/argocd/apps/`
3. Commit and push
4. ArgoCD syncs automatically

## Cost Management

### Estimated Monthly Costs (us-west-2)

- EKS Control Plane: $72/month
- Node Groups (3x m5.large): $260/month
- NAT Gateway (2x): $64/month + data
- Load Balancers: $40/month
- CloudWatch Logs: $20/month
- **Total**: ~$456/month + data transfer

### Cost Optimization

1. Use Spot Instances for non-critical workloads
2. Implement cluster autoscaling
3. Right-size your instances
4. Use reserved instances for stable workloads
5. Monitor costs with AWS Cost Explorer
