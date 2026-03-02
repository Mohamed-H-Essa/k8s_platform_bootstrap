# Contributing to K8s Platform Bootstrap

Thank you for your interest in contributing to K8s Platform Bootstrap! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for all contributors.

## How to Contribute

### Reporting Issues

1. Check if the issue has already been reported
2. Use the issue template to create a detailed report
3. Include:
   - Steps to reproduce
   - Expected behavior
   - Actual behavior
   - Environment details (OS, Terraform version, etc.)
   - Relevant logs or screenshots

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Development Setup

### Prerequisites

- Terraform >= 1.5.0
- kubectl >= 1.28
- Helm >= 3.12
- AWS CLI >= 2.13

### Local Testing

1. **Terraform Validation**
   ```bash
   cd terraform/environments/dev
   terraform init
   terraform validate
   terraform plan
   ```

2. **Kubernetes Manifest Validation**
   ```bash
   kubectl apply --dry-run=client -f kubernetes/manifests/
   ```

3. **Helm Chart Validation**
   ```bash
   helm lint kubernetes/helm-charts/*
   helm template test-release kubernetes/helm-charts/your-chart
   ```

## Coding Standards

### Terraform

- Use consistent naming: `snake_case` for resources and variables
- Document all variables with descriptions
- Use modules for reusable components
- Follow [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

Example:
```hcl
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "Cluster name must not be empty."
  }
}
```

### Kubernetes Manifests

- Use consistent labeling (follow Kubernetes conventions)
- Include resource requests and limits
- Use namespaces for isolation
- Follow [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)

Example labels:
```yaml
metadata:
  labels:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/instance: myapp-prod
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: platform
    app.kubernetes.io/managed-by: argocd
```

### Shell Scripts

- Use `set -euo pipefail` for error handling
- Add comments for complex logic
- Make scripts idempotent
- Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)

Example:
```bash
#!/bin/bash
set -euo pipefail

# Function with clear purpose
deploy_application() {
    local app_name=$1
    log_info "Deploying application: $app_name"
    kubectl apply -f "manifests/${app_name}.yaml"
}
```

## Testing

### Before Submitting PR

1. **Validate Terraform**
   ```bash
   terraform fmt -check -recursive
   terraform validate
   ```

2. **Validate Kubernetes Manifests**
   ```bash
   kubectl apply --dry-run=client -k kubernetes/manifests/
   ```

3. **Test Deployment** (if applicable)
   - Deploy to a test environment
   - Verify all components are functioning
   - Check logs for errors

4. **Update Documentation**
   - Update README.md if needed
   - Update inline documentation
   - Add comments for complex logic

## Pull Request Process

1. **PR Title**: Clear and descriptive
   - `feat: Add support for custom VPC CIDR`
   - `fix: Resolve IAM role creation issue`
   - `docs: Update deployment guide`

2. **PR Description**:
   - What changes were made
   - Why they were made
   - How to test them
   - Any breaking changes

3. **Review Process**:
   - At least one approval required
   - All CI checks must pass
   - No merge conflicts
   - Documentation updated

4. **After Approval**:
   - Squash commits if needed
   - Maintain a clean commit history
   - Maintainer will merge

## Project Structure

```
k8s-platform-bootstrap/
├── terraform/
│   ├── modules/              # Reusable modules
│   └── environments/         # Environment configs
├── kubernetes/
│   ├── bootstrap/           # Initial setup
│   ├── manifests/           # Kubernetes resources
│   └── helm-charts/         # Custom charts
├── scripts/                 # Utility scripts
└── docs/                    # Documentation
```

## Getting Help

- **Issues**: Create an issue on GitHub
- **Discussions**: Use GitHub Discussions
- **Documentation**: Check `docs/` directory

## Recognition

Contributors will be recognized in:
- Release notes
- Contributors file
- Project README

Thank you for contributing! 🎉
