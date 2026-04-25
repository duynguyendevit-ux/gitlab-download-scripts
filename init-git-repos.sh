#!/bin/bash

# Script to initialize git repos for Source Only downloads
# Usage: ./init-git-repos.sh [directory]

set -e

REPOS_DIR="${1:-./gitlab-repos}"

if [[ ! -d "$REPOS_DIR" ]]; then
  echo "❌ Directory not found: $REPOS_DIR"
  exit 1
fi

echo "🔍 Scanning for repos in: $REPOS_DIR"
echo ""

total=0
success=0
skipped=0

# Find all directories that don't have .git
while IFS= read -r -d '' dir; do
  total=$((total + 1))
  repo_name=$(basename "$dir")
  
  # Skip if already has .git
  if [[ -d "$dir/.git" ]]; then
    echo "[$total] ⏭️  $repo_name (already initialized)"
    skipped=$((skipped + 1))
    continue
  fi
  
  # Skip if empty
  file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
  if [[ $file_count -eq 0 ]]; then
    echo "[$total] ⚠️  $repo_name (empty, skipping)"
    skipped=$((skipped + 1))
    continue
  fi
  
  echo "[$total] 🔧 $repo_name"
  
  cd "$dir"
  
  # Initialize git
  git init -q
  
  # Create .gitignore if not exists
  if [[ ! -f .gitignore ]]; then
    cat > .gitignore << 'EOF'
# Common ignores
node_modules/
target/
build/
dist/
*.log
.env
.DS_Store
EOF
  fi
  
  # Add all files
  git add .
  
  # Initial commit
  git commit -q -m "Initial commit from GitLab archive"
  
  echo "  ✅ Initialized with $(git rev-list --count HEAD) commit"
  success=$((success + 1))
  
  cd - > /dev/null
  
done < <(find "$REPOS_DIR" -mindepth 1 -maxdepth 3 -type d -print0)

echo ""
echo "🎉 Done!"
echo "📊 Stats:"
echo "  • Total: $total"
echo "  • Initialized: $success"
echo "  • Skipped: $skipped"
