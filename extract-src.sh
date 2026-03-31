#!/bin/bash

# 🎯 Extract src/ từ các repo → thư mục đích, loại bỏ file nhạy cảm

set -euo pipefail

# 💬 Hiển thị banner
gum style --border double --padding "1" --margin "1" \
  --border-foreground 33 --foreground 15 \
  "📤 Extracting 'src/' folders from repositories"

# 📂 Chọn thư mục nguồn
echo ""
gum style --foreground 33 --bold "📂 Chọn thư mục chứa repos:"
echo "   (Navigate và Enter để chọn - chỉ hiển thị folders có nội dung)"
SOURCE_BASE=$(gum file --directory --file=false)

if [[ -z "$SOURCE_BASE" || ! -d "$SOURCE_BASE" ]]; then
  gum style --foreground 196 "❌ Thư mục nguồn không hợp lệ!"
  exit 1
fi

echo ""
gum style --foreground 49 "✓ Nguồn: $SOURCE_BASE"
echo ""

# 📁 Chọn thư mục đích
echo ""
gum style --foreground 36 --bold "📁 Chọn thư mục đích:"
dest_choice=$(gum choose "Tạo thư mục mới" "Chọn thư mục có sẵn")

if [[ "$dest_choice" == "Tạo thư mục mới" ]]; then
  echo "   Nhập tên thư mục mới (hoặc đường dẫn đầy đủ):"
  new_folder=$(gum input --placeholder "extracted-src")
  
  if [[ -z "$new_folder" ]]; then
    gum style --foreground 196 "❌ Tên thư mục trống!"
    exit 1
  fi
  
  # If relative path, create in current directory
  if [[ "$new_folder" != /* ]]; then
    DEST_BASE="$(pwd)/$new_folder"
  else
    DEST_BASE="$new_folder"
  fi
  
  mkdir -p "$DEST_BASE"
  gum style --foreground 49 "✓ Đã tạo: $DEST_BASE"
else
  echo "   (Navigate và Enter để chọn - chỉ hiển thị folders có nội dung)"
  DEST_BASE=$(gum file --directory --file=false)
  
  if [[ -z "$DEST_BASE" ]]; then
    gum style --foreground 196 "❌ Chưa chọn thư mục đích!"
    exit 1
  fi
  
  gum style --foreground 49 "✓ Đã chọn: $DEST_BASE"
fi

echo ""

# 📊 Counters
total=0
success=0
skipped=0

# ✅ Bắt đầu extract
gum style --foreground 14 "🔍 Đang quét repositories (bao gồm subfolders)..."

# Find all directories with src/ folder
temp_list="/tmp/extract-list-$$.txt"
find "$SOURCE_BASE" -type d -name "src" > "$temp_list"

total_found=$(wc -l < "$temp_list")
echo "DEBUG: Found $total_found src/ folders"
echo "DEBUG: First 5 entries:"
head -5 "$temp_list"
echo ""

while read -r src_folder; do
  # Get parent directory (the repo directory)
  repo_path=$(dirname "$src_folder")
  
  # Skip if parent is a build folder
  parent_name=$(basename "$repo_path")
  if [[ "$parent_name" =~ ^(node_modules|target|build|dist)$ ]]; then
    echo "DEBUG: Skipping $parent_name (build folder)"
    continue
  fi
  
  # Get relative path from SOURCE_BASE
  rel_path="${repo_path#$SOURCE_BASE/}"
  
  echo "DEBUG: Processing $rel_path"
  
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
    --exclude='resources' \
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
