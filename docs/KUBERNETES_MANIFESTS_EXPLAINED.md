# Kubernetes Manifests Explained

This guide explains every Kubernetes manifest in the project, line by line.

## What is a Kubernetes Manifest?

A **manifest** is a YAML file that describes the desired state of your Kubernetes resources. It's declarative - you describe WHAT you want, and Kubernetes figures out HOW to achieve it.

## Directory Structure

```
kubernetes/
├── bootstrap/
│   └── argocd/                  # ArgoCD installation and config
│       ├── install.yaml         # ArgoCD namespace and config
│       ├── app-of-apps.yaml     # Root application (GitOps)
│       └── apps/                # ArgoCD application definitions
│           ├── namespaces.yaml
│           ├── cert-manager.yaml
│           ├── ingress-nginx.yaml
│           └── prometheus-stack.yaml
│
└── manifests/                   # Kubernetes resources
    ├── namespaces/
    │   └── namespaces.yaml      # Namespace definitions
    └── cert-manager/
        └── cluster-issuers.yaml # TLS certificate issuers
```

## Namespaces (`manifests/namespaces/namespaces.yaml`)

### What is a Namespace?

Namespaces are like folders in a file system - they organize and isolate resources.

**Why use namespaces?**
- **Isolation**: Production doesn't affect staging
- **Resource Quotas**: Limit CPU/memory per namespace
- **Access Control**: Different teams, different permissions
- **Organization**: Easier to find and manage resources

### File Breakdown

```yaml
---
# Document separator (YAML allows multiple documents in one file)

# Create the monitoring namespace
apiVersion: v1                    # API version
kind: Namespace                   # Resource type
metadata:                         # Metadata about the resource
  name: monitoring               # Name of the namespace
  labels:                        # Key-value pairs for organization
    name: monitoring
    app.kubernetes.io/component: observability
    # Pod Security Standards labels
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

**What this does**:
- Creates a namespace called "monitoring"
- Labels it for organization
- Sets Pod Security Standards to "privileged" (monitoring needs elevated permissions)

**Pod Security Standards**:
- **privileged**: Unrestricted (for system components)
- **baseline**: Minimally restrictive (for most apps)
- **restricted**: Heavily restricted (for security-critical apps)

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
  labels:
    name: cert-manager
    app.kubernetes.io/component: security
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**What this does**:
- Creates namespace for cert-manager
- Uses "restricted" security (cert-manager is security-critical)

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    name: production
    environment: production
    app.kubernetes.io/component: workloads
    pod-security.kubernetes.io/enforce: restricted
```

**What this does**:
- Creates production namespace for your applications
- Most restrictive security policy
```

### Resource Quotas

```yaml
---
# Resource Quota for production namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production  # Which namespace this applies to
spec:
  hard:                  # Hard limits (cannot be exceeded)
    requests.cpu: "20"      # Total CPU requests
    requests.memory: 40Gi   # Total memory requests
    limits.cpu: "40"        # Total CPU limits
    limits.memory: 80Gi     # Total memory limits
    persistentvolumeclaims: "10"  # Number of PVCs
    pods: "50"              # Number of pods
    services: "20"          # Number of services
    secrets: "50"           # Number of secrets
    configmaps: "50"        # Number of configmaps
```

**What this does**:
- Limits total resources in production namespace
- Prevents runaway resource usage
- Ensures fair resource distribution

**Requests vs Limits**:
- **requests**: Guaranteed resources (what the pod gets)
- **limits**: Maximum resources (what the pod can burst to)

```yaml
---
# Resource Quota for staging namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: staging-quota
  namespace: staging
spec:
  hard:
    requests.cpu: "10"      # Half of production
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    persistentvolumeclaims: "5"
    pods: "20"
    services: "10"
    secrets: "30"
    configmaps: "30"
```

**What this does**:
- Lower limits for staging (cost optimization)
- Prevents staging from using too many resources

### Limit Ranges

```yaml
---
# Limit Range sets defaults and constraints for individual containers
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
    - default:              # Default limits (if not specified)
        cpu: 500m          # 0.5 CPU cores
        memory: 512Mi      # 512 MB
      defaultRequest:       # Default requests (if not specified)
        cpu: 100m          # 0.1 CPU cores
        memory: 128Mi      # 128 MB
      type: Container      # Apply to containers
    - max:                  # Maximum allowed
        cpu: "4"           # 4 CPU cores
        memory: 8Gi        # 8 GB
      min:                  # Minimum allowed
        cpu: 50m           # 0.05 CPU cores
        memory: 64Mi       # 64 MB
      type: Container
