terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 6.0" }
    helm = { source = "hashicorp/helm", version = "~> 2.17" }
  }

  # State in S3, locked with DynamoDB (Terraform 1.5 has no S3-native locking). The
  # values live in backend.hcl (copy backend.hcl.example):
  #   terraform init -backend-config=backend.hcl
  # Offline checks skip the backend: terraform init -backend=false
  backend "s3" {}
}

provider "aws" {
  region = var.region
}

# Talks to the new cluster with a short-lived token from the AWS CLI, as the identity
# that runs Terraform (it is cluster admin through the creator's access entry).
provider "helm" {
  kubernetes {
    host                   = module.eks.endpoint
    cluster_ca_certificate = base64decode(module.eks.certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
