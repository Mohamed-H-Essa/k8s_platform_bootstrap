# Architecture Overview

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                    │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                            VPC (10.0.0.0/16)                        │ │
│  │                                                                     │ │
│  │  ┌──────────────────────────┐    ┌──────────────────────────────┐ │ │
│  │  │   Public Subnets         │    │    Private Subnets           │ │ │
│  │  │                          │    │                              │ │ │
│  │  │  ┌────────────────────┐ │    │  ┌─────────────────────────┐ │ │ │
│  │  │  │  NAT Gateway       │ │    │  │   EKS Cluster           │ │ │ │
│  │  │  │  (x3 - HA)        │ │    │  │                         │ │ │ │
│  │  │  └────────────────────┘ │    │  │  ┌──────────────────┐  │ │ │ │
│  │  │                          │    │  │  │  Control Plane   │  │ │ │ │
│  │  │  ┌────────────────────┐ │    │  │  │  (Managed)       │  │ │ │ │
│  │  │  │  Load Balancer     │ │    │  │  └──────────────────┘  │ │ │ │
│  │  │  │  (ALB/NLB)        │ │    │  │                         │ │ │ │
│  │  │  └────────────────────┘ │    │  │  ┌──────────────────┐  │ │ │ │
│  │  │                          │    │  │  │  Node Groups     │  │ │ │ │
│  │  │  ┌────────────────────┐ │    │  │  │  - General       │  │ │ │ │
│  │  │  │  Bastion Host      │ │    │  │  │  - Compute       │  │ │ │ │
│  │  │  │  (Optional)       │ │    │  │  │  - Memory        │  │ │ │ │
│  │  │  └────────────────────┘ │    │  │  └──────────────────┘  │ │ │ │
│  │  └──────────────────────────┘    │  └─────────────────────────┘ │ │
│  │                                   │                              │ │
│  │  ┌────────────────────────────────────────────────────────────┐ │ │
│  │  │                    VPC Endpoints                            │ │ │
│  │  │  S3 │ ECR │ Secrets Manager │ CloudWatch                    │ │ │
│  │  └────────────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                        AWS Services                                 │ │
│  │                                                                     │ │
│  │  S3 │ ECR │ IAM │ CloudWatch │ Route53 │ ACm │ KMS                │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

## Kubernetes Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         EKS Cluster                                  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                      ArgoCD Namespace                           │ │
│  │                                                                 │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │ │
│  │  │  ArgoCD API  │  │  Repo Server │  │  Application │        │ │
│  │  │  Server      │  │              │  │  Controller  │        │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │ │
│  │                                                                 │ │
│  │  ┌──────────────────────────────────────────────────────┐    │ │
│  │  │            App of Apps (GitOps Controller)            │    │ │
│  │  │  - Namespaces                                         │    │ │
│  │  │  - Cert-Manager                                       │    │ │
│  │  │  - Ingress-Nginx                                      │    │ │
│  │  │  - Prometheus Stack                                   │    │ │
│  │  └──────────────────────────────────────────────────────┘    │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                   Ingress-Nginx Namespace                       │ │
│  │                                                                 │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │ │
│  │  │  NGINX       │  │  NGINX       │  │  Default     │        │ │
│  │  │  Controller  │  │  Backend     │  │  Backend     │        │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                   Cert-Manager Namespace                        │ │
│  │                                                                 │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │ │
│  │  │  Cert-Manager│  │  Webhook     │  │  CA Injector │        │ │
│  │  │  Controller  │  │              │  │              │        │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │ │
│  │                                                                 │ │
│  │  ┌──────────────────────────────────────────────────────┐    │ │
│  │  │  ClusterIssuers:                                      │    │ │
│  │  │  - letsencrypt-staging                               │    │ │
│  │  │  - letsencrypt-prod                                  │    │ │
│  │  └──────────────────────────────────────────────────────┘    │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                   Monitoring Namespace                          │ │
│  │                                                                 │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │ │
│  │  │  Prometheus  │  │  AlertManager│  │  Grafana     │        │ │
│  │  │  (2 replicas)│  │  (3 replicas)│  │              │        │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │ │
│  │                                                                 │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │ │
│  │  │  Node        │  │  Kube-State  │  │  Prometheus  │        │ │
│  │  │  Exporter    │  │  Metrics     │  │  Operator    │        │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                   Application Namespaces                        │ │
│  │                                                                 │ │
│  │  Production │ Staging │ Development                            │ │
│  │                                                                 │ │
│  │  Resource Quotas │ Limit Ranges │ Network Policies            │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

