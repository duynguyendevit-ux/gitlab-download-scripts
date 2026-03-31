#!/bin/bash

# 🎯 GitLab Bulk Clone/Download Tool

set -euo pipefail

gum style --border double --padding "1" --margin "1" \
  --border-foreground 33 --foreground 15 \
  "📦 GitLab Bulk Clone/Download Tool"

# 🔧 Config
TOKEN_FILE="$HOME/.gitlab-tokens.json"
DEFAULT_URL="http://10.0.0.40"

# Load saved tokens
if [[ -f "$TOKEN_FILE" ]]; then
  saved_tokens=$(cat "$TOKEN_FILE")
else
  saved_tokens="{}"
fi

# GitLab URL với default
gum style --foreground 33 "🔧 GitLab URL (Enter = $DEFAULT_URL):"
GITLAB_URL=$(gum input --placeholder "$DEFAULT_URL" --value "$DEFAULT_URL")

if [[ -z "$GITLAB_URL" ]]; then
  GITLAB_URL="$DEFAULT_URL"
fi

# Check if token exists for this URL
saved_token=$(echo "$saved_tokens" | jq -r --arg url "$GITLAB_URL" '.[$url] // empty')

if [[ -n "$saved_token" ]]; then
  gum style --foreground 14 "🔑 Tìm thấy token đã lưu"
  use_saved=$(gum choose "Dùng token đã lưu" "Nhập token mới")
  
  if [[ "$use_saved" == "Dùng token đã lưu" ]]; then
    GITLAB_TOKEN="$saved_token"
    gum style --foreground 49 "✅ Đang dùng token đã lưu"
  else
    GITLAB_TOKEN=$(gum input --placeholder "Nhập GitLab Personal Access Token" --password)
    
    if [[ -z "$GITLAB_TOKEN" ]]; then
      gum style --foreground 196 "❌ Token không được để trống!"
      exit 1
    fi
    
    # Save new token
    saved_tokens=$(echo "$saved_tokens" | jq --arg url "$GITLAB_URL" --arg token "$GITLAB_TOKEN" '.[$url] = $token')
    echo "$saved_tokens" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    gum style --foreground 49 "✅ Đã lưu token mới"
  fi
else
  GITLAB_TOKEN=$(gum input --placeholder "Nhập GitLab Personal Access Token" --password)
  
  if [[ -z "$GITLAB_TOKEN" ]]; then
    gum style --foreground 196 "❌ Token không được để trống!"
    exit 1
  fi
  
  # Auto save token
  saved_tokens=$(echo "$saved_tokens" | jq --arg url "$GITLAB_URL" --arg token "$GITLAB_TOKEN" '.[$url] = $token')
  echo "$saved_tokens" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  gum style --foreground 49 "✅ Đã lưu token vào $TOKEN_FILE"
fi

# 📁 Chọn thư mục đích
gum style --foreground 36 "📁 Chọn thư mục để lưu repos:"
DEST_DIR=$(gum file --directory)

# Validate directory
if [[ -z "$DEST_DIR" ]]; then
  gum style --foreground 196 "❌ Chưa chọn thư mục đích!"
  exit 1
fi

# Ensure it's a directory, not a file
if [[ -f "$DEST_DIR" ]]; then
  gum style --foreground 196 "❌ Đã chọn file, cần chọn thư mục!"
  exit 1
fi

# Create directory if not exists
mkdir -p "$DEST_DIR" 2>/dev/null || {
  gum style --foreground 196 "❌ Không thể tạo thư mục: $DEST_DIR"
  exit 1
}

# 🎯 Chọn mode
gum style --foreground 14 "🎯 Chọn chế độ download:"
MODE=$(gum choose "Source Only (chỉ code, nhanh - khuyến nghị)" "Full Clone (với git history)")

# 📊 Counters
total_success=0
total_skipped=0
total_failed=0

# 🔍 Lấy danh sách groups
gum style --foreground 14 "🔍 Đang lấy danh sách groups..."

groups_response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_URL/api/v4/groups?per_page=100")

# Parse groups
group_options=("Tất cả projects")
group_ids=("")

while IFS='|' read -r gid gname gpath; do
  group_options+=("$gname ($gpath)")
  group_ids+=("$gid")
