# Documentation Index

Welcome to the K8s Platform Bootstrap documentation! This index helps you find the right guide for your needs.

## 🎯 Where Should I Start?

### I'm New to Kubernetes/AWS
**Start here**: [📘 Beginner's Guide](BEGINNERS_GUIDE.md)

This guide explains:
- What is Kubernetes, EKS, Terraform, GitOps?
- Key concepts (Pods, Nodes, Clusters, Namespaces)
- How all the pieces fit together
- Prerequisites and setup

**Time**: ~30 minutes to read and understand

### I Want to Deploy Now
**Start here**: [🚀 Quick Start Guide](QUICK_START.md)

This guide shows:
- Prerequisites check
- 12-minute deployment process
- Quick commands to get running
- Basic verification

**Time**: ~12 minutes to deploy

### I Want to Understand Everything
**Read these in order**:

1. [📘 Beginner's Guide](BEGINNERS_GUIDE.md) - Concepts and fundamentals
2. [🏗️ Terraform Explained](TERRAFORM_EXPLAINED.md) - Infrastructure code
3. [☸️ Kubernetes Manifests Explained](KUBERNETES_MANIFESTS_EXPLAINED.md) - Application definitions
4. [🔄 ArgoCD Explained](ARGOCD_EXPLAINED.md) - GitOps workflow
5. [📋 Complete Workflow](WORKFLOW.md) - Deployment process

**Time**: ~2-3 hours to read all

### I'm Deploying for Real
**Use this**: [📖 Deployment Guide](DEPLOYMENT.md)

This comprehensive guide includes:
- Detailed prerequisites
- Step-by-step deployment
- Post-deployment configuration
- Troubleshooting
- Maintenance procedures

**Time**: ~1 hour to read, ~20 minutes to execute

## 📚 All Documentation

### Getting Started
| Document | Purpose | Audience | Time |
|----------|---------|----------|------|
| [Beginner's Guide](BEGINNERS_GUIDE.md) | Learn concepts and fundamentals | New to K8s/AWS | 30 min |
| [Quick Start](QUICK_START.md) | Deploy quickly | Ready to deploy | 5 min read + 12 min deploy |
| [Deployment Guide](DEPLOYMENT.md) | Comprehensive deployment | Production deployment | 1 hour |

### Understanding the Code
| Document | Purpose | Audience | Time |
|----------|---------|----------|------|
| [Terraform Explained](TERRAFORM_EXPLAINED.md) | Infrastructure modules | Want to understand IaC | 45 min |
| [Kubernetes Manifests Explained](KUBERNETES_MANIFESTS_EXPLAINED.md) | YAML configurations | Want to understand K8s | 30 min |
| [ArgoCD Explained](ARGOCD_EXPLAINED.md) | GitOps workflow | Want to understand GitOps | 30 min |

### References
| Document | Purpose | Audience | Time |
|----------|---------|----------|------|
| [Architecture](ARCHITECTURE.md) | System design and diagrams | Architects, Leads | 20 min |
| [Complete Workflow](WORKFLOW.md) | End-to-end process | Anyone deploying | 45 min |

## 🗺️ Learning Path

### Path 1: Quick Deployment (Fast Track)
```
1. Quick Start Guide (5 min read)
   ↓
2. Deploy infrastructure (12 min)
   ↓
3. Verify and access services (5 min)
   ↓
4. Done! Start using your cluster
```
**Total time**: ~25 minutes

### Path 2: Understand & Deploy (Balanced)
```
1. Beginner's Guide (30 min)
   ↓
2. Quick Start Guide (5 min read)
   ↓
3. Deploy with understanding (12 min)
   ↓
4. Terraform Explained (45 min - optional)
   ↓
5. Kubernetes Manifests Explained (30 min - optional)
```
**Total time**: ~2 hours

### Path 3: Deep Understanding (Comprehensive)
```
1. Beginner's Guide (30 min)
   ↓
2. Architecture (20 min)
   ↓
3. Terraform Explained (45 min)
   ↓
4. Kubernetes Manifests Explained (30 min)
   ↓
5. ArgoCD Explained (30 min)
   ↓
6. Complete Workflow (45 min)
   ↓
7. Deployment Guide (1 hour)
   ↓
8. Deploy with full knowledge (20 min)
```
**Total time**: ~5 hours

## 📖 Document Details

### [Beginner's Guide](BEGINNERS_GUIDE.md)
**What you'll learn**:
- What is Kubernetes and why use it
- What is EKS (Elastic Kubernetes Service)
- What is Terraform and Infrastructure as Code
- What is GitOps and ArgoCD
- Key concepts: Pods, Nodes, Clusters, Namespaces
- File structure explanation
- Technology deep dives
- Common questions answered

**Prerequisites**: None

**Who it's for**: Complete beginners to Kubernetes and cloud infrastructure

---

### [Quick Start Guide](QUICK_START.md)
**What you'll learn**:
- Prerequisites verification
- 6-step deployment process
- Quick commands reference
- Basic troubleshooting

**Prerequisites**:
- AWS account
- Terraform, kubectl, Helm, AWS CLI installed

**Who it's for**: People who want to deploy quickly

---

### [Deployment Guide](DEPLOYMENT.md)
**What you'll learn**:
- Detailed prerequisites and setup
- Tool installation instructions
- AWS account configuration
- Terraform backend setup
- Step-by-step deployment
- Post-deployment configuration
- Accessing services
- Troubleshooting common issues
- Maintenance procedures
- Cost management

**Prerequisites**: AWS account, basic CLI knowledge

**Who it's for**: Teams deploying to production

---

### [Terraform Explained](TERRAFORM_EXPLAINED.md)
**What you'll learn**:
- VPC module (variables, resources, outputs)
- EKS module (cluster, node groups, IAM)
- Production environment configuration
- Line-by-line code explanation
- Visual representations
- Best practices used

**Prerequisites**: Basic Terraform knowledge helpful

**Who it's for**: People wanting to understand the infrastructure code

---

### [Kubernetes Manifests Explained](KUBERNETES_MANIFESTS_EXPLAINED.md)
**What you'll learn**:
- Namespace definitions with resource quotas
- Cert-Manager configuration
- ArgoCD bootstrap applications
- Helm chart deployments
- Line-by-line YAML explanation
- Best practices used
- Common operations

**Prerequisites**: Basic Kubernetes knowledge helpful

**Who it's for**: People wanting to understand the Kubernetes configurations

---

### [ArgoCD Explained](ARGOCD_EXPLAINED.md)
**What you'll learn**:
- What is GitOps
- How ArgoCD works
- App of Apps pattern
- Application definitions
- Sync policies and waves
- Health checks
- Projects and RBAC
- CLI commands
- Best practices

**Prerequisites**: Basic Kubernetes knowledge

**Who it's for**: People wanting to understand GitOps workflow

---

### [Architecture](ARCHITECTURE.md)
**What you'll learn**:
- High-level architecture
- Kubernetes cluster architecture
- GitOps workflow diagram
- Network architecture
- Security architecture
- Key components explained
- Design principles
- Scaling strategy

**Prerequisites**: Basic understanding of the project

**Who it's for**: Architects, team leads, anyone wanting the big picture

---

### [Complete Workflow](WORKFLOW.md)
**What you'll learn**:
- 4-phase deployment process
- Detailed steps with explanations
- What happens at each stage
- Timeline and durations
- Post-deployment steps
- DNS and TLS configuration
- Troubleshooting guide
- Maintenance procedures

**Prerequisites**: Ready to deploy

**Who it's for**: Anyone going through the deployment process

## 🔍 Quick Reference

### Common Tasks

**Deploy the cluster**:
```bash
./scripts/setup.sh deploy prod
```
See: [Quick Start](QUICK_START.md) or [Workflow](WORKFLOW.md)

**Access ArgoCD UI**:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
See: [ArgoCD Explained](ARGOCD_EXPLAINED.md)

**Access Grafana**:
```bash
kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80
```
See: [Deployment Guide](DEPLOYMENT.md)

**Update cluster**:
```bash
terraform plan
terraform apply
```
See: [Terraform Explained](TERRAFORM_EXPLAINED.md)

**Add new application**:
1. Add manifests to `kubernetes/manifests/`
2. Add Application to `kubernetes/bootstrap/argocd/apps/`
3. Commit and push

See: [Kubernetes Manifests Explained](KUBERNETES_MANIFESTS_EXPLAINED.md)

### Troubleshooting

**Terraform issues**: See [Deployment Guide](DEPLOYMENT.md) > Troubleshooting

**ArgoCD issues**: See [ArgoCD Explained](ARGOCD_EXPLAINED.md) > Troubleshooting

**Kubernetes issues**: See [Kubernetes Manifests Explained](KUBERNETES_MANIFESTS_EXPLAINED.md) > Debugging Tips

**General issues**: See [Complete Workflow](WORKFLOW.md) > Troubleshooting

## 💡 Tips

1. **Start with the Beginner's Guide** if you're new
2. **Use Quick Start** for your first deployment
3. **Read the Explained guides** to understand what you deployed
4. **Keep the Workflow guide handy** during deployment
5. **Refer to Architecture** when explaining to others

## 🆘 Getting Help

- **Issues**: GitHub Issues
- **Questions**: GitHub Discussions
- **Documentation**: This directory
- **Community**: Kubernetes Slack, Reddit

## 📝 Document Maintenance

These documents are maintained in the repository. To contribute:
1. Fork the repository
2. Make improvements
3. Submit a pull request

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

---

**Choose your path and happy learning!** 🚀