## GitOps Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitOps Workflow                              │
│                                                                  │
│  ┌──────────────┐                                              │ │
│  │  Developer   │                                              │ │
│  │  Workstation │                                              │ │
│  └──────────────┘                                              │ │
│         │                                                       │ │
│         │ git push                                              │ │
│         ▼                                                       │ │
│  ┌──────────────────────────────────────────┐                 │ │
│  │         Git Repository                    │                 │ │
│  │  (GitHub/GitLab/Bitbucket)               │                 │ │
│  │                                           │                 │ │
│  │  - Kubernetes Manifests                  │                 │ │
│  │  - Helm Charts                           │                 │ │
│  │  - Configuration Files                   │                 │ │
│  └──────────────────────────────────────────┘                 │ │
│         │                                                       │ │
│         │ Webhook / Polling                                     │ │
│         ▼                                                       │ │
│  ┌──────────────────────────────────────────┐                 │ │
│  │            ArgoCD                         │                 │ │
│  │                                           │                 │ │
│  │  1. Detects changes                      │                 │ │
│  │  2. Compares Git vs Cluster              │                 │ │
│  │  3. Syncs differences                    │                 │ │
│  │  4. Reports status                       │                 │ │
│  └──────────────────────────────────────────┘                 │ │
│         │                                                       │ │
│         │ kubectl apply                                         │ │
│         ▼                                                       │ │
│  ┌──────────────────────────────────────────┐                 │ │
│  │         EKS Cluster                       │                 │ │
│  │                                           │                 │ │
│  │  - Creates/Updates resources             │                 │ │
│  │  - Maintains desired state               │                 │ │
│  │  - Self-healing                          │                 │ │
│  └──────────────────────────────────────────┘                 │ │
└─────────────────────────────────────────────────────────────────┘
```

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       Network Architecture                       │
│                                                                  │
│                      Internet                                    │
│                         │                                        │
│                         │                                        │
│                  ┌──────▼──────┐                                │
│                  │  Route53    │                                │
│                  │  (DNS)      │                                │
│                  └──────┬──────┘                                │
│                         │                                        │
│                  ┌──────▼──────┐                                │
│                  │  AWS WAF    │                                │
│                  │  (Optional) │                                │
│                  └──────┬──────┘                                │
│                         │                                        │
│                  ┌──────▼──────┐                                │
│                  │  AWS ACM    │                                │
│                  │  (TLS/SSL)  │                                │
│                  └──────┬──────┘                                │
│                         │                                        │
│                  ┌──────▼──────┐                                │
│                  │  Network LB │                                │
│                  │  (Layer 4)  │                                │
│                  └──────┬──────┘                                │
│                         │                                        │
│         ┌───────────────┼───────────────┐                       │
│         │               │               │                       │
│  ┌──────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐              │
│  │  AZ-1       │ │  AZ-2       │ │  AZ-3       │              │
│  │             │ │             │ │             │              │
│  │  Public SN  │ │  Public SN  │ │  Public SN  │              │
│  │  NAT GW     │ │  NAT GW     │ │  NAT GW     │              │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘              │
│         │               │               │                       │
│  ┌──────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐              │
│  │  Private SN │ │  Private SN │ │  Private SN │              │
│  │             │ │             │ │             │              │
│  │  EKS Nodes  │ │  EKS Nodes  │ │  EKS Nodes  │              │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘              │
│         │               │               │                       │
│         └───────────────┼───────────────┘                       │
│                         │                                        │
│                  ┌──────▼──────┐                                │
│                  │  VPC Endpoint│                               │
│                  │  (S3, ECR)  │                                │
│                  └─────────────┘                                │
└─────────────────────────────────────────────────────────────────┘
```

## Security Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Security Architecture                        │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │                   Identity & Access                     │    │
│  │                                                        │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐│    │
│  │  │  AWS IAM     │  │  IRSA        │  │  RBAC        ││    │
│  │  │  (Users/Role)│  │  (Pod Id)    │  │  (K8s Auth)  ││    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘│    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │                   Network Security                      │    │
│  │                                                        │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐│    │
│  │  │  Security    │  │  Network     │  │  VPC Flow    ││    │
│  │  │  Groups      │  │  Policies    │  │  Logs        ││    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘│    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │                   Data Security                         │    │
│  │                                                        │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐│    │
│  │  │  KMS         │  │  Secrets Mgr │  │  EBS Encrypt ││    │
│  │  │  (Keys)      │  │  (Secrets)   │  │  (Volumes)   ││    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘│    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │                   Runtime Security                      │    │
│  │                                                        │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐│    │
│  │  │  Pod Security│  │  Container   │  │  TLS/mTLS    ││    │
│  │  │  Policies    │  │  Security    │  │  (Cert-Mgr)  ││    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘│    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │                   Monitoring & Audit                    │    │
│  │                                                        │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐│    │
│  │  │  CloudTrail  │  │  CloudWatch  │  │  Prometheus  ││    │
│  │  │  (Audit)     │  │  (Metrics)   │  │  (Metrics)   ││    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘│    │
│  └────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. Infrastructure (Terraform)
- **VPC**: Multi-AZ networking with private subnets
- **EKS**: Managed Kubernetes control plane
- **Node Groups**: Auto-scaling worker nodes
- **IAM**: Role-based access control
- **Security Groups**: Network-level firewall rules

### 2. GitOps (ArgoCD)
- **Declarative Setup**: All configurations in Git
- **Automated Sync**: Continuous reconciliation
- **Rollback**: Easy rollback to previous states
- **Audit Trail**: Complete history of changes

### 3. Observability (Prometheus Stack)
- **Metrics**: Resource utilization and performance
- **Alerting**: Automated incident detection
- **Visualization**: Grafana dashboards
- **Long-term Storage**: Prometheus with persistent storage

### 4. Networking (Ingress-Nginx)
- **Load Balancing**: Distribute traffic across pods
- **TLS Termination**: HTTPS with Let's Encrypt
- **Path-based Routing**: Route to different services
- **Rate Limiting**: Protect applications

### 5. Security (Cert-Manager)
- **Automatic Certificates**: Let's Encrypt integration
- **Certificate Renewal**: Automatic renewal before expiry
- **Multiple Issuers**: Staging and production
- **Wildcard Support**: DNS-01 challenge support

## Design Principles

1. **Infrastructure as Code**: All infrastructure defined in code
2. **GitOps**: Git as single source of truth
3. **Immutable Infrastructure**: Replace, don't modify
4. **Defense in Depth**: Multiple security layers
5. **High Availability**: Multi-AZ deployment
6. **Cost Optimization**: Right-sized resources
7. **Observability**: Complete visibility into system
8. **Automation**: Minimize manual intervention

## Scaling Strategy

- **Horizontal**: Add more nodes via cluster autoscaler
- **Vertical**: Increase node size for compute-intensive workloads
- **Pod Autoscaling**: HPA for dynamic workload scaling
- **Multi-Region**: Active-active or active-passive setups
