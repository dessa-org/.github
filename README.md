# .github

Org-level defaults for [dessa-org](https://github.com/dessa-org) repositories.

## What's here

- `profile/README.md` — public profile page for the org (rendered at github.com/dessa-org)
- `.github/PULL_REQUEST_TEMPLATE.md` — default PR template inherited by repos that don't define their own
- `.github/workflows/ci.yml` — **reusable portfolio CI** (build/lint/test). Auto-detects Node/.NET/Go in the caller's tree. Per [ADR 0004](https://github.com/dessa-org/dessa-logs/blob/main/decisions/0004-portfolio-devops-standard.md).
- `.github/workflow-templates/ci.yml` — the ~10-line caller shown in each repo's "Actions → New workflow" picker.

## Standard CI

Every repo gets the same CI by dropping in one file (`.github/workflows/ci.yml`):

```yaml
jobs:
  ci:
    uses: dessa-org/.github/.github/workflows/ci.yml@main
```

The reusable workflow then auto-detects and runs, with no per-repo config:
- **Node** — every dir with a `package.json` (excl. `node_modules`): install + `lint`/`build`/`test` (run `--if-present`). npm or pnpm by lockfile.
- **.NET** — every `*.sln`: restore + build + test (Release).
- **Go** — every `go.mod`: build + vet + test.

Make it a **required status check** on `staging`/`main` (FULL) or `main` (LITE). CD is separate — the deployer's webhook handles deploys; this is the quality gate only.

## Planned (not yet added)

- `.github/ISSUE_TEMPLATE/*` — default issue templates
- CI v2: per-workspace change detection (skip unchanged), dependency caching, pinned pnpm/Go versions per the audit below.

> **Version audit:** the reusable workflow defaults to Node 20 / .NET 9.0.x / Go 1.23. Before flipping a repo's required check on, confirm these match what the repo actually uses; override via `with:` in that repo's caller if not.

## How reusable workflows work

Once added, other repos in the org call them like:

```yaml
jobs:
  build:
    uses: dessa-org/.github/.github/workflows/pnpm-build.yml@main
```

One place to update language versions, lint rules, secret scans — and every repo picks up the change.
