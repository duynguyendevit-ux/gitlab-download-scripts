#!/bin/bash

# 🎯 GitLab Bulk Clone/Download Tool (Fixed v3)

set -euo pipefail

# Trap để debug
trap 'echo "ERROR: Script exited at line $LINENO"' ERR
trap 'echo "Script interrupted"' INT TERM

gum style --border double --padding "1" --margin "1" \
  --border-foreground 33 --foreground 15 \
  "📦 GitLab Bulk Clone/Download Tool"

TOKEN_FILE="$HOME/.gitlab-tokens.json"
URL_FILE="$HOME/.gitlab-url.txt"

[[ -f "$TOKEN_FILE" ]] && saved_tokens=$(cat "$TOKEN_FILE") || saved_tokens="{}"
[[ -f "$URL_FILE" ]] && saved_url=$(cat "$URL_FILE") || saved_url=""

gum style --foreground 33 "🔧 GitLab URL:"
if [[ -n "$saved_url" ]]; then
  gum style --foreground 14 "   Đã lưu: $saved_url"
  use_saved_url=$(gum choose "Dùng URL đã lưu" "Nhập URL mới")
  if [[ "$use_saved_url" == "Dùng URL đã lưu" ]]; then
    GITLAB_URL="$saved_url"
  else
    GITLAB_URL=$(gum input --placeholder "http://your-gitlab-host")
    [[ -z "$GITLAB_URL" ]] && { gum style --foreground 196 "❌ URL trống!"; exit 1; }
    echo "$GITLAB_URL" > "$URL_FILE"
  fi
else
  GITLAB_URL=$(gum input --placeholder "http://your-gitlab-host")
  [[ -z "$GITLAB_URL" ]] && { gum style --foreground 196 "❌ URL trống!"; exit 1; }
  echo "$GITLAB_URL" > "$URL_FILE"
fi

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
echo "DEBUG: Projects file: $projects_file"
echo "DEBUG: File exists: $(test -f "$projects_file" && echo YES || echo NO)"
echo "DEBUG: File size: $(wc -c < "$projects_file") bytes"
echo "DEBUG: Line count: $(wc -l < "$projects_file") lines"
echo "DEBUG: First 3 lines:"
head -3 "$projects_file"
echo ""
echo "DEBUG: Starting while loop..."

current=0

while IFS='|' read -r id path clone_url branch || [[ -n "$id" ]]; do
  [[ -z "$id" ]] && continue
  current=$((current + 1))
  echo "DEBUG: Loop iteration $current: id=$id"
  project_dir="$DEST_DIR/$path"
  
  echo "[$current/$total_projects] $path"
  
  if [[ -d "$project_dir" ]]; then
    echo "  ⚠️  Bỏ qua (đã tồn tại)"
    total_skipped=$((total_skipped + 1))
    continue
  fi
  
  mkdir -p "$(dirname "$project_dir")"
  
  if [[ "$MODE" == "Full Clone (với git history)" ]]; then
    # Debug: Show clone URL
    echo "  🔗 URL: $clone_url"
    
    # Test SSH connection first
    if [[ "$clone_url" =~ ssh://git@([^:]+):([0-9]+) ]]; then
      ssh_host="${BASH_REMATCH[1]}"
      ssh_port="${BASH_REMATCH[2]}"
      echo "  🔍 Testing SSH: $ssh_host:$ssh_port"
      
      # Quick SSH test (timeout 5s)
      if timeout 5 ssh -p "$ssh_port" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "git@$ssh_host" 2>&1 | grep -q "successfully authenticated\|Welcome\|Hi"; then
        echo "  ✅ SSH OK"
      else
        echo "  ⚠️  SSH connection may have issues"
      fi
    fi
    
    # Clone with timeout and error output
    echo "  🔄 Cloning..."
    clone_output=$(timeout 300 git clone "$clone_url" "$project_dir" 2>&1)
    clone_status=$?
    
    if [[ $clone_status -eq 0 ]]; then
      echo "  ✅ Cloned"
      total_success=$((total_success + 1))
    elif [[ $clone_status -eq 124 ]]; then
      echo "  ❌ Timeout (>5 minutes)"
      rm -rf "$project_dir"
      total_failed=$((total_failed + 1))
    else
      error_msg=$(echo "$clone_output" | grep -i "error\|fatal\|permission denied\|connection" | head -1)
      echo "  ❌ Failed: ${error_msg:-Unknown error}"
      rm -rf "$project_dir"
      total_failed=$((total_failed + 1))
    fi
  else
    # URL encode the project ID (replace / with %2F)
    encoded_id=$(echo "$id" | sed 's/\//%2F/g')
    archive_url="$GITLAB_URL/api/v4/projects/$encoded_id/repository/archive.tar.gz?sha=$branch"
    mkdir -p "$project_dir"
    
    # Download and extract directly (don't capture binary data)
    if curl -s --fail --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$archive_url" | \
       tar xzf - -C "$project_dir" --strip-components=1 2>/dev/null; then
      # Check if any files were extracted
      file_count=$(find "$project_dir" -type f 2>/dev/null | wc -l)
      if [[ $file_count -gt 0 ]]; then
        echo "  ✅ Downloaded ($file_count files)"
        total_success=$((total_success + 1))
      else
        echo "  ⚠️  Empty repo"
        rm -rf "$project_dir"
        total_skipped=$((total_skipped + 1))
      fi
    else
      echo "  ❌ Failed (check token/permissions)"
      rm -rf "$project_dir"
      total_failed=$((total_failed + 1))
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
