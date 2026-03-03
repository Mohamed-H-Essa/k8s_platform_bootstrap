# ArgoCD Explained

This guide explains ArgoCD and the GitOps workflow in detail.

## What is GitOps?

**GitOps** is a modern approach to infrastructure and application management where Git is the single source of truth.

### Traditional Deployment vs GitOps

**Traditional Deployment**:
```
Developer → CI Server → Manual Deploy → Production
         (scripts)    (click buttons)
```

**Problems**:
- What's running in production? 🤷
- Who deployed this? 🤷
- How do I rollback? 😰
- Configuration drift 💢

**GitOps Deployment**:
```
Developer → Git Commit → ArgoCD → Production
                        (automated sync)
                        ↖──────────────┘
                          (continuous monitoring)
```

**Benefits**:
- Git = Single source of truth ✅
- Full audit trail ✅
- Easy rollback (git revert) ✅
- No configuration drift ✅

## What is ArgoCD?

**ArgoCD** is a declarative, GitOps continuous delivery tool for Kubernetes.

### How ArgoCD Works

```
┌─────────────────┐
│  Git Repository │
│  (Source of     │
│   Truth)        │
└────────┬────────┘
         │
         │ Polling (every 3 mins)
         │ or Webhook (instant)
         ▼
┌─────────────────┐
│    ArgoCD       │
│                 │
│  1. Detects     │
│     changes     │
│  2. Compares    │
│     Git vs Live │
│  3. Syncs       │
│     differences │
└────────┬────────┘
         │
         │ kubectl apply
         ▼
┌─────────────────┐
│   Kubernetes    │
│    Cluster      │
└─────────────────┘
```

### Key Concepts

1. **Application**: A group of Kubernetes resources managed by ArgoCD
2. **Project**: A logical grouping of Applications with restrictions
3. **Repository**: Git repository containing manifests
4. **Sync**: Process of making the cluster match Git
5. **Health**: Status of application resources

## ArgoCD Components

```
ArgoCD Namespace
│
├── argocd-application-controller
│   └── Main controller that manages applications
│       - Compares Git vs Live state
│       - Syncs differences
│       - Reports health status
│
├── argocd-repo-server
│   └── Manages Git repository access
│       - Clones repositories
│       - Caches repository content
│       - Generates manifests
│
├── argocd-server
│   └── API Server and Web UI
│       - Serves UI
│       - Handles API requests
│       - Manages authentication
│
├── argocd-dex
│   └── SSO/OIDC integration
│       - GitHub, GitLab, Google, etc.
│
├── argocd-redis
│   └── Cache for application data
│
└── argocd-notifications-controller
    └── Sends notifications
        - Slack, Email, PagerDuty, etc.
```

## The App of Apps Pattern

The **App of Apps** pattern is a way to manage multiple ArgoCD Applications with a single parent Application.

### Why Use App of Apps?

**Without App of Apps**:
```bash
kubectl apply -f app1.yaml
kubectl apply -f app2.yaml
kubectl apply -f app3.yaml
# Manual management of each app
```

**With App of Apps**:
```bash
kubectl apply -f app-of-apps.yaml
# ArgoCD automatically creates and manages all apps
```

### How It Works

```
app-of-apps.yaml (Root Application)
├── Points to: kubernetes/bootstrap/argocd/apps/
│
└── Directory contains:
    ├── namespaces.yaml
    ├── cert-manager.yaml
    ├── ingress-nginx.yaml
    └── prometheus-stack.yaml
```

**Flow**:
1. You apply app-of-apps.yaml once
2. ArgoCD reads the `apps/` directory
3. ArgoCD creates an Application for each YAML file
4. Each Application deploys its resources
5. Everything is managed via Git

### Example: Root Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/your-org/k8s-platform-bootstrap
    targetRevision: HEAD
    path: kubernetes/bootstrap/argocd/apps  # Directory of Applications

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      prune: true     # Delete resources removed from Git
      selfHeal: true  # Fix drift automatically
