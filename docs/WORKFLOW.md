# Complete Deployment Workflow

This guide walks you through the entire deployment process, explaining what happens at each step.

## Overview

The deployment happens in **4 phases**:
1. **Setup** (2 minutes): Configure tools and credentials
2. **Infrastructure** (10-12 minutes): Create AWS resources with Terraform
3. **GitOps Setup** (2-3 minutes): Install ArgoCD
4. **Application Deployment** (2-3 minutes): Deploy services via GitOps

**Total time**: ~16 minutes

## Prerequisites Check

Before starting, verify you have all required tools:

```bash
# Check Terraform
terraform version
# Expected: >= 1.5.0

# Check kubectl
kubectl version --client
# Expected: >= 1.28

# Check Helm
helm version
# Expected: >= 3.12

# Check AWS CLI
aws --version
# Expected: >= 2.13
```

If any tools are missing, install them:

**macOS (Homebrew)**:
```bash
brew install terraform kubectl helm awscli
```

**Linux**: See [BEGINNERS_GUIDE.md](BEGINNERS_GUIDE.md) for installation instructions.

## Phase 1: Setup (2 minutes)

### Step 1.1: Clone Repository

```bash
# Clone the repository
git clone https://github.com/your-org/k8s-platform-bootstrap.git

# Navigate to the directory
cd k8s-platform-bootstrap
```

**What this does**:
- Downloads all configuration files
- Creates a local working directory

### Step 1.2: Configure AWS Credentials

**Option 1: Environment Variables** (Quick, temporary)
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-west-2"
```

**Option 2: AWS CLI** (Permanent)
```bash
aws configure
# Enter your credentials when prompted
# AWS Access Key ID: your-key
# AWS Secret Access Key: your-secret
# Default region: us-west-2
# Default output format: json
```

**What this does**:
- Authenticates you with AWS
- Allows Terraform to create resources

**Verify credentials**:
```bash
aws sts get-caller-identity
# Should show your account ID and user ARN
```

### Step 1.3: Configure Terraform Variables

```bash
# Navigate to production environment
cd terraform/environments/prod

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars

# Edit with your settings
vim terraform.tfvars
```

**Minimum required changes**:
```hcl
# Update these values
cluster_name    = "my-cluster"        # Unique cluster name
environment     = "production"

tags = {
  Environment  = "production"
  Owner        = "your-name"
  Project      = "my-project"
}
```

**What this does**:
- Customizes the deployment to your needs
- Sets cluster name, region, and tags

## Phase 2: Infrastructure (10-12 minutes)

### Step 2.1: Initialize Terraform

```bash
# Initialize Terraform
terraform init
```

**What happens**:
```
1. Downloads AWS provider plugin
2. Downloads TLS provider plugin
3. Initializes modules (vpc, eks)
4. Sets up backend (local by default)
```

**Output**:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.17.0...
- Installed hashicorp/aws v5.17.0

Terraform has been successfully initialized!
```

### Step 2.2: Plan Infrastructure

```bash
# Create execution plan
terraform plan -out=tfplan
```

**What happens**:
```
1. Reads your configuration files
2. Refreshes state (checks current infrastructure)
3. Compares desired vs current state
4. Creates execution plan
5. Shows what will be created/changed/deleted
```

**Output** (summary):
```
Plan: 25 to add, 0 to change, 0 to destroy.

Resources to add:
  + aws_vpc.main
  + aws_subnet.public[0]
  + aws_subnet.public[1]
  + aws_subnet.public[2]
  + aws_subnet.private[0]
  + aws_subnet.private[1]
  + aws_subnet.private[2]
  + aws_internet_gateway.main
  + aws_eip.nat[0]
  + aws_eip.nat[1]
  + aws_eip.nat[2]
  + aws_nat_gateway.main[0]
  + aws_nat_gateway.main[1]
  + aws_nat_gateway.main[2]
  + aws_eks_cluster.main
  + aws_eks_node_group.main["general"]
  + ... (and more)
```