done < <(echo "$groups_response" | jq -r '.[] | "\(.id)|\(.name)|\(.full_path)"')

# Chọn group
gum style --foreground 14 "📦 Chọn group/namespace:"
selected_group=$(gum choose "${group_options[@]}")

# Get selected group ID
selected_index=0
for i in "${!group_options[@]}"; do
  if [[ "${group_options[$i]}" == "$selected_group" ]]; then
    selected_index=$i
    break
  fi
done

selected_group_id="${group_ids[$selected_index]}"

# 🔍 Lấy danh sách projects
if [[ -z "$selected_group_id" ]]; then
  gum style --foreground 14 "🔍 Đang lấy TẤT CẢ projects..."
  api_endpoint="$GITLAB_URL/api/v4/projects"
else
  gum style --foreground 14 "🔍 Đang lấy projects từ group: $selected_group"
  api_endpoint="$GITLAB_URL/api/v4/groups/$selected_group_id/projects"
fi

page=1
all_projects=()

while true; do
  response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$api_endpoint?per_page=100&page=$page&simple=true&include_subgroups=true")
  
  # Check if empty
  project_count=$(echo "$response" | jq '. | length')
  if [[ $project_count -eq 0 ]]; then
    break
  fi
  
  # Collect projects
  while IFS='|' read -r id path clone_url branch; do
    all_projects+=("$id|$path|$clone_url|$branch")
  done < <(echo "$response" | jq -r '.[] | "\(.id)|\(.path_with_namespace)|\(.http_url_to_repo)|\(.default_branch)"')
  
  ((page++))
done

total_projects=${#all_projects[@]}

if [[ $total_projects -eq 0 ]]; then
  gum style --foreground 11 "⚠️  Không tìm thấy project nào!"
  exit 0
fi

gum style --foreground 14 "📦 Tìm thấy $total_projects projects"

# 🚀 Process projects
current=0

for project_data in "${all_projects[@]}"; do
  IFS='|' read -r id path clone_url branch <<< "$project_data"
  ((current++))
  
  project_dir="$DEST_DIR/$path"
  
  # Progress
  gum style --foreground 14 "[$current/$total_projects] Processing: $path"
  
  # Check if exists
  if [[ -d "$project_dir" ]]; then
    gum style --foreground 11 "⚠️  Bỏ qua: $path (đã tồn tại)"
    ((total_skipped++))
    continue
  fi
  
  # Create parent directory
  mkdir -p "$(dirname "$project_dir")"
  
  if [[ "$MODE" == "Full Clone (với git history)" ]]; then
    # Mode 1: Full clone
    auth_url=$(echo "$clone_url" | sed "s|http://|http://oauth2:$GITLAB_TOKEN@|")
    
    if git clone --quiet "$auth_url" "$project_dir" 2>/dev/null; then
      gum style --foreground 49 "✅ Cloned: $path"
      ((total_success++))
    else
      gum style --foreground 196 "❌ Failed: $path"
      ((total_failed++))
    fi
  else
    # Mode 2: Source only (archive)
    archive_url="$GITLAB_URL/api/v4/projects/$id/repository/archive.tar.gz?sha=$branch"
    
    mkdir -p "$project_dir"
    
    if curl -s --fail --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$archive_url" | \
       tar xzf - -C "$project_dir" --strip-components=1 2>/dev/null; then
      gum style --foreground 49 "✅ Downloaded: $path"
      ((total_success++))
    else
      gum style --foreground 196 "❌ Failed: $path"
      rmdir "$project_dir" 2>/dev/null || true
      ((total_failed++))
    fi
  fi
done

# 📊 Summary
echo ""
gum style --border rounded --padding "1" --margin "1" \
  --border-foreground 14 --foreground 15 \
  "🎉 Hoàn tất!

📊 Thống kê:
  • Tổng projects: $total_projects
  • Thành công: $total_success
  • Bỏ qua: $total_skipped
  • Thất bại: $total_failed

📁 Vị trí: $DEST_DIR"

# 🎯 Suggest next step
if [[ $total_success -gt 0 ]]; then
  echo ""
  gum style --foreground 14 "💡 Tiếp theo: Chạy script extract-src.sh để lấy code từ thư mục src/"
fi
