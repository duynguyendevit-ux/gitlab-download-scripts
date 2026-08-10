#!/bin/bash

# Script to push changes from Source Only repos back to GitLab
# Usage: ./push-changes.sh [directory]

set -e

REPOS_DIR="${1:-./gitlab-repos}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gitlab-config.sh
source "$SCRIPT_DIR/gitlab-config.sh"
gitlab_config_init

# Preserve explicit environment overrides and fill only missing values from config.
if [[ -z "${GITLAB_URL+x}" ]]; then
  GITLAB_URL=""
  if [[ -f "$GITLAB_URL_FILE" ]]; then
    GITLAB_URL=$(<"$GITLAB_URL_FILE")
  fi
fi

if [[ -z "${GITLAB_TOKEN+x}" ]]; then
  GITLAB_TOKEN=""
  if [[ -n "$GITLAB_URL" ]]; then
    GITLAB_TOKEN=$(jq -r --arg url "$GITLAB_URL" '.[$url] // empty' "$GITLAB_TOKEN_FILE")
  fi
fi

if [[ -z "$GITLAB_URL" ]]; then
  echo "❌ GitLab URL not found. Run gitlab-bulk-download.sh first."
  exit 1
fi

echo "🔍 Scanning repos in: $REPOS_DIR"
echo "🔗 GitLab: $GITLAB_URL"
echo ""

total=0
success=0
skipped=0
failed=0

# Find all directories
while IFS= read -r -d '' dir; do
  total=$((total + 1))
  
  # Get project path relative to REPOS_DIR
  project_path="${dir#$REPOS_DIR/}"
  repo_name=$(basename "$dir")
  
  echo "[$total] 📦 $project_path"
  
  # Check if has .git
  if [[ ! -d "$dir/.git" ]]; then
    echo "  ⚠️  Not a git repo (run init-git-repos.sh first)"
    skipped=$((skipped + 1))
    continue
  fi
  
  cd "$dir"
  
  # Check if has changes
  if git diff --quiet && git diff --cached --quiet; then
    echo "  ⏭️  No changes"
    skipped=$((skipped + 1))
    cd - > /dev/null
    continue
  fi
  
  # Check if remote exists
  if git remote | grep -q "^origin$"; then
    echo "  🔗 Remote already exists"
  else
    # Construct SSH URL from project path
    # Format: ssh://git@host:port/path.git
    if [[ "$GITLAB_URL" =~ ^https?://([^/]+) ]]; then
      gitlab_host="${BASH_REMATCH[1]}"
      # Assume SSH port 17122 (customize if needed)
      ssh_port="${SSH_PORT:-17122}"
      remote_url="ssh://git@$gitlab_host:$ssh_port/$project_path.git"
      
      echo "  ➕ Adding remote: $remote_url"
      git remote add origin "$remote_url"
    else
      echo "  ❌ Cannot construct remote URL"
      failed=$((failed + 1))
      cd - > /dev/null
      continue
    fi
  fi
  
  # Get current branch
  current_branch=$(git branch --show-current)
  if [[ -z "$current_branch" ]]; then
    current_branch="main"
    git checkout -b "$current_branch" 2>/dev/null || true
  fi
  
  # Commit changes if any
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "  💾 Committing changes..."
    git add .
    git commit -m "Update from local changes - $(date '+%Y-%m-%d %H:%M:%S')" || true
  fi
  
  # Push
  echo "  🚀 Pushing to $current_branch..."
  if git push -u origin "$current_branch" 2>&1; then
    echo "  ✅ Pushed successfully"
    success=$((success + 1))
  else
    echo "  ❌ Push failed"
    failed=$((failed + 1))
  fi
  
  cd - > /dev/null
  
done < <(find "$REPOS_DIR" -mindepth 1 -maxdepth 3 -type d -print0)

echo ""
echo "🎉 Done!"
echo "📊 Stats:"
echo "  • Total: $total"
echo "  • Pushed: $success"
echo "  • Skipped: $skipped"
echo "  • Failed: $failed"
