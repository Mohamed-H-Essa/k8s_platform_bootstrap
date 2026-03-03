# Beginner's Guide to K8s Platform Bootstrap

Welcome! This guide will walk you through everything you need to know to understand and use this project, even if you're new to Kubernetes and AWS.

## What Are We Building?

We're creating a **production-ready Kubernetes cluster on AWS** that includes:
- A cluster of computers (servers) that run your applications
- Automatic monitoring to track how your applications are performing
- Automatic security (TLS certificates) for your websites
- A GitOps system that automatically deploys your code changes

Think of it as setting up a fully-managed data center in the cloud that runs your applications automatically.

## Who Is This For?

- **Developers** who want to deploy applications to Kubernetes
- **DevOps Engineers** learning Kubernetes and AWS
- **Teams** wanting a production-ready infrastructure starter kit
- **Anyone** interested in modern cloud infrastructure

## Prerequisites

Before starting, you should have:

### Knowledge Prerequisites
- Basic command line usage (Terminal/PowerShell)
- Basic understanding of what a server is
- Basic Git knowledge (clone, commit, push)
- A general idea of what containers are (Docker)

### Technical Prerequisites
- A computer with admin access (to install tools)
- An AWS account (we'll help you set this up)
- About $450-500/month budget for AWS costs

## Key Concepts Explained

### 1. What is Kubernetes?

**Kubernetes (K8s)** is like a conductor of an orchestra, but for computers.

Imagine you have 10 applications that need to run across 5 servers. Kubernetes:
- Decides which server runs which application
- Restarts applications if they crash
- Scales applications up/down based on demand
- Manages networking between applications

**Analogy**: If Docker containers are like shipping containers, Kubernetes is the shipping yard that organizes them all.

### 2. What is EKS?

**Amazon EKS (Elastic Kubernetes Service)** is AWS's managed Kubernetes.

Instead of installing and maintaining Kubernetes yourself (which is complex), AWS does it for you:
- AWS manages the Kubernetes control plane (the "brain")
- You just provide the worker nodes (the "muscle")
- AWS handles updates, patches, and high availability

**Benefit**: You focus on your applications, not on managing Kubernetes itself.

### 3. What is Terraform?

**Terraform** is a tool for writing infrastructure as code.

Instead of clicking buttons in AWS console to create servers, networks, and databases, you write code that describes what you want:

```hcl
# This creates a server
resource "aws_instance" "example" {
  ami           = "ami-12345"
  instance_type = "t2.micro"
}
```

**Benefits**:
- **Reproducible**: Create identical environments easily
- **Version Controlled**: Track changes in Git
- **Automated**: Run one command to create everything
- **Collaborative**: Team can review and contribute

**Analogy**: Terraform is like a blueprint for building a house. You write the blueprint once, and can build the same house anywhere.

### 4. What is GitOps?

**GitOps** is a way to manage infrastructure using Git as the single source of truth.

Traditional approach:
1. Developer makes code changes
2. Developer runs scripts to deploy
3. Infrastructure state is unknown

GitOps approach:
1. Developer makes code changes in Git
2. Automated system detects changes
3. Automated system deploys changes
4. Git always matches what's running

**Benefits**:
- **Traceability**: Every change is tracked in Git
- **Rollback**: Revert to previous state easily
- **Audit Trail**: Know who changed what and when
- **Automation**: No manual deployment steps

### 5. What is ArgoCD?

**ArgoCD** is a GitOps tool for Kubernetes.

It continuously monitors your Git repository and ensures your Kubernetes cluster matches what's in Git:

```
Git Repository (Desired State) ←→ ArgoCD ←→ Kubernetes Cluster (Actual State)
```

**How it works**:
1. You commit Kubernetes manifests to Git
2. ArgoCD detects the changes
3. ArgoCD applies changes to the cluster
4. ArgoCD monitors and reports status

**Analogy**: ArgoCD is like an automated assistant that ensures your cluster always matches your instructions in Git.

### 6. What is a Container?

A **container** is a lightweight, standalone package that includes everything needed to run an application:
- Code
- Runtime
- System tools
- Libraries
- Settings

**Benefits**:
- **Consistent**: Runs the same everywhere (dev, staging, prod)
- **Isolated**: One container doesn't affect others
- **Efficient**: Uses less resources than virtual machines
- **Portable**: Move between clouds easily

### 7. What is a Pod?

A **Pod** is the smallest deployable unit in Kubernetes.

A Pod contains one or more containers that:
- Share storage and network
- Are always scheduled together
- Can communicate with each other easily

**Analogy**: If a container is like a process, a Pod is like a group of processes that work together.

### 8. What is a Node?

A **Node** is a worker machine in Kubernetes (a server).

Each node has:
- A container runtime (Docker or containerd)
- Kubelet (agent that talks to the control plane)
- kube-proxy (manages network rules)

**Analogy**: Nodes are like the workers in a factory, running the machines (containers).

### 9. What is a Cluster?

A **Cluster** is a collection of nodes that run containerized applications.

A cluster consists of:
- **Control Plane**: The brain (manages the cluster)
- **Worker Nodes**: The muscle (runs your applications)

**Analogy**: A cluster is like the entire factory, with management (control plane) and workers (nodes).

### 10. What is a Namespace?

A **Namespace** is a way to divide cluster resources between multiple users/projects.

Think of it as folders in a file system:
- Each namespace has its own resources
- Namespaces can have resource quotas
- Provides isolation between environments

**Example**:
```
Cluster
├── Namespace: production
│   ├── App 1
│   └── App 2
├── Namespace: staging
│   ├── App 1
│   └── App 2
└── Namespace: monitoring
    ├── Prometheus
    └── Grafana
```

## Project Architecture Overview

### What Does This Project Create?

```
Your Computer
      ↓
  Git Repository (Source of Truth)
      ↓
  ArgoCD (GitOps Controller)
      ↓
  EKS Cluster (Kubernetes on AWS)
      ├── Monitoring (Prometheus + Grafana)
      ├── Ingress (NGINX - routes traffic)
      ├── Certificates (Cert-Manager - TLS)
      └── Your Applications
```

### The Components

#### 1. Infrastructure Layer (Terraform)
- **VPC**: Private network in AWS
- **EKS**: Managed Kubernetes cluster
- **Node Groups**: Worker servers
- **IAM**: Permissions and security
- **Security Groups**: Firewall rules

#### 2. Platform Layer (ArgoCD)
- **ArgoCD**: GitOps controller
- **Namespaces**: Resource organization
- **Resource Quotas**: Limits per namespace

#### 3. Services Layer
- **Prometheus**: Metrics collection
- **Grafana**: Visualization dashboards
- **AlertManager**: Alert routing
- **NGINX Ingress**: Traffic routing
- **Cert-Manager**: TLS automation

## File Structure Explained

```
k8s-platform-bootstrap/
│
├── terraform/                     # Infrastructure definitions
│   ├── modules/                   # Reusable components
│   │   ├── vpc/                  # Network setup
│   │   │   ├── main.tf           # Creates VPC, subnets, NAT
│   │   │   ├── variables.tf      # Input parameters
│   │   │   └── outputs.tf        # Output values
│   │   └── eks/                  # Kubernetes cluster
│   │       ├── main.tf           # Creates EKS cluster
│   │       ├── variables.tf      # Input parameters
│   │       └── outputs.tf        # Cluster endpoint, etc.
│   │
│   └── environments/              # Environment-specific configs
│       └── prod/                 # Production environment
│           ├── main.tf           # Uses modules to create prod
│           ├── variables.tf      # Prod-specific variables
│           ├── outputs.tf        # What we get from prod
│           └── terraform.tfvars.example # Example configuration
│
├── kubernetes/                    # Kubernetes configurations
│   ├── bootstrap/                # Initial setup
│   │   └── argocd/              # ArgoCD installation
│   │       ├── install.yaml     # ArgoCD setup
│   │       ├── app-of-apps.yaml # Root application
│   │       └── apps/            # Application definitions
│   │           ├── namespaces.yaml      # Create namespaces
│   │           ├── cert-manager.yaml    # TLS automation
│   │           ├── ingress-nginx.yaml   # Traffic routing
│   │           └── prometheus-stack.yaml # Monitoring
│   │
│   └── manifests/                # Kubernetes resources
│       ├── namespaces/          # Namespace definitions
│       │   └── namespaces.yaml  # Creates prod, staging, etc.
│       └── cert-manager/        # Certificate config
│           └── cluster-issuers.yaml # Let's Encrypt setup
│
├── scripts/                       # Automation scripts
│   ├── setup.sh                 # Deploy everything
│   └── destroy.sh               # Clean up everything
│
└── docs/                          # Documentation
    ├── BEGINNERS_GUIDE.md       # This file
    ├── QUICK_START.md           # Quick deployment guide
    ├── DEPLOYMENT.md            # Detailed deployment
    └── ARCHITECTURE.md          # Architecture details
```

## How Does It All Work Together?

### Step-by-Step Flow

#### 1. Infrastructure Creation (Terraform)
```bash
# You run this command
terraform apply

# Terraform does this:
1. Reads configuration files
2. Plans what to create
3. Creates VPC (network)
4. Creates EKS cluster
5. Creates worker nodes
6. Creates IAM roles
7. Sets up networking
```

**Time**: ~10-12 minutes

#### 2. Cluster Configuration (kubectl)
```bash
# You run this command
aws eks update-kubeconfig --name prod-cluster

# This does:
1. Gets cluster credentials
2. Configures kubectl
3. Tests connection
```

**Time**: ~30 seconds

#### 3. ArgoCD Installation
```bash
# You run this command
kubectl apply -f kubernetes/bootstrap/argocd/

# This does:
1. Creates argocd namespace
2. Deploys ArgoCD components
3. Waits for readiness
```

**Time**: ~2 minutes

#### 4. GitOps Deployment
```bash
# You run this command
kubectl apply -f kubernetes/bootstrap/argocd/app-of-apps.yaml

# ArgoCD does this:
1. Reads application definitions
2. Creates Namespaces
3. Deploys Cert-Manager
4. Deploys NGINX Ingress
5. Deploys Prometheus Stack
6. Monitors for changes
```

**Time**: ~2-3 minutes

### What Happens When You Deploy an App?

1. **You commit** a Kubernetes manifest to Git
2. **ArgoCD detects** the change (polls every 3 minutes by default)
3. **ArgoCD compares** Git vs cluster state
4. **ArgoCD applies** changes to cluster
5. **Kubernetes** creates pods, services, etc.
6. **Your app** is running!

## Understanding the Technologies

### Terraform Deep Dive

Terraform uses **declarative syntax** - you describe WHAT you want, not HOW to get it.

**Example** - Creating a VPC:
```hcl
# This is what you write
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "my-vpc"
  }
}

# Terraform figures out:
# - What API calls to make
# - What order to make them
# - How to handle dependencies
# - How to track state
```

#### Key Terraform Concepts

1. **Providers**: Plugins that interact with APIs
   ```hcl
   provider "aws" {
     region = "us-west-2"
   }
   ```

2. **Resources**: Infrastructure components
   ```hcl
   resource "aws_instance" "example" {
     ami           = "ami-12345"
     instance_type = "t2.micro"
   }
   ```

3. **Modules**: Reusable groups of resources
   ```hcl
   module "vpc" {
     source = "./modules/vpc"
     name   = "my-vpc"
   }
   ```

4. **Variables**: Parameterize configurations
   ```hcl
   variable "cluster_name" {
     description = "Name of the cluster"
     type        = string
     default     = "prod-cluster"
   }
   ```

5. **Outputs**: Export values
   ```hcl
   output "cluster_endpoint" {
     value = aws_eks_cluster.main.endpoint
   }
   ```

### Kubernetes Deep Dive

Kubernetes uses **declarative manifests** - YAML files that describe desired state.

**Example** - Deploying an application:
```yaml
# Deployment - manages pods
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3              # Run 3 copies
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
```

#### Key Kubernetes Concepts

1. **Pod**: Smallest deployable unit
   - Contains one or more containers
   - Shares network and storage

2. **Deployment**: Manages ReplicaSets and Pods
   - Ensures desired number of replicas
   - Handles rolling updates
   - Can rollback changes

3. **Service**: Provides network access to Pods
   - Stable IP address
   - Load balancing
   - Service discovery

4. **Ingress**: Routes external traffic to Services
   - URL-based routing
   - TLS termination
   - Load balancing

5. **ConfigMap**: Stores configuration data
   - Non-sensitive data
   - Can be mounted as files or env vars

6. **Secret**: Stores sensitive data
   - Passwords, tokens, keys
   - Base64 encoded
   - Can be encrypted at rest

7. **Namespace**: Virtual cluster within a cluster
   - Resource isolation
   - Resource quotas
   - Name scope

### AWS Services Used

1. **VPC (Virtual Private Cloud)**: Your private network
   - Isolated from other AWS customers
   - You control IP addressing
   - You control routing

2. **Subnets**: Sub-divisions of a VPC
   - Public: Have internet access via IGW
   - Private: No direct internet access

3. **NAT Gateway**: Allows private subnets to access internet
   - Outbound only
   - Managed by AWS
   - $0.045/hour per AZ

4. **EKS (Elastic Kubernetes Service)**: Managed Kubernetes
   - AWS manages control plane
   - Automatic updates
   - High availability

5. **EC2 (Elastic Compute Cloud)**: Virtual machines
   - Worker nodes run on EC2
   - Various instance types
   - Pay per hour

6. **IAM (Identity and Access Management)**: Permissions
   - Roles for services
   - Policies define permissions
   - IRSA for pods

7. **ELB (Elastic Load Balancer)**: Traffic distribution
   - NLB (Network Load Balancer)
   - ALB (Application Load Balancer)

8. **S3**: Object storage
   - Terraform state storage
   - Highly durable

9. **DynamoDB**: NoSQL database
   - Terraform state locking

## Common Questions

### Why Use This Instead of AWS Console?

**Manual (Console)**:
- Click, click, click to create resources
- Hard to reproduce
- No version control
- Difficult to collaborate
- Prone to human error
- Time-consuming

**Infrastructure as Code (Terraform)**:
- Write once, deploy many times
- Version controlled in Git
- Easy collaboration
- Consistent and repeatable
- Automated
- Fast

### Why Use GitOps?

**Traditional CI/CD**:
- Scripts in CI server
- Hard to see what's deployed
- Manual intervention needed
- Difficult rollback

**GitOps**:
- Git is the source of truth
- See exact state in Git
- Automated sync
- Easy rollback (git revert)

### Why So Many Namespaces?

Namespaces provide:
1. **Isolation**: Production doesn't affect staging
2. **Resource Quotas**: Limit resources per team/project
3. **Access Control**: Different teams, different permissions
4. **Organization**: Easier to manage resources

### Why Private Subnets?

Private subnets are more secure:
1. Worker nodes aren't directly accessible from internet
2. Must use bastion host or VPN to access
3. Reduced attack surface
4. Compliance requirements

### What About Costs?

**Monthly estimate** (us-west-2):
- EKS Control Plane: $72
- 3x m5.large instances: $260
- 3x NAT Gateways: $64
- Load Balancers: $40
- CloudWatch Logs: $20
- **Total**: ~$456/month

**Ways to reduce costs**:
- Use Spot instances (up to 90% discount)
- Use smaller instances for dev
- Single NAT Gateway for non-prod
- Use cluster autoscaler (only pay for what you use)

## Next Steps

Now that you understand the concepts:

1. Read [QUICK_START.md](QUICK_START.md) to deploy your first cluster
2. Read [DEPLOYMENT.md](DEPLOYMENT.md) for detailed instructions
3. Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand the design

## Learning Resources

### Kubernetes
- [Kubernetes Official Docs](https://kubernetes.io/docs/home/)
- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
- [Kubernetes Up & Running](https://www.oreilly.com/library/view/kubernetes-up-and/9781492046523/)

### Terraform
- [Terraform Official Docs](https://www.terraform.io/docs)
- [Terraform: Up & Running](https://www.oreilly.com/library/view/terraform-up-and/9781491977077/)

### AWS
- [AWS Documentation](https://docs.aws.amazon.com/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

### GitOps
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [GitOps Principles](https://opengitops.dev/)

## Getting Help

- **Issues**: Open an issue on GitHub
- **Documentation**: Check the docs/ directory
- **Community**: Kubernetes Slack, Reddit, Stack Overflow

---

**Congratulations!** You now understand the fundamentals of this project. Let's deploy your cluster! 🚀
