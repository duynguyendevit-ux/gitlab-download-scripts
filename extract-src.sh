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

# Find all directories with src/ folder
temp_list="/tmp/extract-list-$$.txt"
find "$SOURCE_BASE" -type d -name "src" > "$temp_list"

echo "DEBUG: Found $(wc -l < "$temp_list") src/ folders"

while read -r src_folder; do
  # Get parent directory (the repo directory)
  repo_path=$(dirname "$src_folder")
  
  # Skip if parent is a build folder
  parent_name=$(basename "$repo_path")
  [[ "$parent_name" =~ ^(node_modules|target|build|dist)$ ]] && continue
  
  # Get relative path from SOURCE_BASE
  rel_path="${repo_path#$SOURCE_BASE/}"
  
  total=$((total + 1))
  
  dest_folder="$DEST_BASE/$rel_path"
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
  echo "✅ $rel_path: $file_count files"
  success=$((success + 1))
done < "$temp_list"

rm "$temp_list"

# ✅ Hoàn tất với summary
echo ""
echo "🎉 Hoàn tất!"
echo "📊 Thống kê:"
echo "  • Tổng repos: $total"
echo "  • Thành công: $success"
echo "  • Bỏ qua: $skipped"
echo "📁 Kết quả: $DEST_BASE"
