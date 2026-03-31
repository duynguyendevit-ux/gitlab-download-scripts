#!/bin/bash

# 🎯 Extract src/ từ các repo → thư mục đích, loại bỏ file nhạy cảm

set -euo pipefail

# 💬 Hiển thị banner
gum style --border double --padding "1" --margin "1" \
  --border-foreground 33 --foreground 15 \
  "📤 Extracting 'src/' folders from repositories"

# 📂 Chọn thư mục chứa các repository
gum style --foreground 33 "📂 Chọn thư mục chứa các repository:"
SOURCE_BASE=$(gum file --directory)
if [[ -z "$SOURCE_BASE" ]]; then
  gum style --foreground 196 "❌ Bạn chưa chọn thư mục nguồn. Thoát!"
  exit 1
fi

# Validate source directory
if [[ ! -d "$SOURCE_BASE" ]]; then
  gum style --foreground 196 "❌ Thư mục nguồn không tồn tại!"
  exit 1
fi

# 📁 Chọn thư mục đích
gum style --foreground 36 "📁 Chọn thư mục đích để lưu kết quả extract:"
DEST_BASE=$(gum file --directory)
if [[ -z "$DEST_BASE" ]]; then
  gum style --foreground 196 "❌ Bạn chưa chọn thư mục đích. Thoát!"
  exit 1
fi

# Create destination if not exists
mkdir -p "$DEST_BASE" 2>/dev/null || {
  gum style --foreground 196 "❌ Không thể tạo thư mục đích!"
  exit 1
}

# 📊 Counters
total=0
success=0
skipped=0

# ✅ Bắt đầu extract
gum style --foreground 14 "🔍 Đang quét repositories (bao gồm subfolders)..."

# Scan recursively for all directories
find "$SOURCE_BASE" -type d -mindepth 1 | while read -r repo_path; do
  # Skip hidden directories and common build folders
  [[ "$(basename "$repo_path")" =~ ^\. ]] && continue
  [[ "$(basename "$repo_path")" =~ ^(node_modules|target|build|dist|.git)$ ]] && continue
  
  # Check if this directory contains a src/ folder
  if [[ -d "$repo_path/src" ]]; then
    # Get relative path from SOURCE_BASE
    rel_path="${repo_path#$SOURCE_BASE/}"
    repo_name="$rel_path"
    
    ((total++))
    
    src_folder="$repo_path/src"
    dest_folder="$DEST_BASE/$repo_name"
    mkdir -p "$dest_folder"

    # Copy, loại bỏ các file nhạy cảm
    rsync -a --quiet \
      --exclude='*.yml' \
      --exclude='*.yaml' \
      --exclude='*.properties' \
      --exclude='*.env' \
      --exclude='*.env.*' \
      --exclude='.git' \
      --exclude='node_modules' \
      --exclude='target' \
      --exclude='build' \
      --exclude='dist' \
      "$src_folder/" "$dest_folder/"

    # Đếm files đã copy
    file_count=$(find "$dest_folder" -type f 2>/dev/null | wc -l)
    gum style --foreground 49 "✅ $repo_name: $file_count files"
    ((success++))
  fi
done

# ✅ Hoàn tất với summary
echo ""
gum style --border rounded --padding "1" --margin "1" \
  --border-foreground 14 --foreground 15 \
  "🎉 Hoàn tất!

📊 Thống kê:
  • Tổng repos: $total
  • Thành công: $success
  • Bỏ qua: $skipped

📁 Kết quả: $DEST_BASE"