**What's being created**:
- 1 VPC (Virtual Private Cloud)
- 6 Subnets (3 public, 3 private)
- 1 Internet Gateway
- 3 NAT Gateways (one per AZ)
- 3 Elastic IPs
- 1 EKS Cluster
- 1+ Node Groups
- IAM Roles and Policies
- Security Groups
- VPC Endpoints

### Step 2.3: Apply Infrastructure

```bash
# Apply the plan
terraform apply tfplan
```

**What happens** (timeline):
```
0:00  - Starting apply
0:01  - Creating VPC
0:02  - Creating Subnets
0:03  - Creating Internet Gateway
0:04  - Creating Security Groups
0:05  - Allocating Elastic IPs
0:06  - Creating NAT Gateways (slow, ~2-3 min each)
0:10  - Creating Route Tables
0:11  - Creating IAM Roles
0:12  - Creating EKS Cluster (slow, ~5-7 min)
0:18  - Creating Node Groups
0:20  - Apply complete!
```

**Why it takes 10-12 minutes**:
- NAT Gateways require AWS to provision network hardware (~2-3 min each)
- EKS Cluster requires AWS to provision control plane (~7 min)
- Node Groups require EC2 instance provisioning (~2 min)

**Output**:
```
Apply complete! Resources: 25 added, 0 changed, 0 destroyed.

Outputs:
cluster_endpoint = "https://XXXXX.yl4.us-west-2.eks.amazonaws.com"
cluster_name = "prod-cluster"
kubectl_config = "aws eks update-kubeconfig --name prod-cluster --region us-west-2"
```

**What was created**:

```
AWS Account
│
└── VPC (10.0.0.0/16)
    │
    ├── Internet Gateway
    │
    ├── Public Subnets
    │   ├── us-west-2a (10.0.101.0/24)
    │   │   └── NAT Gateway + Elastic IP
    │   ├── us-west-2b (10.0.102.0/24)
    │   │   └── NAT Gateway + Elastic IP
    │   └── us-west-2c (10.0.103.0/24)
    │       └── NAT Gateway + Elastic IP
    │
    ├── Private Subnets
    │   ├── us-west-2a (10.0.1.0/24)
    │   ├── us-west-2b (10.0.2.0/24)
    │   └── us-west-2c (10.0.3.0/24)
    │       └── EKS Worker Nodes
    │
    ├── Route Tables
    │   ├── Public (→ Internet Gateway)
    │   └── Private (→ NAT Gateways)
    │
    └── VPC Endpoints
        └── S3 Gateway

EKS Cluster
│
├── Control Plane (Managed by AWS)
│   └── API Server, etcd, scheduler, etc.
│
└── Node Groups
    └── general (3x m5.large instances)
```

### Step 2.4: Verify Infrastructure

```bash
# Verify VPC
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=prod-cluster-vpc"

# Verify EKS cluster
aws eks describe-cluster --name prod-cluster

# Verify node groups
aws eks list-nodegroups --cluster-name prod-cluster
```

## Phase 3: GitOps Setup (2-3 minutes)

### Step 3.1: Configure kubectl

```bash
# Configure kubectl to connect to cluster
aws eks update-kubeconfig \
  --name prod-cluster \
  --region us-west-2

# Verify connection
kubectl cluster-info
```

**What happens**:
```
1. Gets cluster endpoint from EKS
2. Gets authentication token from AWS
3. Writes configuration to ~/.kube/config
4. Tests connection to cluster
```

**Output**:
```
Kubernetes control plane is running at https://XXXXX.yl4.us-west-2.eks.amazonaws.com
CoreDNS is running at https://XXXXX.yl4.us-west-2.eks.amazonaws.com/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

**Verify nodes**:
```bash
kubectl get nodes
```

**Expected output**:
```
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-0-1-100.us-west-2.compute.internal    Ready    <none>   2m    v1.28.3
ip-10-0-2-200.us-west-2.compute.internal    Ready    <none>   2m    v1.28.3
ip-10-0-3-300.us-west-2.compute.internal    Ready    <none>   2m    v1.28.3
```

### Step 3.2: Install ArgoCD

```bash
# Go back to root directory
cd ../../..

# Create namespace and configuration
kubectl apply -f kubernetes/bootstrap/argocd/install.yaml

