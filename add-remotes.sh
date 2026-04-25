#!/bin/bash

# Script to add remote URLs to Source Only repos
# Usage: ./add-remotes.sh [directory]

set -e

REPOS_DIR="${1:-./gitlab-repos}"
MAPPING_FILE="$REPOS_DIR/remote-urls.txt"

if [[ ! -f "$MAPPING_FILE" ]]; then
  echo "❌ Mapping file not found: $MAPPING_FILE"
  echo "💡 Run ./get-remote-urls.sh first"
  exit 1
fi

echo "🔗 Adding remote URLs to repos..."
echo ""

total=0
success=0
skipped=0
failed=0

while IFS='|' read -r project_path ssh_url default_branch; do
  total=$((total + 1))
  
  repo_dir="$REPOS_DIR/$project_path"
  
  echo "[$total] 📦 $project_path"
  
  if [[ ! -d "$repo_dir" ]]; then
    echo "  ⚠️  Directory not found"
    skipped=$((skipped + 1))
    continue
  fi
  
  if [[ ! -d "$repo_dir/.git" ]]; then
    echo "  ⚠️  Not a git repo (run init-git-repos.sh first)"
    skipped=$((skipped + 1))
    continue
  fi
  
  cd "$repo_dir"
  
  # Check if remote already exists
  if git remote | grep -q "^origin$"; then
    existing_url=$(git remote get-url origin)
    if [[ "$existing_url" == "$ssh_url" ]]; then
      echo "  ✅ Remote already correct"
      success=$((success + 1))
    else
      echo "  🔄 Updating remote"
      echo "     Old: $existing_url"
      echo "     New: $ssh_url"
      git remote set-url origin "$ssh_url"
      success=$((success + 1))
    fi
  else
    echo "  ➕ Adding remote: $ssh_url"
    git remote add origin "$ssh_url"
    success=$((success + 1))
  fi
  
  # Set default branch
  current_branch=$(git branch --show-current)
  if [[ -z "$current_branch" ]]; then
    echo "  🌿 Creating branch: $default_branch"
    git checkout -b "$default_branch" 2>/dev/null || true
  fi
  
  cd - > /dev/null
  
done < "$MAPPING_FILE"

echo ""
echo "🎉 Done!"
echo "📊 Stats:"
echo "  • Total: $total"
echo "  • Success: $success"
echo "  • Skipped: $skipped"
echo "  • Failed: $failed"
echo ""
echo "💡 Next steps:"
echo "   • Make changes to your repos"
echo "   • Run: ./push-changes.sh"
