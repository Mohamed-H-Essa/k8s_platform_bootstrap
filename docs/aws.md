# The AWS environment

`infra/terraform/envs/aws` runs the same platform on EKS. It is written and checked offline
(`make aws-check`) but **has never been applied**: there is no AWS account behind this project.
It exists to show that the laptop design carries over to a cloud, and what changes when it does.

## What it creates

| Area | What | Where |
|---|---|---|
| Network | VPC (`10.0.0.0/16`) over 3 AZs: a public /24 and a private /19 in each. Nodes and pods live in the private subnets. **One NAT gateway** for the VPC (cost; `single_nat_gateway = false` gives one per AZ). S3 gateway endpoint. The default security group has no rules. | `modules/vpc` |
| Cluster | EKS **1.35**, standard support only. API: private endpoint plus a public one limited to `api_allowed_cidrs` (0.0.0.0/0 is rejected). Kubernetes Secrets encrypted with a KMS key (rotation on). Control plane logs `api`, `audit`, `authenticator`, kept 7 days. Access through **access entries** (no `aws-auth` ConfigMap). | `modules/eks/main.tf` |
| Nodes | Managed node groups on AL2023: `system` (on-demand, 1 node) and `apps` (**spot**, 2 nodes, five interchangeable 2 vCPU / 8 GiB instance types). Launch templates: IMDSv2 only with hop limit 1, encrypted gp3 root disk. The shortener lands on `apps` through the label `slipway.dev/pool=apps`, the same label the kind workers carry. | `modules/eks/nodes.tf` |
| Night schedule | `aws_autoscaling_schedule` on the `apps` group's Auto Scaling group: to zero every evening at 20:00, back on weekday mornings at 07:00 (UTC by default), so weekends stay off. | `modules/eks/nodes.tf` |
| Add-ons | EKS-managed: VPC CNI, kube-proxy, CoreDNS, Pod Identity agent, **EBS CSI driver** with its IAM role through **Pod Identity**, and a default StorageClass for the Postgres volumes. EBS encryption by default is on for the region. | `modules/eks/addons.tf`, `main.tf` |
| CI identity | GitHub OIDC provider and a role only `main` of this repository can assume. It may describe this one cluster and read (view) the `shortener` namespace, nothing else. No access keys anywhere. | `modules/github-oidc`, `ci.tf` |
| Cost guard | AWS Budgets: monthly limit you choose, e-mail at 80 % actual and 100 % forecast. | `budget.tf` |
| GitOps | Argo CD by Helm with the same `platform/values/argocd.yaml`, and the same root app (`platform/apps`) with `repoURL` = GitHub, `revision` = `main`, `env` = `aws`. | `argocd.tf` |
| State | S3 backend with a DynamoDB lock table (Terraform 1.5 has no S3-native locking). | `versions.tf`, `backend.hcl.example` |

Why own modules and not `terraform-aws-modules`, Pod Identity, and the cost choices: see
[adr/aws-modules.md](adr/aws-modules.md), [adr/eks-pod-identity.md](adr/eks-pod-identity.md),
[adr/aws-cost-controls.md](adr/aws-cost-controls.md). CI and keyless signing:
[adr/ci-keyless-signing.md](adr/ci-keyless-signing.md).

## Local and AWS, side by side

| | Local (`envs/local`) | AWS (`envs/aws`) |
|---|---|---|
| Cluster | kind, 1 control plane + 2 workers in Docker | EKS, managed control plane, 1 on-demand + 2 spot nodes |
| Git that Argo CD reads | soft-serve next to the cluster | GitHub |
| Shortener image | `slipway-registry:5000`, signed with a local key | `ghcr.io/mohamed-h-essa/shortener`, signed keyless by CI |
| Volumes | kind's local-path provisioner | EBS gp3 through the EBS CSI driver |
| Way out to the internet | the laptop, through pull-through caches | one NAT gateway (S3 through a free gateway endpoint) |
| Values | `platform/values/*.yaml` + `platform/values/local/` | `platform/values/*.yaml` + `platform/values/aws/` (none needed yet) |

## How it would be applied

You need an AWS account, the AWS CLI logged in as an admin, and Terraform 1.5.

1. **State bucket and lock table** (once per account; names are examples):
   ```sh
   ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
   BUCKET=slipway-tfstate-$ACCOUNT REGION=eu-central-1
   aws s3api create-bucket --bucket $BUCKET --region $REGION \
     --create-bucket-configuration LocationConstraint=$REGION
   aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled
   aws s3api put-public-access-block --bucket $BUCKET --public-access-block-configuration \
     BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
   aws s3api put-bucket-encryption --bucket $BUCKET --server-side-encryption-configuration \
     '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
   aws dynamodb create-table --table-name slipway-tflock --region $REGION \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
   ```