```

**What this does**:
- Sets default resources if pod doesn't specify them
- Sets min/max constraints
- Prevents pods from being created without resource limits

**Why this matters**:
- Without limits, a runaway pod can consume all cluster resources
- Without requests, Kubernetes can't efficiently schedule pods

## Cert-Manager (`manifests/cert-manager/cluster-issuers.yaml`)

### What is Cert-Manager?

**Cert-Manager** is a Kubernetes add-on that automates TLS certificate management.

**Why use it?**
- **Automation**: Automatically issues and renews certificates
- **Let's Encrypt**: Free TLS certificates
- **Security**: HTTPS for your applications
- **Convenience**: No manual certificate management

### File Breakdown

```yaml
---
# ClusterIssuer for Let's Encrypt staging
# Use this for testing (doesn't count against rate limits)
apiVersion: cert-manager.io/v1    # Cert-Manager API
kind: ClusterIssuer              # Issuer that works across all namespaces
metadata:
  name: letsencrypt-staging
  namespace: cert-manager
spec:
  acme:                          # Automatic Certificate Management Environment
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    # Staging server (for testing)
    # Uses fake certificates (browsers will warn)
    # No rate limits

    email: your-email@example.com  # YOUR EMAIL HERE
    # Let's Encrypt sends expiry notices here

    privateKeySecretRef:
      name: letsencrypt-staging  # Secret to store ACME account key

    solvers:                     # How to prove domain ownership
      - http01:                  # HTTP-01 challenge
          ingress:
            class: nginx         # Use NGINX ingress
```

**What this does**:
- Creates a ClusterIssuer for Let's Encrypt staging
- Uses HTTP-01 challenge (proves ownership by serving a file on the domain)
- Stores account key in a Kubernetes secret

**HTTP-01 Challenge**:
1. Let's Encrypt gives you a token
2. Cert-manager creates an Ingress to serve the token at `http://your-domain/.well-known/acme-challenge/<token>`
3. Let's Encrypt verifies it can access the token
4. Certificate is issued

```yaml
---
# ClusterIssuer for Let's Encrypt production
# Use this for production (real certificates)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    # Production server (real certificates)
    # Browsers will trust these certificates
    # HAS rate limits (50 certificates per domain per week)

    email: your-email@example.com

    privateKeySecretRef:
      name: letsencrypt-prod

    solvers:
      - http01:
          ingress:
            class: nginx
```

**What this does**:
- Creates a ClusterIssuer for Let's Encrypt production
- Issues real, trusted certificates
- Subject to rate limits

**Rate Limits**:
- 50 certificates per domain per week
- Use staging for testing to avoid hitting limits

### How to Use Cert-Manager

1. **Create an Ingress with TLS**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod  # Reference the issuer
spec:
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls  # Cert-manager stores cert here
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

2. **Cert-manager automatically**:
   - Creates a Certificate resource
   - Requests certificate from Let's Encrypt
   - Proves domain ownership (HTTP-01 challenge)
   - Stores certificate in the secret
   - Renews before expiry (30 days by default)

## ArgoCD Bootstrap (`bootstrap/argocd/`)

### ArgoCD Application Model

ArgoCD uses the "App of Apps" pattern:
```
Root Application (app-of-apps.yaml)
├── Namespaces Application
├── Cert-Manager Application
├── NGINX Ingress Application
└── Prometheus Stack Application
```

### File: `install.yaml`

```yaml
---
# Create ArgoCD namespace
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
  labels:
    name: argocd
    app.kubernetes.io/name: argocd
    app.kubernetes.io/component: gitops
```

**What this does**:
- Creates isolated namespace for ArgoCD

```yaml
---
# ArgoCD Configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  # Repository configuration
  repositories: |
    - type: git
      url: https://github.com/your-org/k8s-platform-bootstrap
      # UPDATE THIS with your repository URL

  # Enable Helm support
  helm.valuesFileSchemes: >-
    secrets+gpg-import, secrets+gpg-import-kubernetes,
    secrets+age-import, secrets+age-import-kubernetes,
    secrets, https

  # Ignore differences in certain fields
  resource.customizations: |
    admissionregistration.k8s.io/MutatingWebhookConfiguration:
      ignoreDifferences: |
        jsonPointers:
        - /webhooks/0/clientConfig/caBundle
        # CA bundles change, ignore them
```

