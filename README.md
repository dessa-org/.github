# .github

Org-level defaults for [dessa-org](https://github.com/dessa-org) repositories.

## What's here

- `profile/README.md` — public profile page for the org (rendered at github.com/dessa-org)
- `.github/PULL_REQUEST_TEMPLATE.md` — default PR template inherited by repos that don't define their own

## Planned (not yet added)

- `.github/ISSUE_TEMPLATE/*` — default issue templates
- `.github/workflows/*.yml` — reusable GitHub Actions workflows callable from per-repo CI

Before adding reusable workflows, audit existing per-repo `.github/workflows/` to ensure the shared one matches what each repo actually uses (pnpm version, Node version, Go version, .NET SDK version).

## How reusable workflows work

Once added, other repos in the org call them like:

```yaml
jobs:
  build:
    uses: dessa-org/.github/.github/workflows/pnpm-build.yml@main
```

One place to update language versions, lint rules, secret scans — and every repo picks up the change.
