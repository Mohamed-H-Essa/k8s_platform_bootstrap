# A Git server next to the cluster (soft-serve)

**Status:** accepted

## Context
GitOps needs a Git remote that Argo CD pulls from. Locally we want it to work offline, without
tokens, and without pushing every experiment (including chaos day's deliberately bad release)
to the public GitHub repository. Rolling back with `git revert` has to work exactly as it would
against GitHub.

## Decision
- Run **soft-serve** (a single small Go binary) as a container on the `kind` Docker network:
  `slipway-git`.
- `make publish` pushes the current `HEAD` over SSH (`localhost:23231`, key `.local/git_ed25519`,
  registered as the admin key when the container starts). The repository is created on the first
  push.
- Argo CD reads `http://slipway-git:23232/platform.git` anonymously; that address only exists on
  the laptop's Docker network.
- On AWS the same app-of-apps chart points `repoURL` at GitHub instead. Nothing else changes.

## Alternatives
- **Argo CD reads GitHub directly**: needs network and every local change becomes a public commit.
- **Gitea**: a full forge with a database and a web UI we would not use.
- **`git daemon` or a bare repo over HTTP**: no authentication for pushes, no repo management.
- **Mounting the working tree into Argo CD**: not GitOps: no commits, no history, no revert.

## Consequences
- The laptop's Git history is the source of truth; `make publish` force-pushes it.
- Releases and rollbacks are ordinary commits (`make release`, `git revert`), so the audit trail
  is `git log`.
- Argo CD checks Git every 60 s; `make publish` also asks for a hard refresh, so changes start
  syncing within seconds.
