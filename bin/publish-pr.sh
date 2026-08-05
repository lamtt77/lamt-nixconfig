#!/usr/bin/env bash
set -euo pipefail

# Open a pull request that syncs this repository to its public GitHub mirror.
#
# This is deliberately manual: run it when a snapshot is worth publishing,
# review what it staged, then merge the PR on GitHub.
#
# The published tree excludes internal material, which carries private-site
# topology and local scratch state. Each sync is squashed to one commit, so
# excluded content is never recoverable from an earlier revision on the mirror.

usage() {
  cat >&2 <<'USAGE'
usage: bin/publish-pr.sh [--push] [--remote URL] [--base BRANCH]

  (default)      Stage the filtered snapshot, print a summary, exit. No push.
  --push         Create the sync branch, push it, and open the pull request.
  --remote URL   Override the mirror (default: git@github.com:lamtt77/lamt-nixconfig.git)
  --base BRANCH  Base branch on the mirror (default: main)

The default run touches no branch and contacts no remote beyond a fetch.
Inspect what it reports, then re-run with --push.
USAGE
}

remote_url="git@github.com:lamtt77/lamt-nixconfig.git"
base_branch="main"
do_push=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) do_push=1; shift ;;
    --remote) remote_url=${2:?--remote needs a URL}; shift 2 ;;
    --base) base_branch=${2:?--base needs a branch}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# Paths that must never reach the public mirror. This is the explicit denial
# that documents *why*; .gitignore already keeps most of them untracked.
EXCLUDE_REASONS=(
  "docs/fcmbuilder.md   private-site cache runbook: internal addressing and topology"
  "_tmp                 local scratch"
  ".nxd                 regenerated plans and local run state"
  ".log                 local run logs"
  "lamt-secrets         encrypted secret store, never mirrored"
)

source_branch=$(git rev-parse --abbrev-ref HEAD)

if [[ -n "$(git status --porcelain)" ]]; then
  echo "refusing to publish from a dirty tree; commit or stash first" >&2
  git status --short >&2
  exit 1
fi

echo "==> fetching mirror"
git remote get-url github >/dev/null 2>&1 || git remote add github "$remote_url"
git fetch --quiet github

# Fail closed: nothing denied may be tracked, whatever .gitignore claims.
echo "==> verifying exclusions"
violations=0
for entry in "${EXCLUDE_REASONS[@]}"; do
  path=${entry%% *}
  if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    echo "    LEAK: $path is tracked and would be published" >&2
    violations=$((violations + 1))
  fi
done
if [[ $violations -gt 0 ]]; then
  echo "refusing to publish: ${violations} excluded path(s) tracked" >&2
  echo "fix with: git rm --cached <path> && echo <path> >> .gitignore" >&2
  exit 1
fi
echo "    ok: no excluded path tracked"

# Secret-shaped content. Match key *bodies*, not headers: the tree legitimately
# contains header strings in comparisons and fixtures, and matching those would
# report the guard as the leak. SOPS-encrypted values are expected and fine --
# they are ciphertext -- so only unencrypted key material fails.
echo "==> scanning for unencrypted key material"
secret_hits=$(
  git ls-files -z | xargs -0 grep -IlE 'AGE-SECRET-KEY-1[0-9A-Z]{20,}|^[A-Za-z0-9+/]{60,}={0,2}$' 2>/dev/null |
    while IFS= read -r hit; do
      # A base64 body inside a CERTIFICATE block is public by definition.
      if grep -q 'BEGIN CERTIFICATE' "$hit" 2>/dev/null && ! grep -q 'PRIVATE KEY' "$hit" 2>/dev/null; then
        continue
      fi
      # SOPS documents are ciphertext by construction.
      if grep -q 'sops:' "$hit" 2>/dev/null; then
        continue
      fi
      echo "$hit"
    done || true
)
if [[ -n "$secret_hits" ]]; then
  echo "refusing to publish: possible key material in:" >&2
  echo "$secret_hits" | sed 's/^/  /' >&2
  exit 1
fi
echo "    ok: no unencrypted key material"

# Two-dot, not three: the mirror carries squashed snapshots with unrelated
# history, so there is no merge base and `...` aborts the run.
changed_files=$(git diff --name-only "github/${base_branch}" HEAD 2>/dev/null | wc -l | tr -d ' ')
commits=$(git log --oneline "github/${base_branch}..HEAD" 2>/dev/null | wc -l | tr -d ' ' || echo 0)

echo
echo "==> sync summary"
echo "    source branch : ${source_branch} ($(git rev-parse --short HEAD))"
echo "    mirror        : ${remote_url} (${base_branch})"
echo "    files changed : ${changed_files}"
echo "    local commits : ${commits}"
echo
echo "    excluded:"
for entry in "${EXCLUDE_REASONS[@]}"; do
  echo "      ${entry}"
done

if [[ $do_push -eq 0 ]]; then
  echo
  echo "==> dry run: nothing pushed, no branch created"
  echo "    re-run with --push to open the pull request"
  exit 0
fi

branch="sync-$(date +%Y%m%d-%H%M%S)"
echo
echo "==> creating ${branch}"
git checkout -q -b "$branch"

# Always return to the original branch, even on failure.
cleanup() {
  git checkout -q "$source_branch" 2>/dev/null || true
  git branch -D "$branch" 2>/dev/null || true
}
trap cleanup ERR INT TERM

# Squash to a single commit against the mirror. The mirror carries curated
# snapshots, not this repository's full history.
git reset --soft "github/${base_branch}"

if [[ -z "$(git status --porcelain)" ]]; then
  echo "==> mirror is already up to date"
  cleanup
  exit 0
fi

template=$(mktemp)
{
  echo "sync: update public configuration snapshot"
  echo
  echo "# Edit the subject above and the body below, then save and quit."
  echo "# Lines starting with # are removed."
  echo
  if [[ "$commits" != "0" ]]; then
    echo "Local commits in this sync:"
    # -n30 rather than `| head -30`: head closes the pipe early, git dies of
    # SIGPIPE, and `set -o pipefail` turns that into a failed run -- which
    # aborted the script before the editor ever opened.
    git log -n30 --format='- %s' "github/${base_branch}..ORIG_HEAD" 2>/dev/null || true
    echo
  fi
  echo "Files changed:"
  git diff --cached --stat -- . | tail -20 || true
} >"$template"

"${EDITOR:-${VISUAL:-nvim}}" "$template" || { cleanup; exit 1; }

message=$(grep -v '^#' "$template" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba')
rm -f "$template"

if [[ -z "$message" ]]; then
  echo "empty commit message; aborting" >&2
  cleanup
  exit 1
fi

git commit -q -F - <<<"$message"
git push -q github "$branch"

title=$(head -n1 <<<"$message")
body=$(tail -n +3 <<<"$message")
gh pr create --title "$title" --body "${body:-Configuration sync.}" \
  --head "$branch" --base "$base_branch"

trap - ERR INT TERM
git checkout -q "$source_branch"
echo "==> pull request opened; branch ${branch} left on the mirror until merged"