```

**What this does**:
- Creates the root Application
- Points to a directory of Application manifests
- Auto-sync enabled

## ArgoCD Applications

An **Application** defines:
- **Source**: Where to get manifests (Git repo, Helm chart)
- **Destination**: Where to deploy (cluster, namespace)
- **Sync Policy**: How to sync (automated or manual)

### Example: Namespaces Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: namespaces
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/your-org/k8s-platform-bootstrap
    targetRevision: HEAD
    path: kubernetes/manifests/namespaces  # Directory with YAML files

  destination:
    server: https://kubernetes.default.svc  # This cluster

  syncPolicy:
    automated:
      prune: true      # Remove resources deleted in Git
      selfHeal: true   # Automatically fix drift
    syncOptions:
      - CreateNamespace=true
```

**What this does**:
- Watches `kubernetes/manifests/namespaces/` directory
- Deploys all YAML files in that directory
- Auto-syncs when Git changes

### Example: Helm Chart Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-stack
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 52.0.1

    helm:
      values: |
        prometheus:
          prometheusSpec:
            replicas: 2
            retention: 15d

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**What this does**:
- Deploys Helm chart from remote repository
- Customizes with inline values
- Auto-syncs when chart or values change

## Sync Policies

### Automated Sync

```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources not in Git
    selfHeal: true   # Fix drift automatically
```

**What happens**:
1. You commit changes to Git
2. ArgoCD detects changes (polls every 3 min)
3. ArgoCD automatically applies changes
4. If someone manually changes resources, ArgoCD reverts them

### Manual Sync

```yaml
syncPolicy: {}  # No automated sync
```

**What happens**:
1. You commit changes to Git
2. ArgoCD shows "OutOfSync" status
3. You manually click "Sync" in UI or run `argocd app sync`

### Sync Options

```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true      # Create namespace if it doesn't exist
    - PrunePropagationPolicy=foreground  # How to delete resources
    - PruneLast=true            # Delete resources last
    - ApplyOutOfSyncOnly=true   # Only sync changed resources
    - ServerSideApply=true      # Use server-side apply
```

## Sync Waves

**Sync Waves** control the order of resource synchronization.

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # First
---
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Second
---
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"  # Third
```

**Order**:
1. Wave -5: Pre-sync
2. Wave 0: Namespaces, CRDs
3. Wave 1: Infrastructure (cert-manager, ingress)
4. Wave 2: Applications
5. Wave 5: Post-sync

**Use cases**:
- Create namespaces before deploying apps
- Install CRDs before creating CRs
- Set up infrastructure before applications

## Health Checks

ArgoCD continuously monitors application health.

### Health Status

- **Healthy**: All resources are healthy
- **Progressing**: Resources are being created/updated
- **Degraded**: Some resources are unhealthy
- **Suspended**: Resources are paused
- **Missing**: Resources don't exist

### Custom Health Checks

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  source:
    # ...
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas  # Ignore replica count
```

## ArgoCD Projects

**Projects** provide logical grouping and restrictions for Applications.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  description: Production applications

  # Source repositories
  sourceRepos:
    - 'https://github.com/myorg/*'  # Allow all repos in org

  # Destination clusters and namespaces
  destinations:
    - namespace: 'production-*'  # Allow all namespaces starting with production-
      server: https://kubernetes.default.svc

  # Resource allowlist
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace  # Allow creating namespaces

  # Resource denylist
  namespaceResourceBlacklist:
    - group: ''
      kind: ResourceQuota  # Deny ResourceQuotas
```

**What this does**:
- Creates a project called "production"
- Restricts which repos can be used
- Restricts which namespaces can be deployed to
- Restricts which resource types can be created

## ArgoCD Workflow

### Initial Setup

```
1. Install ArgoCD
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

