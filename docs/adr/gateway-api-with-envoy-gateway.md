# Gateway API with Envoy Gateway

**Status:** accepted

## Context
The cluster needs one HTTP entry point for the workload and the platform UIs. The usual default,
the community ingress-nginx controller, was retired by Kubernetes SIG Network (announced November
2025, maintenance ended March 2026). The Ingress API itself is frozen; new work goes into the
Gateway API.

## Decision
- Use the **Gateway API** (`GatewayClass`, `Gateway`, `HTTPRoute`, all GA) with **Envoy Gateway**
  as the implementation.
- The platform owns one shared `Gateway` named `platform` (namespace `envoy-gateway-system`).
  Each team attaches an `HTTPRoute` from its own namespace: the shortener's route lives with the
  shortener, Grafana's and Argo CD's with the platform.
- The Envoy data plane is configured per environment (`platform/gateway/<env>/envoyproxy.yaml`).
  **Locally** it is a DaemonSet on every node, including the control plane, behind NodePort 30080
  with `externalTrafficPolicy: Local`: kind maps `127.0.0.1:80` to the control-plane node, and that
  node's own Envoy answers. (With a two-replica Deployment on the workers, requests from the host to
  the control-plane NodePort timed out while kube-proxy forwarded them across nodes; the same
  NodePort on a worker worked. Keeping ingress traffic on the node it arrives at sidesteps that and
  keeps the client's IP.) Hosts are `*.localtest.me`, public DNS that resolves to `127.0.0.1`.
- **On AWS** Envoy is a two-replica Deployment spread over zones, with a PodDisruptionBudget,
  behind a Network Load Balancer.

## Alternatives
- **ingress-nginx**: retired, see above.
- **Traefik**: good Gateway API support; Envoy Gateway was chosen for Envoy's data plane and its
  policy CRDs (retries, timeouts, health checks, rate limits) that map to the Gateway model.
- **Cilium Gateway**: would mean replacing kind's CNI with Cilium: more memory and moving parts
  on an 8 GB laptop.
- **Istio**: a service mesh; far more than one entry point needs.

## Consequences
- The split of roles (platform owns the Gateway, teams own routes) is built into the API instead of
  being a convention.
- The same manifests work on AWS, where the Gateway's Service becomes a load balancer.
- `allowedRoutes: from: All` is fine on a one-team laptop; a shared production cluster would
  restrict it with a namespace label selector.
