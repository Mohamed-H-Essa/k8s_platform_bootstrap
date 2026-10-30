# Signed images and SBOMs, enforced by Kyverno

**Status:** accepted

## Context
Anything that can push to the registry can, by default, run in the cluster. We want only images
that went through the release pipeline (built from this repo, scanned, with a known bill of
materials) to be admitted, and we want what runs to be byte-for-byte what was signed.

## Decision
- **Release pipeline** (`scripts/release-image.sh`, `make image` / `make release`): build →
  **Trivy** (fail on fixable HIGH/CRITICAL) → push → **Syft** SPDX SBOM → **cosign** signature and
  an SBOM attestation (`cosign attest --type spdxjson`).
- Locally the key pair lives in `.local/` (gitignored) and nothing goes to a transparency log.
  cosign v2 runs in a container on the `kind` network so it signs the image under the name the
  cluster pulls it by (`slipway-registry:5000/shortener`).
- **Admission:** in application namespaces (label `slipway.dev/policy=restricted`), the Kyverno
  ClusterPolicy `verify-platform-images` requires, for every image from `slipway-registry:5000/*`,
  a valid signature **and** an SPDX attestation signed by the release key, and rewrites the tag to
  the verified digest.
- A second policy, `restricted-workloads`, enforces a baseline in namespaces labelled
  `slipway.dev/policy=restricted`: a pinned version, no `:latest`, CPU and memory requests and a
  memory limit, non-root, no privilege escalation.
- `make unsigned` proves the gate: it pushes an unsigned image and shows Kyverno refusing it.

## Alternatives
- **Sigstore policy-controller**: verifies signatures only; we would still need a second engine
  for the baseline rules.
- **OPA Gatekeeper**: policies in Rego; image verification needs an external data provider.
- **ValidatingAdmissionPolicy (CEL)**: built in and fast, but cannot make network calls, so it
  cannot verify signatures.
- **Pod Security Admission**: covers non-root and privilege escalation, not pinned versions,
  resources or signatures.

## Consequences
- Kyverno sits in the pod-creation path and fails closed: if it is down, matching pods are not
  admitted. That is the intended trade-off for a supply-chain gate, so its webhooks only see the
  application namespaces. Learned the hard way: with cluster-wide webhooks, a Kyverno outage on the
  overloaded laptop blocked Argo CD's own upgrade and even `kubectl patch` in `argocd`.
- Platform namespaces run upstream images (Argo CD, Prometheus…) that this policy does not verify.
  Production would add a policy that pins them by digest or verifies the vendors' signatures.
- cosign v3 changed its default bundle format; the local pipeline pins cosign v2 for Kyverno
  compatibility.
- In CI on GitHub the same steps sign keyless (OIDC identity of the workflow, recorded in Rekor),
  so no long-lived key exists there. A cluster running those images would verify the workflow
  identity instead of a public key.
