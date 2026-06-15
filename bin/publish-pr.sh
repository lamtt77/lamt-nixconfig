#!/bin/bash
# publish-pr.sh - Create PR with single commit squash (dynamic commit message, nvim/editor default)

set -e # Exit on any error

echo "🔄 Starting sync PR workflow..."

# Step 1: Setup
echo "📡 Setting up GitHub remote..."
git remote add github git@github.com:lamtt77/lamt-nixconfig.git 2>/dev/null || echo "Remote already exists"
git fetch github

# Step 2: Prepare staging and capture commit logs
echo "🌿 Preparing branch and history..."
git checkout master

# Stage all changes (including uncommitted files) so they are part of the squash
echo "📦 Staging current changes..."
git add -A

# Get recent commits since GitHub main BEFORE we reset
RECENT_COMMITS=$(git log --oneline github/main..HEAD 2>/dev/null | head -20 || echo "")

# Create a temporary PR branch based on current master
BRANCH_NAME="sync-$(date +%Y%m%d-%H%M%S)"
echo "🌿 Creating temporary PR branch: $BRANCH_NAME..."
git checkout -b "$BRANCH_NAME"

# Step 3: Squash commits
echo "🔨 Squashing commits against github/main..."
git reset --soft github/main

# Check if there are any changes to commit
if [ -z "$(git status --porcelain)" ]; then
  echo "⚠️ No changes or new commits detected between master and github/main."
  echo "🔄 Switching back to master..."
  git checkout master
  git branch -d "$BRANCH_NAME" 2>/dev/null || true
  exit 0
fi

echo "📝 Staging status:"
git status --porcelain

# Generate dynamic commit message template
echo "📊 Generating dynamic change summary..."

# Generate dynamic summary from commit messages
COMMIT_SUMMARY=""
if [ -n "$RECENT_COMMITS" ]; then
  while IFS= read -r commit; do
    [ -z "$commit" ] && continue
    msg=$(echo "$commit" | cut -d' ' -f2-)

    # Categorize commits
    if echo "$msg" | grep -qi "^feat\|^add\|^new"; then
      COMMIT_SUMMARY+="- $msg"$'\n'
    elif echo "$msg" | grep -qi "^fix\|^resolve\|^correct"; then
      COMMIT_SUMMARY+="- $msg"$'\n'
    elif echo "$msg" | grep -qi "^refactor\|^restructure"; then
      COMMIT_SUMMARY+="- $msg"$'\n'
    else
      COMMIT_SUMMARY+="- $msg"$'\n'
    fi
  done <<<"$RECENT_COMMITS"
else
  COMMIT_SUMMARY="- Comprehensive system improvements and updates"
fi

# Build dynamic template
COMMIT_TEMPLATE=$(
  cat <<EOF
feat: Complete NixOS configuration refactor

Comprehensive system overhaul including:
$COMMIT_SUMMARY

CHANGES SUMMARY:
$(git diff --cached --stat 2>/dev/null || echo "No staged changes")

FILES CHANGED:
$(git diff --cached --name-only 2>/dev/null | sed 's/^/- /' || echo "- System updates")

This commit represents the culmination of extensive local development work,
bringing all improvements into a clean, deployable state.
EOF
)

# Write template to temp file and open in editor
TEMP_FILE=$(mktemp)
echo "$COMMIT_TEMPLATE" >"$TEMP_FILE"

echo "📝 Opening commit message in editor..."
if command -v nvim &>/dev/null; then
  nvim "$TEMP_FILE"
elif [ -n "$EDITOR" ]; then
  $EDITOR "$TEMP_FILE"
else
  nano "$TEMP_FILE"
fi

# Use the edited content as commit message
COMMIT_MSG=$(cat "$TEMP_FILE")
rm "$TEMP_FILE"

# Commit with the prepared message
git commit -F <(echo "$COMMIT_MSG")

# Step 4: Push and create PR
echo "🚀 Pushing to GitHub..."
git push github "$BRANCH_NAME"

echo "📋 Creating PR..."
# Extract commit message for PR title and body
COMMIT_TITLE=$(echo "$COMMIT_MSG" | head -n 1)
PR_BODY=$(echo "$COMMIT_MSG" | tail -n +3)

# Fallback if no body was provided
if [ -z "$PR_BODY" ]; then
  PR_BODY="Major system modernization - see commit message for comprehensive details"
fi

gh pr create --title "$COMMIT_TITLE" \
  --body "$PR_BODY" \
  --head "$BRANCH_NAME" \
  --base main

echo "✅ PR created successfully!"
echo "🔗 Check GitHub for the new PR"

# Return to master branch so the user is left on their clean master
echo "🔄 Returning to master branch..."
git checkout master
