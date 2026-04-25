#!/bin/bash

# Script to get remote URLs for Source Only repos
# Usage: ./get-remote-urls.sh [directory]

set -e

REPOS_DIR="${1:-./gitlab-repos}"

# Load saved GitLab URL and token
TOKEN_FILE="$HOME/.gitlab-tokens.json"
if [[ -f "$TOKEN_FILE" ]]; then
  GITLAB_URL=$(jq -r 'keys[0]' "$TOKEN_FILE" 2>/dev/null || echo "")
  GITLAB_TOKEN=$(jq -r ".\"$GITLAB_URL\"" "$TOKEN_FILE" 2>/dev/null || echo "")
fi

if [[ -z "$GITLAB_URL" ]] || [[ -z "$GITLAB_TOKEN" ]]; then
  echo "❌ GitLab credentials not found. Run gitlab-bulk-download.sh first."
  exit 1
fi

echo "🔍 Fetching remote URLs from GitLab..."
echo "🔗 GitLab: $GITLAB_URL"
echo ""

# Create mapping file
MAPPING_FILE="$REPOS_DIR/remote-urls.txt"
> "$MAPPING_FILE"

total=0
success=0

# Find all directories
while IFS= read -r -d '' dir; do
  total=$((total + 1))
  
  # Get project path relative to REPOS_DIR
  project_path="${dir#$REPOS_DIR/}"
  
  # URL encode the project path
  encoded_path=$(echo "$project_path" | sed 's/\//%2F/g')
  
  # Fetch project info from GitLab API
  project_info=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_URL/api/v4/projects/$encoded_path" 2>/dev/null)
  
  if [[ -n "$project_info" ]] && echo "$project_info" | jq -e '.ssh_url_to_repo' > /dev/null 2>&1; then
    ssh_url=$(echo "$project_info" | jq -r '.ssh_url_to_repo')
    default_branch=$(echo "$project_info" | jq -r '.default_branch // "main"')
    
    echo "✅ $project_path"
    echo "   → $ssh_url"
    
    # Save to mapping file
    echo "$project_path|$ssh_url|$default_branch" >> "$MAPPING_FILE"
    
    success=$((success + 1))
  else
    echo "⚠️  $project_path (not found in GitLab)"
  fi
  
done < <(find "$REPOS_DIR" -mindepth 1 -maxdepth 3 -type d ! -name ".*" -print0)

echo ""
echo "🎉 Done!"
echo "📊 Stats:"
echo "  • Total: $total"
echo "  • Found: $success"
echo ""
echo "📄 Remote URLs saved to: $MAPPING_FILE"
echo ""
echo "💡 Next steps:"
echo "   1. Review: cat $MAPPING_FILE"
echo "   2. Init git: ./init-git-repos.sh"
echo "   3. Add remotes: ./add-remotes.sh"