**What this does**:
- Configures ArgoCD
- Sets up repository access
- Configures Helm support
- Defines how to handle differences

```yaml
---
# ArgoCD RBAC Configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  # Default policy for unauthenticated users
  policy.default: role:readonly

  # Custom policy (admin access)
  policy.csv: |
    # Grant admin access to a team
    g, your-github-team, role:admin
    # Or individual user
    g, your-github-username, role:admin
    # UPDATE THIS with your actual users/teams

  # Scopes to use for SSO
  scopes: "[groups]"
```

**What this does**:
- Configures access control
- Sets default permissions
- Defines admin users/teams

### File: `app-of-apps.yaml`

```yaml
---
# Root Application - App of Apps Pattern
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
    # Ensures resources are cleaned up when app is deleted
spec:
  project: default

  source:
    repoURL: https://github.com/your-org/k8s-platform-bootstrap
    targetRevision: HEAD  # Or a specific branch/tag
    path: kubernetes/bootstrap/argocd/apps  # Directory containing app manifests

  destination:
    server: https://kubernetes.default.svc  # Deploy to same cluster
    namespace: argocd

  syncPolicy:
    automated:
      prune: true  # Delete resources that are no longer in Git
      selfHeal: true  # Fix drift automatically
      allowEmpty: false
    syncOptions:
      - Validate=true  # Validate manifests before applying
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

**What this does**:
- Creates the root application
- Points to directory containing other applications
- Enables auto-sync (GitOps)
- Configures retry logic

**How it works**:
1. ArgoCD reads `kubernetes/bootstrap/argocd/apps/` directory
2. Finds all Application manifests
3. Creates each Application
4. Each Application deploys its resources
5. Continuous monitoring and sync

### File: `apps/namespaces.yaml`

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: namespaces
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/your-org/k8s-platform-bootstrap
    targetRevision: HEAD
    path: kubernetes/manifests/namespaces  # Path to namespace manifests

  destination:
    server: https://kubernetes.default.svc

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**What this does**:
- Creates an Application for namespaces
- Points to namespace manifests
- Enables auto-sync

### File: `apps/prometheus-stack.yaml`

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-stack
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack  # Helm chart
    targetRevision: 52.0.1        # Chart version

    helm:
      values: |
        # Prometheus Configuration
        prometheus:
          prometheusSpec:
            replicas: 2
            retention: 15d  # Keep metrics for 15 days
            storageSpec:
              volumeClaimTemplate:
                spec:
                  storageClassName: gp2
                  resources:
                    requests:
                      storage: 50Gi  # 50GB storage

        # Grafana Configuration
        grafana:
          adminPassword: "your-secure-password"  # UPDATE THIS

          ingress:
            enabled: true
            hosts:
              - grafana.yourdomain.com  # UPDATE THIS
```

**What this does**:
- Deploys Prometheus Stack using Helm
- Configures Prometheus with persistent storage
- Configures Grafana with ingress
- Customizes via Helm values

## Best Practices Used

1. **Label Standardization**: Using `app.kubernetes.io/*` labels
2. **Resource Quotas**: Preventing resource exhaustion
3. **Pod Security**: Enforcing security standards
4. **Declarative State**: All resources defined in Git
5. **Auto-Sync**: GitOps automated synchronization
6. **Namespaces**: Logical separation of concerns
7. **TLS Automation**: Cert-manager for HTTPS

## Common Operations

### Apply a manifest manually
```bash
kubectl apply -f manifest.yaml
```

### Delete resources in a manifest
```bash
kubectl delete -f manifest.yaml
```

### View resources
```bash
kubectl get all -n <namespace>
```

### Describe a resource
```bash
kubectl describe deployment <name> -n <namespace>
```

### View logs
```bash
kubectl logs -f deployment/<name> -n <namespace>
```

### Edit a resource
```bash
kubectl edit deployment <name> -n <namespace>
```

## Debugging Tips

1. **Check resource status**:
```bash
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
```

2. **Check events**:
```bash
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

3. **Check logs**:
```bash
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous container
```

4. **Check ArgoCD application status**:
```bash
argocd app get <app-name>
kubectl get application <app-name> -n argocd -o yaml
```

## Next Steps

- Read [ARGOCD_EXPLAINED.md](ARGOCD_EXPLAINED.md) to understand GitOps setup
- Read [WORKFLOW.md](WORKFLOW.md) to understand the deployment workflow
