#!/bin/bash

# K8s Platform Bootstrap - Setup Script
# This script initializes and deploys the entire platform

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws")
    fi

    # Check Helm
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again."
        exit 1
    fi

    log_success "All prerequisites met!"
}

# Check AWS credentials
check_aws_credentials() {
    log_info "Checking AWS credentials..."

    if aws sts get-caller-identity &> /dev/null; then
        log_success "AWS credentials are valid!"
        aws sts get-caller-identity
    else
        log_error "AWS credentials not configured or invalid"
        log_info "Please configure AWS credentials using:"
        log_info "  export AWS_ACCESS_KEY_ID=your-key"
        log_info "  export AWS_SECRET_ACCESS_KEY=your-secret"
        log_info "  export AWS_REGION=us-west-2"
        log_info "Or run: aws configure"
        exit 1
    fi
}

# Initialize Terraform
init_terraform() {
    local env=$1

    log_info "Initializing Terraform for environment: $env"

    cd "terraform/environments/$env"

    # Create terraform.tfvars if it doesn't exist
    if [ ! -f "terraform.tfvars" ]; then
        log_warning "terraform.tfvars not found, creating from example..."
        if [ -f "terraform.tfvars.example" ]; then
            cp terraform.tfvars.example terraform.tfvars
            log_info "Created terraform.tfvars from example. Please edit it with your values."
        else
            log_warning "No example file found. Please create terraform.tfvars manually."
        fi
    fi

    terraform init
    log_success "Terraform initialized!"

    cd ../../..
}

# Plan Terraform changes
plan_terraform() {
    local env=$1

    log_info "Planning Terraform changes for environment: $env"

    cd "terraform/environments/$env"
    terraform plan -out=tfplan
    log_success "Terraform plan completed!"

    cd ../../..
}

# Apply Terraform changes
apply_terraform() {
    local env=$1

    log_info "Applying Terraform changes for environment: $env"

    cd "terraform/environments/$env"

    # Ask for confirmation
    read -p "Do you want to apply these changes? (yes/no): " -r
    echo
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        terraform apply -auto-approve
        log_success "Terraform apply completed!"
    else
        log_warning "Terraform apply cancelled."
        exit 0
    fi

    cd ../../..
}

# Configure kubectl
configure_kubectl() {
    local env=$1
    local cluster_name=$2
    local region=$3

    log_info "Configuring kubectl for cluster: $cluster_name"

    aws eks update-kubeconfig \
        --name "$cluster_name" \
        --region "$region"

    log_success "kubectl configured!"

    # Verify connection
    log_info "Verifying cluster connection..."
    if kubectl cluster-info &> /dev/null; then
        log_success "Successfully connected to cluster!"
        kubectl cluster-info
    else
        log_error "Failed to connect to cluster"
        exit 1
    fi
}

# Install ArgoCD
install_argocd() {
    log_info "Installing ArgoCD..."

    # Create namespace and apply configuration
    kubectl apply -f kubernetes/bootstrap/argocd/install.yaml

    # Install ArgoCD
    kubectl apply -n argocd \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    # Wait for ArgoCD to be ready
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

    log_success "ArgoCD installed!"

    # Get initial password
    log_info "Getting ArgoCD initial admin password..."
    local password
    password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" | base64 -d)

    echo
    log_info "ArgoCD Access Information:"
    echo "  Username: admin"
    echo "  Password: $password"
    echo
    log_info "To access ArgoCD UI:"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  Then open: https://localhost:8080"
}

# Deploy root application
deploy_root_app() {
    log_info "Deploying root application (App of Apps)..."

    kubectl apply -f kubernetes/bootstrap/argocd/app-of-apps.yaml

    log_success "Root application deployed!"
    log_info "ArgoCD will now sync all applications automatically."
}

# Main deployment function
deploy_platform() {
    local env=${1:-prod}

    log_info "Starting K8s Platform Bootstrap deployment..."
    log_info "Environment: $env"

    # Check prerequisites
    check_prerequisites
    check_aws_credentials

    # Initialize Terraform
    init_terraform "$env"

    # Plan and apply
    plan_terraform "$env"
    apply_terraform "$env"

    # Get cluster information from Terraform outputs
    cd "terraform/environments/$env"
    local cluster_name
    local region
    cluster_name=$(terraform output -raw cluster_name)
    region=$(terraform output -raw region 2>/dev/null || echo "us-west-2")
    cd ../../..

    # Configure kubectl
    configure_kubectl "$env" "$cluster_name" "$region"

    # Install ArgoCD
    install_argocd

    # Deploy root application
    deploy_root_app

    log_success "K8s Platform Bootstrap deployment completed successfully!"
    echo
    log_info "Next steps:"
    echo "  1. Update ArgoCD configuration with your repository URL"
    echo "  2. Configure repository credentials in ArgoCD"
    echo "  3. Update domain names and email addresses in manifests"
    echo "  4. Monitor ArgoCD for application sync status"
}

# Show help
show_help() {
    cat << EOF
K8s Platform Bootstrap - Setup Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    deploy [env]       Deploy entire platform (default: prod)
    init [env]         Initialize Terraform (default: prod)
    plan [env]         Plan Terraform changes (default: prod)
    apply [env]        Apply Terraform changes (default: prod)
    configure-kubectl  Configure kubectl to connect to cluster
    install-argocd     Install ArgoCD on cluster
    deploy-apps        Deploy root application to ArgoCD
    check              Check prerequisites and AWS credentials
    help               Show this help message

Environment Variables:
    AWS_ACCESS_KEY_ID          AWS access key
    AWS_SECRET_ACCESS_KEY      AWS secret key
    AWS_REGION                 AWS region (default: us-west-2)

Examples:
    $0 deploy prod
    $0 init prod
    $0 plan staging
    $0 configure-kubectl

EOF
}

# Main script
main() {
    local command=${1:-help}
    local env=${2:-prod}

    case "$command" in
        deploy)
            deploy_platform "$env"
            ;;
        init)
            check_prerequisites
            check_aws_credentials
            init_terraform "$env"
            ;;
        plan)
            check_prerequisites
            check_aws_credentials
            init_terraform "$env"
            plan_terraform "$env"
            ;;
        apply)
            check_prerequisites
            check_aws_credentials
            init_terraform "$env"
            apply_terraform "$env"
            ;;
        configure-kubectl)
            local cluster_name=${3:-"prod-cluster"}
            local region=${4:-"us-west-2"}
            configure_kubectl "$env" "$cluster_name" "$region"
            ;;
        install-argocd)
            install_argocd
            ;;
        deploy-apps)
            deploy_root_app
            ;;
        check)
            check_prerequisites
            check_aws_credentials
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