# Install ArgoCD
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**What happens**:
```
1. Creates 'argocd' namespace
2. Creates ConfigMaps for configuration
3. Deploys ArgoCD components:
   - argocd-application-controller (manages apps)
   - argocd-repo-server (Git access)
   - argocd-server (UI and API)
   - argocd-dex (SSO)
   - argocd-redis (cache)
   - argocd-notifications-controller
```

### Step 3.3: Wait for ArgoCD

```bash
# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server \
  -n argocd
```

**What happens**:
- Polls deployment status
- Waits until pods are running
- Times out after 5 minutes

### Step 3.4: Get ArgoCD Password

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Make note of this password!
```

**What happens**:
- Retrieves auto-generated password
- Password is base64 encoded in secret
- You'll need this to login

### Step 3.5: Access ArgoCD UI (Optional)

```bash
# Port forward to access locally
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Open in browser: https://localhost:8080
# Username: admin
# Password: <from-step-3.4>
```

**What happens**:
- Creates tunnel from localhost:8080 to ArgoCD service
- Allows you to access UI without ingress

## Phase 4: Application Deployment (2-3 minutes)

### Step 4.1: Update Repository URL

Before deploying, update the repository URL in the manifests:

```bash
# Find and replace repository URL
find kubernetes/bootstrap/argocd -type f -name "*.yaml" \
  -exec sed -i '' 's|https://github.com/your-org/k8s-platform-bootstrap|YOUR_REPO_URL|g' {} \;

# Update email addresses
find kubernetes -type f -name "*.yaml" \
  -exec sed -i '' 's|your-email@example.com|YOUR_EMAIL|g' {} \;

# Update domain names
find kubernetes -type f -name "*.yaml" \
  -exec sed -i '' 's|yourdomain.com|YOUR_DOMAIN|g' {} \;
```

**What this does**:
- Updates all references to your actual repository
- Sets your email for Let's Encrypt
- Sets your domain for ingress

### Step 4.2: Deploy Root Application

```bash
# Deploy the App of Apps
kubectl apply -f kubernetes/bootstrap/argocd/app-of-apps.yaml
```

**What happens**:
```
1. Creates 'root-app' Application in ArgoCD
2. ArgoCD reads kubernetes/bootstrap/argocd/apps/ directory
3. ArgoCD creates Applications for each YAML file:
   - namespaces (creates namespaces and quotas)
   - cert-manager (TLS automation)
   - ingress-nginx (traffic routing)
   - prometheus-stack (monitoring)
```

### Step 4.3: Watch Deployment

```bash
# Watch applications sync
kubectl get applications -n argocd -w
```

**Expected output**:
```
NAME               SYNC STATUS   HEALTH STATUS
root-app           Synced        Healthy
namespaces         Synced        Healthy
cert-manager       Synced        Healthy
ingress-nginx      Synced        Healthy
prometheus-stack   Synced        Healthy
```

### Step 4.4: Verify Deployments

```bash
# Check all namespaces
kubectl get namespaces

# Check all pods
kubectl get pods -A

# Check services
kubectl get svc -A
```

**Expected pods**:
```
NAMESPACE         NAME                                          READY   STATUS
argocd            argocd-application-controller-0               1/1     Running
argocd            argocd-repo-server-xxx                        1/1     Running
argocd            argocd-server-xxx                             1/1     Running
cert-manager      cert-manager-xxx                              1/1     Running
ingress-nginx     ingress-nginx-controller-xxx                  1/1     Running
monitoring        alertmanager-prometheus-stack-kube-prom-alertmanager-0   2/2     Running
monitoring        prometheus-prometheus-stack-kube-prom-prometheus-0       2/2     Running
monitoring        prometheus-stack-grafana-xxx                  2/2     Running
monitoring        prometheus-stack-kube-prom-operator-xxx       1/1     Running
```

## Post-Deployment

### Step 5.1: Configure DNS

Get the load balancer address:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

**Output**:
```
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP
ingress-nginx-controller   LoadBalancer   10.100.200.10   abcd1234.us-west-2.elb.amazonaws.com
```

**Create DNS records**:
```
argocd.yourdomain.com    → abcd1234.us-west-2.elb.amazonaws.com
grafana.yourdomain.com   → abcd1234.us-west-2.elb.amazonaws.com
```

### Step 5.2: Verify TLS Certificates

```bash
# Check certificate status
kubectl get certificates -A

