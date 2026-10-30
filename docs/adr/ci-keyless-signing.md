# CI with GitHub OIDC: keyless signing and no cloud keys

**Status:** accepted

## Context
CI builds the image others will run, so it needs to prove where an image came from, and it may
need to reach AWS. Long-lived secrets in CI (a cosign private key, AWS access keys) are the usual
way, and the usual leak.

## Decision
- **One identity: the workflow's OIDC token.** GitHub issues a short-lived token per run,
  naming the repository, workflow and ref. Jobs that need it ask for `id-token: write`; nothing
  else does (`permissions: {}` at the top of every workflow).
- **Keyless cosign** in `ci.yml` on `main`: the token is exchanged for a short-lived Fulcio
  certificate; the signature and the SPDX SBOM attestation are recorded in the public Rekor log.
  The job then verifies both against the identity
  `https://github.com/<repo>/.github/workflows/ci.yml@refs/heads/main`, which is what an admission
  policy on a real cluster would check. cosign is pinned to v2, the format the local Kyverno
  policy already verifies.
- **The scanned image is the shipped image**: the `image` job builds, scans (Trivy, fails on
  fixable HIGH/CRITICAL) and saves the image; `publish` loads and pushes that same image after
  every check passed. No rebuild between scan and push.
- **AWS through OIDC**: the role in `envs/aws` trusts GitHub's OIDC provider for exactly
  `repo:Mohamed-H-Essa/k8s_platform_bootstrap:ref:refs/heads/main`, may describe one cluster and
  view one namespace. The `aws` job runs only when the repository variable `AWS_ROLE_ARN` is set.
- **e2e on a GitHub runner**: `e2e.yml` runs the laptop path (`make up`, `make smoke`,
  `make unsigned`) on a standard Linux runner, by hand and weekly.

## Alternatives
- **A cosign key pair in GitHub secrets**: works offline and without a public log, but the key can
  leak and must be rotated; verification needs the public key distributed. Kept for the local
  path only, where there is no OIDC issuer.
- **AWS access keys in secrets**: long-lived, broad by habit, rotated by hand.
- **Rebuild on push** (one job does everything with `push: true`): simpler, but what is pushed is
  not byte-for-byte what was scanned, and the job holding `packages: write` also runs untrusted
  build steps on pull requests.

## Consequences
- Nothing secret to store or rotate for CI; a fork's pull request can build and scan but gets no
  token to publish or sign.
- Signatures for a public repo go to the public Rekor log (repository name and workflow are
  visible there, which is fine for a public project).
- Keyless verification depends on Sigstore's public infrastructure being reachable.
- The workflows pass `actionlint`, but have not run on GitHub yet: the repository has not been
  pushed. `e2e.yml` in particular is untested on a runner.
