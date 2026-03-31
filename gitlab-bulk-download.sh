#!/bin/bash

# 🎯 GitLab Bulk Clone/Download Tool (Fixed v2)

set -euo pipefail

gum style --border double --padding "1" --margin "1" \
  --border-foreground 33 --foreground 15 \
  "📦 GitLab Bulk Clone/Download Tool"

TOKEN_FILE="$HOME/.gitlab-tokens.json"
DEFAULT_URL="http://10.0.0.40"

[[ -f "$TOKEN_FILE" ]] && saved_tokens=$(cat "$TOKEN_FILE") || saved_tokens="{}"

gum style --foreground 33 "🔧 GitLab URL (Enter = $DEFAULT_URL):"
GITLAB_URL=$(gum input --placeholder "$DEFAULT_URL" --value "$DEFAULT_URL")
[[ -z "$GITLAB_URL" ]] && GITLAB_URL="$DEFAULT_URL"

saved_token=$(echo "$saved_tokens" | jq -r --arg url "$GITLAB_URL" '.[$url] // empty')

if [[ -n "$saved_token" ]]; then
  gum style --foreground 14 "🔑 Tìm thấy token đã lưu"
  use_saved=$(gum choose "Dùng token đã lưu" "Nhập token mới")
  
  if [[ "$use_saved" == "Dùng token đã lưu" ]]; then
    GITLAB_TOKEN="$saved_token"
    gum style --foreground 49 "✅ Đang dùng token đã lưu"
  else
    GITLAB_TOKEN=$(gum input --placeholder "Nhập GitLab Personal Access Token" --password)
    [[ -z "$GITLAB_TOKEN" ]] && { gum style --foreground 196 "❌ Token trống!"; exit 1; }
    saved_tokens=$(echo "$saved_tokens" | jq --arg url "$GITLAB_URL" --arg token "$GITLAB_TOKEN" '.[$url] = $token')
    echo "$saved_tokens" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    gum style --foreground 49 "✅ Đã lưu token mới"
  fi
else
  GITLAB_TOKEN=$(gum input --placeholder "Nhập GitLab Personal Access Token" --password)
  [[ -z "$GITLAB_TOKEN" ]] && { gum style --foreground 196 "❌ Token trống!"; exit 1; }
  saved_tokens=$(echo "$saved_tokens" | jq --arg url "$GITLAB_URL" --arg token "$GITLAB_TOKEN" '.[$url] = $token')
  echo "$saved_tokens" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  gum style --foreground 49 "✅ Đã lưu token"
fi

# 📁 Thư mục đích (dùng thư mục hiện tại)
DEST_DIR="$(pwd)/gitlab-repos"
mkdir -p "$DEST_DIR"
gum style --foreground 49 "📁 Sẽ lưu vào: $DEST_DIR"

gum style --foreground 14 "🎯 Chọn chế độ download:"
MODE=$(gum choose "Source Only (chỉ code, nhanh - khuyến nghị)" "Full Clone (với git history)")

total_success=0
total_skipped=0
total_failed=0

gum style --foreground 14 "🔍 Đang lấy danh sách groups..."
groups_response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/groups?per_page=100")

group_options=("Tất cả projects")
group_ids=("")

while IFS='|' read -r gid gname gpath; do
  group_options+=("$gname ($gpath)")
  group_ids+=("$gid")
done < <(echo "$groups_response" | jq -r '.[] | "\(.id)|\(.name)|\(.full_path)"')

gum style --foreground 14 "📦 Chọn group/namespace:"
selected_group=$(gum choose "${group_options[@]}")

selected_index=0
for i in "${!group_options[@]}"; do
  [[ "${group_options[$i]}" == "$selected_group" ]] && { selected_index=$i; break; }
done

selected_group_id="${group_ids[$selected_index]}"

if [[ -z "$selected_group_id" ]]; then
  gum style --foreground 14 "🔍 Đang lấy TẤT CẢ projects..."
  api_endpoint="$GITLAB_URL/api/v4/projects"
else
  gum style --foreground 14 "🔍 Đang lấy projects từ group: $selected_group"
  api_endpoint="$GITLAB_URL/api/v4/groups/$selected_group_id/projects"
fi

page=1
projects_file="/tmp/gitlab-projects-$$.txt"
> "$projects_file"

while true; do
  response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$api_endpoint?per_page=100&page=$page&simple=true&include_subgroups=true")
  project_count=$(echo "$response" | jq '. | length')
  [[ $project_count -eq 0 ]] && break
  
  echo "$response" | jq -r '.[] | "\(.id)|\(.path_with_namespace)|\(.ssh_url_to_repo)|\(.default_branch)"' >> "$projects_file"
  
  ((page++))
done

total_projects=$(wc -l < "$projects_file")
[[ $total_projects -eq 0 ]] && { gum style --foreground 11 "⚠️  Không tìm thấy project!"; rm "$projects_file"; exit 0; }

gum style --foreground 14 "📦 Tìm thấy $total_projects projects"
echo "🚀 Bắt đầu download..."

current=0

while IFS='|' read -r id path clone_url branch; do
  ((current++))
  project_dir="$DEST_DIR/$path"
  
  echo "[$current/$total_projects] $path"
  
  if [[ -d "$project_dir" ]]; then
    echo "  ⚠️  Bỏ qua (đã tồn tại)"
    ((total_skipped++))
    continue
  fi
  
  mkdir -p "$(dirname "$project_dir")"
  
  if [[ "$MODE" == "Full Clone (với git history)" ]]; then
    if git clone --quiet "$clone_url" "$project_dir" 2>/dev/null; then
      echo "  ✅ Cloned"
      ((total_success++))
    else
      echo "  ❌ Failed"
      ((total_failed++))
    fi
  else
    archive_url="$GITLAB_URL/api/v4/projects/$id/repository/archive.tar.gz?sha=$branch"
    mkdir -p "$project_dir"
    if curl -s --fail --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$archive_url" | \
       tar xzf - -C "$project_dir" --strip-components=1 2>/dev/null; then
      echo "  ✅ Downloaded"
      ((total_success++))
    else
      echo "  ❌ Failed"
      rmdir "$project_dir" 2>/dev/null || true
      ((total_failed++))
    fi
  fi
done < "$projects_file"

rm "$projects_file"

echo ""
echo "🎉 Hoàn tất!"
echo "📊 Thống kê:"
echo "  • Tổng: $total_projects"
echo "  • Thành công: $total_success"
echo "  • Bỏ qua: $total_skipped"
echo "  • Thất bại: $total_failed"
echo "📁 Vị trí: $DEST_DIR"