2. **Settings**: in `infra/terraform/envs/aws`, copy `backend.hcl.example` → `backend.hcl` and
   `terraform.tfvars.example` → `terraform.tfvars`; fill in the bucket, your IP (`/32`), the
   budget e-mail and limit.
3. **Apply**:
   ```sh
   cd infra/terraform/envs/aws
   terraform init -backend-config=backend.hcl
   terraform plan -out=tfplan && terraform apply tfplan
   ```
   The Helm provider is configured from the cluster's outputs, so one apply should create
   everything. If a first plan fails because the cluster cannot be reached yet, apply
   `-target=module.eks` first, then the rest.
4. **Use it**: `$(terraform output -raw kubeconfig_command)`, then watch Argo CD sync the
   platform from GitHub (`kubectl -n argocd get applications`).
5. **CI**: set the repository variable `AWS_ROLE_ARN` to `terraform output -raw
   github_actions_role_arn`; the `aws` job in `ci.yml` then checks the shortener's rollout on
   every push to `main`.
6. **Tear down**: `terraform destroy`. The state bucket and lock table stay (delete them by hand).

## What drives the cost

No prices here: they depend on the region and change over time. Estimate with
[Infracost](https://www.infracost.io/) (`infracost breakdown --path infra/terraform/envs/aws`,
free API key needed) or the AWS Pricing Calculator. Neither has been run for this repo.

The drivers, largest first in a setup this small:

- **EKS control plane**: billed per cluster-hour, 24/7, whether nodes run or not. A version in
  extended support is billed at a higher rate; `upgrade_policy = STANDARD` refuses that and
  forces upgrades instead.
- **NAT gateway**: billed per hour, 24/7, plus per GB processed. One instead of three is the
  biggest single saving here; the S3 gateway endpoint (no charge) keeps S3 traffic off it. The
  NAT's Elastic IP is also billed as a public IPv4 address.
- **Nodes**: one on-demand `t3.large` always on; two spot `*.large` nodes on weekdays only
  (night schedule). Spot is cheaper than on-demand but can be reclaimed; managed node groups
  drain spot nodes when AWS signals a rebalance. Each node has a 30 GiB gp3 root disk.
- **Smaller items**: EBS volumes for Postgres (2 × 1 GiB), the gateway's load balancer once it
  exists, CloudWatch log ingestion and storage (3 log types, 7 days), the KMS key (monthly fee
  plus requests), data transfer out.

Turning the night schedule off, adding NAT gateways per AZ, or more control plane log types all
raise the bill; the budget alert is the backstop, it does not stop anything.

## Checks (`make aws-check`)

| Check | Result on 2026-10-30 |
|---|---|
| `terraform init -backend=false && terraform validate` (Terraform 1.5.7, AWS provider 6.x, Helm provider 2.17) | valid |
| `tflint --recursive` in Docker (`ghcr.io/terraform-linters/tflint:v0.65.0`): Terraform rules (recommended) + AWS ruleset 0.50.0 | 0 issues |
| `trivy config --severity HIGH,CRITICAL infra/terraform` (Trivy 0.70) | 0 findings |

Accepted with an inline `#trivy:ignore` and a reason:
- **AWS-0040** (CRITICAL, public API endpoint): a lab has no VPN or bastion, so the endpoint stays
  public but only for `api_allowed_cidrs`, and a validation rejects `0.0.0.0/0`.

Below the gate (MEDIUM/LOW), left on purpose, all for cost:
- **AWS-0038**: `controllerManager` and `scheduler` logs are off (`api`, `audit`,
  `authenticator` are on).
- **AWS-0178**: no VPC flow logs. Production would send them to S3.
- **AWS-0017**: the control plane log group uses CloudWatch's default encryption, not a KMS key.

## Not done (what a real deployment still needs)

- **DNS and TLS**: no Route 53 records, certificates or cert-manager; `var.domain` is
  `example.com`.
- **Logs and traces storage**: Loki and Tempo keep data on volumes; on AWS they would use S3
  buckets with Pod Identity roles.
- **Autoscaling**: no Cluster Autoscaler or Karpenter; node counts are fixed per group, apart
  from the schedule.
- **Release tag**: CI tags images `sha-<commit>` and `main`; the `aws` overlay still pins
  `0.1.0`. Nothing bumps it automatically.

Done since (in `platform/`): the gateway is per environment (`platform/gateway/aws`: two Envoy
replicas across zones behind an NLB, PDB), and the signature gate on AWS verifies the keyless
signature and SBOM attestation from `ci.yml` on `main` (`platform/policies/aws`, issuer
`https://token.actions.githubusercontent.com`, Rekor).
