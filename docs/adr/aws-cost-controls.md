# Cost controls for the AWS environment

**Status:** accepted

## Context
A personal lab on EKS pays for things that run 24/7 whether anyone uses them or not: the control
plane, NAT gateways, nodes. The platform itself is small (it fits in an 8 GB Docker VM locally).
No prices are quoted in this repo; [aws.md](../aws.md) lists the cost drivers and how to estimate
them with Infracost.

## Decision
- **One NAT gateway** for the VPC, not one per AZ (`single_nat_gateway`, default `true`), and an
  S3 gateway endpoint so S3 traffic does not go through it.
- **Two node groups**: a small on-demand `system` group (Argo CD, operators, observability stay
  up) and a **spot** `apps` group with five interchangeable instance types, so one type running
  out of spot capacity does not empty the group.
- **Night scale-down**: `aws_autoscaling_schedule` actions on the `apps` group's Auto Scaling
  group take it to zero every evening and back on weekday mornings. Terraform ignores
  `desired_size` drift so it does not fight the schedule.
- **Standard support only** (`upgrade_policy`): a cluster version in extended support costs more
  per hour, so the cluster must be upgraded instead.
- **AWS Budgets**: e-mail at 80 % of a monthly limit (actual) and 100 % (forecast).
- Control plane logs: three types, 7-day retention; no VPC flow logs.

## Alternatives
- **NAT per AZ**: survives the loss of the NAT's AZ; several times the NAT cost. A variable away.
- **Karpenter** (spot, consolidation, scale to zero by demand): better for real workloads; more
  moving parts than a lab needs, and it still needs somewhere to run.
- **Fargate**: no nodes to manage, but no DaemonSets (log/trace agents) and per-pod pricing.
- **Destroying the environment every evening**: cheapest, but a cold start every morning.

## Consequences
- At night the shortener is Pending (its pods need `apps` nodes); the control plane, the NAT
  gateway and the system node still bill.
- One AZ outage can cut outbound internet for the other two (single NAT).
- Spot nodes can be reclaimed with two minutes' notice; the shortener runs at least two
  replicas with a PodDisruptionBudget and spreads across nodes, as it does locally.
- The budget only alerts; acting on it is manual.
