#!/bin/bash

# 🎯 Extract src/ từ các repo → thư mục đích, loại bỏ file nhạy cảm

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: extract-src.sh [--source DIR --destination DIR] [--manifest FILE|--all]

Options:
  -s, --source DIR       Source directory containing repositories
  -d, --destination DIR  Destination directory for extracted src folders
      --manifest FILE    Extract only projects listed in FILE
      --all               Scan all repositories under the source directory
  -h, --help             Show this help
EOF
}

SOURCE_BASE=""
DEST_BASE=""
MANIFEST_FILE=""
MANIFEST_OPTION_SET=false
ALL_REQUESTED=false
cli_mode=false

is_safe_manifest_path() {
  local project_path=$1
  local path_segment
  local -a path_segments

  [[ -n "$project_path" && "$project_path" != /* ]] || return 1
  [[ "$project_path" != */ && "$project_path" != *//* ]] || return 1
  IFS='/' read -r -a path_segments <<< "$project_path"
  for path_segment in "${path_segments[@]}"; do
    [[ -n "$path_segment" && "$path_segment" != "." && "$path_segment" != ".." ]] || return 1
  done
  return 0
}

trim_whitespace() {
  printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--source)
      [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
      SOURCE_BASE="$2"
      cli_mode=true
      shift 2
      ;;
    -d|--destination)
      [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
      DEST_BASE="$2"
      cli_mode=true
      shift 2
      ;;
    --manifest)
      [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
      MANIFEST_FILE="$2"
      MANIFEST_OPTION_SET=true
      cli_mode=true
      shift 2
      ;;
    --all)
      ALL_REQUESTED=true
      cli_mode=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$MANIFEST_OPTION_SET" == true && "$ALL_REQUESTED" == true ]]; then
  echo "Error: --manifest and --all cannot be used together" >&2
  exit 2
fi

if [[ "$MANIFEST_OPTION_SET" == true && ! -r "$MANIFEST_FILE" ]]; then
  echo "Error: manifest file is not readable: $MANIFEST_FILE" >&2
  exit 2
fi

if [[ "$cli_mode" == true ]]; then
  if [[ -z "$SOURCE_BASE" || -z "$DEST_BASE" ]]; then
    usage >&2
    exit 2
  fi

  if [[ ! -d "$SOURCE_BASE" ]]; then
    echo "Error: source directory is invalid: $SOURCE_BASE" >&2
    exit 1
  fi

  mkdir -p "$DEST_BASE"
  if [[ "$MANIFEST_OPTION_SET" == true ]]; then
    filter_mode="manifest"
  elif [[ "$ALL_REQUESTED" == true ]]; then
    filter_mode="all"
  elif [[ -r "$SOURCE_BASE/.gitlab-ref-projects.txt" ]]; then
    MANIFEST_FILE="$SOURCE_BASE/.gitlab-ref-projects.txt"
    filter_mode="manifest"
  else
    filter_mode="all"
  fi
else
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

default_manifest="$SOURCE_BASE/.gitlab-ref-projects.txt"
if [[ -r "$default_manifest" ]]; then
  filter_choice=$(gum choose "Chỉ projects từ ref-list gần nhất" "Tất cả repositories")
  if [[ "$filter_choice" == "Chỉ projects từ ref-list gần nhất" ]]; then
    MANIFEST_FILE="$default_manifest"
    filter_mode="manifest"
  else
    filter_mode="all"
  fi
else
  filter_mode="all"
fi

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
fi

echo ""

# 📊 Counters
total=0
success=0
skipped=0

# ✅ Bắt đầu extract
if [[ "$cli_mode" == true ]]; then
  echo "🔍 Đang quét repositories (bao gồm subfolders)..."
else
  gum style --foreground 14 "🔍 Đang quét repositories (bao gồm subfolders)..."
fi

# Find all directories with src/ folder
temp_list=$(mktemp "${TMPDIR:-/tmp}/extract-list.XXXXXX")
raw_src_list=$(mktemp "${TMPDIR:-/tmp}/extract-raw-list.XXXXXX")
find_temp_list=""
scan_failed=0

cleanup_extract_temps() {
  if [[ -n "$find_temp_list" ]]; then
    rm -f "$find_temp_list"
    find_temp_list=""
  fi
  rm -f "$raw_src_list" "$temp_list"
}

trap cleanup_extract_temps EXIT

if [[ "$filter_mode" == "manifest" ]]; then
  while IFS= read -r raw_manifest_line || [[ -n "$raw_manifest_line" ]]; do
    manifest_line=${raw_manifest_line%$'\r'}
    manifest_line=$(trim_whitespace "$manifest_line")
    [[ -z "$manifest_line" || "${manifest_line:0:1}" == "#" ]] && continue
    if ! is_safe_manifest_path "$manifest_line"; then
      echo "WARNING: Ignoring unsafe manifest path: $manifest_line" >&2
      continue
    fi

    project_dir="$SOURCE_BASE/$manifest_line"
    if [[ ! -d "$project_dir" ]]; then
      echo "WARNING: Manifest project is missing: $manifest_line" >&2
      continue
    fi

    find_temp_list=$(mktemp "${TMPDIR:-/tmp}/extract-find-list.XXXXXX")
    if ! find "$project_dir" -type d -name "src" -print > "$find_temp_list"; then
      echo "ERROR: Could not scan manifest project: $manifest_line" >&2
      scan_failed=1
      rm -f "$find_temp_list"
      find_temp_list=""
      continue
    fi

    if ! cat "$find_temp_list" >> "$raw_src_list"; then
      echo "ERROR: Could not read scan results for manifest project: $manifest_line" >&2
      scan_failed=1
    fi
    rm -f "$find_temp_list"
    find_temp_list=""
  done < "$MANIFEST_FILE"
else
  if ! find "$SOURCE_BASE" -type d -name "src" -print > "$raw_src_list"; then
    echo "ERROR: Could not scan source directory: $SOURCE_BASE" >&2
    scan_failed=1
  fi
fi

if ! LC_ALL=C sort -u "$raw_src_list" > "$temp_list"; then
  echo "ERROR: Could not deduplicate extracted source paths" >&2
  scan_failed=1
fi

if [[ "$scan_failed" -ne 0 ]]; then
  echo "WARNING: One or more source scans failed; extraction will exit nonzero" >&2
fi

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

# ✅ Hoàn tất với summary
echo ""
if [[ "$scan_failed" -ne 0 ]]; then
  echo "❌ Hoàn tất với lỗi!"
  echo "📊 Thống kê (có lỗi khi quét source):"
else
  echo "🎉 Hoàn tất!"
  echo "📊 Thống kê:"
fi
echo "  • Tổng repos: $total"
echo "  • Thành công: $success"
echo "  • Bỏ qua: $skipped"
echo "📁 Kết quả: $DEST_BASE"

if [[ "$scan_failed" -ne 0 ]]; then
  exit 1
fi
