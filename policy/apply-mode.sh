#!/usr/bin/env bash
# apply-mode.sh — enforce a repo's delivery mode (ADR 0006) from policy/modes.yaml.
#
# Resolves each repo's effective policy (mode + modifiers) and makes GitHub match:
#   - branch protection on the mode's protected branches (required CI check + reviews)
#   - GitHub environments for the mode's tiers
#   - reports whether the repo has the CI caller workflow
#
# Idempotent — safe to re-run; it converges state, it doesn't append.
#
# Usage:
#   policy/apply-mode.sh --repo letzcharter [--dry-run]
#   policy/apply-mode.sh --all              [--dry-run]
#   policy/apply-mode.sh --repo dessa-vault --show     # print resolved policy only
#
# Requires: gh (authed, admin on target repos — repo admin or org owner),
#           jq, python3 with PyYAML.
set -euo pipefail

ORG=dessa-org
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODES="$HERE/modes.yaml"
DRY=0; ONLY=""; ALL=0; SHOW=0
while [ $# -gt 0 ]; do case "$1" in
  --repo) ONLY="${2:?}"; shift 2;;
  --all) ALL=1; shift;;
  --dry-run) DRY=1; shift;;
  --show) SHOW=1; shift;;
  -h|--help) sed -n '2,18p' "$0"; exit 0;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done

command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }
python3 -c 'import yaml' 2>/dev/null || { echo "python3 + PyYAML required (pip install pyyaml)" >&2; exit 1; }

# Resolve mode + modifiers into one flat policy object per repo (JSON).
resolve() {
python3 - "$MODES" <<'PY'
import sys, yaml, json
cfg = yaml.safe_load(open(sys.argv[1]))
modes, mods = cfg["modes"], cfg.get("modifiers", {})
out = {}
for repo, spec in cfg["repos"].items():
    p = dict(modes[spec["mode"]])
    p["mode"] = spec["mode"]
    p["modifiers"] = spec.get("modifiers", [])
    prot = list(p["protected_branches"])
    for m in spec.get("modifiers", []):
        md = mods[m]
        for b in md.get("protected_branches_add", []):
            if b not in prot:
                prot.append(b)
        for k in ("required_reviews", "release"):
            if k in md:
                p[k] = md[k]
        if md.get("tag_to_deploy"):
            p["tag_to_deploy"] = True
    p["protected_branches"] = prot
    out[repo] = p
print(json.dumps(out))
PY
}

run() { if [ "$DRY" = 1 ]; then echo "  DRY » $*"; else "$@"; fi; }

apply_repo() {
  local repo="$1" pol="$2"
  local rp; rp=$(echo "$pol" | jq -c ".\"$repo\"")
  [ "$rp" = "null" ] && { echo "== $repo == (not in modes.yaml — skipping)"; return; }
  local mode reviews; mode=$(jq -r .mode <<<"$rp"); reviews=$(jq -r .required_reviews <<<"$rp")
  echo "== $repo == mode=$mode$( [ "$(jq -r '.modifiers|length' <<<"$rp")" != 0 ] && echo " +$(jq -r '.modifiers|join(",")' <<<"$rp")" )"
  if [ "$SHOW" = 1 ]; then echo "$rp" | jq .; return; fi

  local contexts; contexts=$(jq -c '.required_checks' <<<"$rp")

  # Branch protection (only on branches that exist)
  for b in $(jq -r '.protected_branches[]' <<<"$rp"); do
    if ! gh api "repos/$ORG/$repo/branches/$b" >/dev/null 2>&1; then
      echo "  branch '$b': MISSING — create it before protection can apply"; continue
    fi
    local body
    body=$(jq -nc --argjson ctx "$contexts" --argjson rev "$reviews" '{
      required_status_checks: { strict: true, contexts: $ctx },
      enforce_admins: false,
      required_pull_request_reviews: { required_approving_review_count: $rev },
      restrictions: null
    }')
    echo "  protect '$b': checks=$contexts reviews=$reviews"
    run gh api -X PUT "repos/$ORG/$repo/branches/$b/protection" \
      -H "Accept: application/vnd.github+json" --input - <<<"$body" >/dev/null
  done

  # GitHub environments
  for e in $(jq -r '.environments[]?' <<<"$rp"); do
    echo "  environment '$e'"
    run gh api -X PUT "repos/$ORG/$repo/environments/$e" -H "Accept: application/vnd.github+json" >/dev/null
  done

  # CI caller presence (adding it is a commit — handled separately, not here)
  if gh api "repos/$ORG/$repo/contents/.github/workflows/ci.yml" >/dev/null 2>&1; then
    echo "  ci.yml caller: present"
  else
    echo "  ci.yml caller: MISSING — add from .github/workflow-templates/ci.yml"
  fi
}

POL="$(resolve)"
if [ -n "$ONLY" ]; then
  apply_repo "$ONLY" "$POL"
elif [ "$ALL" = 1 ]; then
  for r in $(echo "$POL" | jq -r 'keys[]'); do apply_repo "$r" "$POL"; done
else
  echo "specify --repo NAME or --all (see --help)" >&2; exit 2
fi
echo "done$( [ "$DRY" = 1 ] && echo ' (dry-run — no changes made)' )"
