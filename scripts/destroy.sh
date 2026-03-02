#!/bin/bash

# K8s Platform Bootstrap - Destroy Script
# This script tears down the entire platform

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

destroy_platform() {
    local env=${1:-prod}

    log_warning "This will destroy all resources for environment: $env"
    log_warning "This action cannot be undone!"

    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    echo

    if [[ $REPLY != "yes" ]]; then
        log_info "Destruction cancelled."
        exit 0
    fi

    log_info "Starting destruction of environment: $env"

    cd "terraform/environments/$env"

    # Get cluster info before destruction
    local cluster_name
    cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "unknown")

    # Destroy Terraform resources
    log_info "Destroying Terraform resources..."
    terraform destroy -auto-approve

    cd ../../..

    log_info "Destruction completed for environment: $env"
    log_info "Cluster '$cluster_name' has been destroyed."
}

# Main
if [ "${1:-}" = "destroy" ]; then
    destroy_platform "${2:-prod}"
else
    echo "Usage: $0 destroy [environment]"
    echo "Example: $0 destroy prod"
fi
