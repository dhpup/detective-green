#!/usr/bin/env bash
# Points this repo at your fork (pattern from akuity/akp-platform). Rewrites:
#   - github.com/<owner>/detective-green repo URLs
#   - ghcr.io/<owner>/ image references
#   - the CODEOWNERS owner
# Run once from a fresh fork; reset with `git checkout -- .` to start over.
# Works with GNU sed (Linux) and BSD sed (macOS).
#
# Usage: hack/personalize.sh [github-owner]
set -euo pipefail
cd "$(dirname "$0")/.."

if sed --version >/dev/null 2>&1; then SEDI=(-i); else SEDI=(-i ''); fi

owner="${1:-}"
if [[ -z "$owner" ]]; then
  read -r -p "GitHub user/org that owns your fork: " owner
fi
[[ "$owner" =~ ^[-_a-zA-Z0-9]+$ ]] || { echo "invalid owner: '$owner'" >&2; exit 1; }
image_owner="$(echo "$owner" | tr '[:upper:]' '[:lower:]')"

files() {
  git ls-files -- '*.yaml' '*.yml' '*.md' '*.sh' 'Makefile' '.github/CODEOWNERS' \
    | grep -v -e '^hack/personalize.sh$'
}
files | xargs sed -E "${SEDI[@]}" \
  -e "s#github.com/[-_a-zA-Z0-9]+/detective-green#github.com/${owner}/detective-green#g" \
  -e "s#ghcr.io/[-_a-z0-9]+/(case-file|evidence-kit)#ghcr.io/${image_owner}/\\1#g"
sed -E "${SEDI[@]}" "s#^(/[^ ]+ +)@[-_a-zA-Z0-9]+\$#\\1@${owner}#" .github/CODEOWNERS

echo "Done. Review with 'git diff', then commit and push."