# Check certificate details
kubectl describe certificate argocd-tls -n argocd
```

**Expected output**:
```
NAME         READY   SECRET       AGE
argocd-tls   True    argocd-tls   5m
```

### Step 5.3: Access Services

**ArgoCD**:
```bash
# Option 1: Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080

# Option 2: Via ingress (after DNS setup)
# Open: https://argocd.yourdomain.com
```

**Grafana**:
```bash
# Option 1: Port forward
kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80
# Open: http://localhost:3000

# Option 2: Via ingress
# Open: https://grafana.yourdomain.com

# Default credentials
Username: admin
Password: prom-operator (check the secret for actual password)
```

### Step 5.4: Change Default Passwords

**ArgoCD**:
```bash
# Login to ArgoCD CLI
argocd login localhost:8080

# Change password
argocd account update-password
```

**Grafana**:
```bash
# Get current password
kubectl get secret -n monitoring prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d

# Change via UI or update secret
kubectl edit secret -n monitoring prometheus-stack-grafana
```

## What's Running Now

```
Your EKS Cluster
│
├── Namespace: argocd
│   ├── ArgoCD (GitOps controller)
│   └── Ingress for UI (TLS enabled)
│
├── Namespace: cert-manager
│   └── Cert-Manager (TLS automation)
│
├── Namespace: ingress-nginx
│   └── NGINX Ingress Controller
│
├── Namespace: monitoring
│   ├── Prometheus (metrics collection)
│   ├── Grafana (visualization)
│   ├── AlertManager (alerting)
│   └── Various exporters
│
├── Namespace: production
│   ├── Resource Quotas
│   └── Limit Ranges
│   └── (Your future applications)
│
└── Namespace: staging
    ├── Resource Quotas
    └── Limit Ranges
    └── (Your future applications)
```

## Troubleshooting

### Issue: Terraform apply fails

**Check credentials**:
```bash
aws sts get-caller-identity
```

**Check logs**:
```bash
terraform apply -auto-approve 2>&1 | tee terraform.log
```

### Issue: kubectl can't connect

**Regenerate config**:
```bash
aws eks update-kubeconfig \
  --name prod-cluster \
  --region us-west-2 \
  --force
```

### Issue: ArgoCD applications not syncing

**Check ArgoCD logs**:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

**Force sync**:
```bash
argocd app sync root-app
```

### Issue: Pods stuck in Pending

**Check events**:
```bash
kubectl get events -A --sort-by='.lastTimestamp'
```

**Check node resources**:
```bash
kubectl describe nodes
```

### Issue: Certificates not issuing

**Check cert-manager logs**:
```bash
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager
```

**Check certificate status**:
```bash
kubectl describe certificate -A
```

## Next Steps

1. **Configure Alerts**: Set up AlertManager with Slack/Email
2. **Add Custom Dashboards**: Import Grafana dashboards for your apps
3. **Deploy Your Applications**: Add application manifests to the repo
4. **Configure Backups**: Implement Velero for backups
5. **Security Review**: Review RBAC and network policies
6. **Cost Monitoring**: Set up AWS Cost Explorer alerts

## Maintenance

### Update Cluster

```bash
# Update cluster_version in terraform.tfvars
vim terraform/environments/prod/terraform.tfvars

# Apply changes
terraform plan
terraform apply
```

### Scale Cluster

```bash
# Update node_groups in terraform.tfvars
vim terraform/environments/prod/terraform.tfvars

# Apply changes
terraform apply
```

### Add New Application

1. Create manifest in `kubernetes/manifests/your-app/`
2. Create ArgoCD Application in `kubernetes/bootstrap/argocd/apps/your-app.yaml`
3. Commit and push
4. ArgoCD automatically syncs

---

**Congratulations!** You now have a fully functional production-grade EKS cluster! 🎉
