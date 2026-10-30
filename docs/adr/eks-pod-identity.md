# EKS Pod Identity and access entries for IAM

**Status:** accepted

## Context
Two IAM questions on EKS: how pods get AWS permissions (here: the EBS CSI driver, which creates
and attaches volumes), and how IAM principals (people, CI) get Kubernetes permissions.

## Decision
- **Pods → AWS: EKS Pod Identity.** The `eks-pod-identity-agent` add-on runs on every node; the
  EBS CSI add-on gets a role through a `pod_identity_association` bound to one service account
  (`kube-system/ebs-csi-controller-sa`) in this cluster. The role trusts the service
  `pods.eks.amazonaws.com`, so no per-cluster OIDC provider is needed.
- **Nodes keep only what nodes need**: worker policy, the CNI policy (the CNI must run before
  anything else on a node, so it does not wait for Pod Identity), and ECR pull-only.
- **IMDSv2 with hop limit 1** on every node: pods cannot reach the node's instance credentials.
- **IAM → Kubernetes: access entries** (`authentication_mode = "API"`), not the `aws-auth`
  ConfigMap. The creator is admin; more admins are a variable; the CI role gets the AWS-managed
  view policy on the `shortener` namespace only.

## Alternatives
- **IRSA** (IAM roles for service accounts): works everywhere, but needs an OIDC provider per
  cluster and trust policies that name the cluster's issuer URL; moving a role to a new cluster
  means editing that policy.
- **Permissions on the node role**: every pod on the node would get them.
- **aws-auth ConfigMap**: a hand-edited ConfigMap that can lock everyone out; access entries are
  AWS API objects managed by Terraform.

## Consequences
- Roles are reusable across clusters; the binding lives in the association, not the trust policy.
- Pod Identity needs the agent DaemonSet, and not every AWS SDK or tool supported it from the
  start; older add-ons may still need IRSA.
