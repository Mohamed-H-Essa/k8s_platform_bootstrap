# kind and Terraform for the local environment

**Status:** accepted

## Context
The platform has to run end to end on one laptop (Docker with 8 GB, no cloud account), come up
from one command, and be torn down and rebuilt often. It should still be infrastructure as code,
in the same tool the AWS environment uses, so the local and cloud setups read the same way.

## Decision
- **kind** runs Kubernetes in Docker: one control-plane node and two workers, so "lose a node"
  is a real experiment (`docker stop slipway-worker`).
- **Terraform** creates everything outside the cluster in `infra/terraform/envs/local`: the kind
  cluster (`tehcyx/kind`), a private registry, four pull-through caches (docker.io, quay.io,
  ghcr.io, registry.k8s.io) and the Git server (`kreuzwerker/docker`), then Argo CD and one root
  Application (`hashicorp/helm`).
- Terraform stops at Argo CD. Everything inside the cluster comes from Git (see
  [app of apps](app-of-apps-as-a-helm-chart.md)).
- containerd on every node reads `/etc/containerd/certs.d/<registry>/hosts.toml`, mounted from the
  repo, so each upstream registry is pulled through its cache and the local registry is plain HTTP.

## Alternatives
- **minikube**: one node by default, VM-oriented. Multi-node works but is less common.
- **k3d / k3s**: lighter, but a different distribution (embedded datastore, bundled Traefik).
  kind runs upstream kubeadm Kubernetes, the same thing EKS runs.
- **A shell script around the kind CLI**: shorter, but no plan, no state, no clean destroy, and
  nothing in common with how the AWS environment is built.

## Consequences
- `make down` keeps the caches and the registry (named volumes), so a rebuild only downloads what
  changed. The first run on a slow connection is dominated by image downloads.
- No cloud load balancer: Envoy listens on NodePort 30080, mapped to `127.0.0.1:80`.
- Storage is kind's local-path provisioner: a volume is tied to its node. Stateful pods cannot
  move when a node dies; the database survives by replication instead (see
  [CloudNativePG](cloudnativepg-for-postgres.md)).
- Terraform 1.5.7 (the last MPL-licensed release) is the floor, so the code avoids newer syntax.