2. Configure repository access
   kubectl apply -f argocd-cm.yaml

3. Create root Application
   kubectl apply -f app-of-apps.yaml

4. ArgoCD automatically:
   - Reads the apps directory
   - Creates Applications
   - Syncs each Application
   - Deploys all resources
```

### Continuous Deployment

```
1. Developer commits changes to Git
   git add .
   git commit -m "Update application"
   git push

2. ArgoCD detects changes (polling or webhook)
   - Compares Git state vs Live state
   - Calculates differences

3. ArgoCD syncs changes (if auto-sync enabled)
   - Applies new/changed resources
   - Deletes removed resources
   - Updates Application status

4. Monitoring continues
   - Health checks
   - Drift detection
   - Self-healing (if enabled)
```

### Rollback

```
1. Bad deployment detected

2. Option 1: Git revert
   git revert <commit>
   git push
   # ArgoCD automatically syncs the revert

3. Option 2: ArgoCD UI
   - Go to Application
   - Click "History and rollback"
   - Select previous sync
   - Click "Rollback"

4. Option 3: ArgoCD CLI
   argocd app rollback <app-name> <revision>
```

## ArgoCD CLI Commands

### Login
```bash
# Login to ArgoCD
argocd login localhost:8080

# Login with SSO
argocd login localhost:8080 --sso
```

### Application Management
```bash
# List applications
argocd app list

# Get application details
argocd app get <app-name>

# Sync application
argocd app sync <app-name>

# Refresh application
argocd app get <app-name> --refresh

# Diff application (Git vs Live)
argocd app diff <app-name>

# Delete application
argocd app delete <app-name>
```

### Project Management
```bash
# List projects
argocd proj list

# Get project details
argocd proj get <project-name>

# Create project
argocd proj create <project-name>
```

### Repository Management
```bash
# List repositories
argocd repo list

# Add repository
argocd repo add https://github.com/myorg/myrepo

# Remove repository
argocd repo remove https://github.com/myorg/myrepo
```

## Best Practices

### 1. Use App of Apps Pattern
- Single entry point
- Automatic application management
- Declarative setup

### 2. Use Projects
- Separate teams/environments
- Restrict access
- Control resource creation

### 3. Enable Auto-Sync
- Automated deployments
- No manual intervention
- GitOps workflow

### 4. Enable Self-Heal
- Prevent configuration drift
- Automatic recovery
- Consistent state

### 5. Use Sync Waves
- Control deployment order
- Handle dependencies
- Avoid race conditions

### 6. Set Resource Quotas
- Prevent runaway resources
- Control costs
- Ensure fair usage

### 7. Configure Notifications
- Slack, Email, PagerDuty
- Stay informed
- Quick response to issues

### 8. Use Health Checks
- Monitor application health
- Automatic rollbacks
- Visibility into status

## Troubleshooting

### Application stuck in "Progressing"

```bash
# Check pod status
kubectl get pods -n <namespace>

# Check events
kubectl get events -n <namespace>

# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### Sync failed

```bash
# Check sync status
argocd app get <app-name>

# Check resource status
argocd app get <app-name> --refresh

# View detailed error
argocd app get <app-name> -o yaml
```

### OutOfSync but no changes

```bash
# Check differences
argocd app diff <app-name>

# Check ignored differences
argocd app get <app-name> -o yaml | grep ignoreDifferences
```

### Repository access issues

```bash
# Check repository
argocd repo list

# Test repository access
argocd repo get <repo-url>

# Check credentials
kubectl get secret -n argocd
```

## Web UI Access

### Port Forward
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open: https://localhost:8080
```

### Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - argocd.yourdomain.com
      secretName: argocd-tls
  rules:
    - host: argocd.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  name: https
```

## Next Steps

- Configure SSO for ArgoCD
- Set up notifications (Slack, Email)
- Create custom health checks
- Configure resource hooks
- Set up image updater for automated image updates
