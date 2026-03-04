# K8s Platform Bootstrap

Production-grade EKS cluster deployment with GitOps, observability, and automatic TLS.

**Deploy a full production EKS cluster in under 12 minutes from a single `terraform apply`.**

## Features

- **EKS Cluster**: Production-ready Kubernetes cluster on AWS
- **GitOps (ArgoCD)**: Declarative continuous deployment
- **Observability**: Prometheus Stack (Prometheus + Grafana + AlertManager)
- **Automatic TLS**: Cert-Manager with Let's Encrypt integration
- **Namespace Isolation**: Built-in multi-tenancy support
- **Helm Charts**: Reusable, version-controlled package management

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    AWS Infrastructure                   │
│  ┌──────────────────────────────────────────────────┐   │
│  │            EKS Cluster (Terraform)               │   │
│  │  ┌────────────────────────────────────────────┐  │   │
│  │  │        ArgoCD (GitOps Controller)          │  │   │
│  │  │  ┌──────────────────────────────────────┐  │  │   │
│  │  │  │  Prometheus Stack (Monitoring)       │  │  │   │
│  │  │  │  Cert-Manager (TLS Automation)       │  │  │   │
│  │  │  │  Application Workloads               │  │  │   │
│  │  │  └──────────────────────────────────────┘  │  │   │
│  │  └────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## 📚 Documentation

**New to Kubernetes and AWS?** Start with our **Beginner's Guide**:
- **[📘 Beginner's Guide](docs/BEGINNERS_GUIDE.md)** - Learn all the concepts from scratch
- **[🚀 Quick Start](docs/QUICK_START.md)** - Deploy in 12 minutes
- **[📋 Complete Workflow](docs/WORKFLOW.md)** - Step-by-step deployment guide

**Understand the code**:
- **[🏗️ Terraform Explained](docs/TERRAFORM_EXPLAINED.md)** - Line-by-line module explanations
- **[☸️ Kubernetes Manifests Explained](docs/KUBERNETES_MANIFESTS_EXPLAINED.md)** - YAML breakdown
- **[🔄 ArgoCD Explained](docs/ARGOCD_EXPLAINED.md)** - GitOps deep dive
- **[🏢 Architecture](docs/ARCHITECTURE.md)** - System design

**Detailed guides**:
- **[📖 Deployment Guide](docs/DEPLOYMENT.md)** - Comprehensive deployment instructions

## Quick Start

```bash
# Clone the repository
git clone https://github.com/Mohamed-H-Essa/k8s_platform_bootstrap
cd k8s_platform_bootstrap

# Configure AWS credentials
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-west-2"

# Deploy infrastructure
cd terraform/environments/prod
terraform init
terraform plan
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name prod-cluster --region us-west-2

# Verify deployment
kubectl get nodes
kubectl get pods -A
```

## Project Structure

```
k8s-platform-bootstrap/
├── terraform/
│   ├── modules/              # Reusable Terraform modules
│   │   ├── eks/             # EKS cluster module
│   │   ├── vpc/             # VPC networking module
│   │   ├── iam/             # IAM roles and policies
│   │   └── security-groups/ # Security group configurations
│   └── environments/        # Environment-specific configs
│       ├── dev/
│       ├── staging/
│       └── prod/
├── kubernetes/
│   ├── bootstrap/           # Initial cluster setup
│   │   └── argocd/         # ArgoCD installation manifests
│   ├── manifests/          # Kubernetes manifests
│   │   ├── monitoring/     # Prometheus Stack
│   │   ├── cert-manager/   # Cert-Manager
│   │   └── namespaces/     # Namespace definitions
│   └── helm-charts/        # Custom Helm charts
└── scripts/                # Utility scripts
    ├── setup.sh           # Initial setup script
    └── destroy.sh         # Cleanup script
```

## Prerequisites

- **Terraform** >= 1.5.0
- **kubectl** >= 1.28
- **Helm** >= 3.12
- **AWS CLI** >= 2.13
- **AWS Account** with appropriate permissions

## Deployment Steps

### 1. Infrastructure (Terraform)
- VPC with public/private subnets
- EKS cluster with managed node groups
- IAM roles and service accounts (IRSA)
- Security groups and network policies

### 2. GitOps Setup (ArgoCD)
- Install ArgoCD
- Configure repository access
- Deploy applications via GitOps

### 3. Observability (Prometheus Stack)
- Deploy kube-prometheus-stack
- Configure Grafana dashboards
- Set up AlertManager rules

### 4. TLS Automation (Cert-Manager)
- Install Cert-Manager
- Configure Let's Encrypt issuers
- Set up automatic certificate provisioning

## Configuration

### Environment Variables

```bash
# Required
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_REGION="us-west-2"

# Optional
export TF_VAR_cluster_name="prod-cluster"
export TF_VAR_environment="production"
```

### Terraform Variables

Key variables in `terraform/environments/prod/terraform.tfvars`:

```hcl
cluster_name    = "prod-cluster"
cluster_version = "1.28"
environment     = "production"
region          = "us-west-2"

node_groups = {
  general = {
    instance_types = ["m5.large"]
    min_size       = 2
    max_size       = 10
    desired_size   = 3
  }
}
```

## Cost Estimation

Estimated monthly costs for a production setup (us-west-2):

- **EKS Control Plane**: $72/month
- **Node Groups** (3x m5.large): ~$260/month
- **NAT Gateway** (2x): $64/month + data transfer
- **Load Balancers**: ~$40/month
- **Total**: ~$436/month + data transfer

## Security Best Practices

- Private subnets for worker nodes
- AWS IAM Authenticator for cluster authentication
- IRSA (IAM Roles for Service Accounts)
- Network policies for pod-to-pod communication
- Secrets encryption at rest with AWS KMS
- RBAC enabled by default

## Maintenance

### Update Cluster Version
```bash
# Update cluster_version in terraform.tfvars
terraform apply
```

### Scale Node Groups
```bash
# Modify desired_size in terraform.tfvars
terraform apply
```

### Add New Application
1. Create manifest in `kubernetes/manifests/`
2. Commit and push to repository
3. ArgoCD automatically syncs changes

## Troubleshooting

### Common Issues

1. **kubectl connection issues**
   ```bash
   aws eks update-kubeconfig --name prod-cluster --region us-west-2
   ```

2. **Terraform state lock**
   ```bash
   terraform force-unlock <LOCK_ID>
   ```

3. **ArgoCD not syncing**
   ```bash
   argocd app sync <app-name>
   ```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

- **Issues**: GitHub Issues
- **Documentation**: [docs/](docs/)
- **Email**: me@mecodes.live
