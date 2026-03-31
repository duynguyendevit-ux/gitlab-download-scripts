#!/bin/bash

# 🔑 GitLab Token Manager

set -euo pipefail

TOKEN_FILE="$HOME/.gitlab-tokens.json"

if [[ ! -f "$TOKEN_FILE" ]]; then
  gum style --foreground 11 "⚠️  Chưa có token nào được lưu"
  exit 0
fi

gum style --border double --padding "1" --margin "1" \
  --border-foreground 33 --foreground 15 \
  "🔑 GitLab Token Manager"

# Load tokens
saved_tokens=$(cat "$TOKEN_FILE")
token_count=$(echo "$saved_tokens" | jq 'length')

gum style --foreground 14 "📊 Có $token_count token(s) đã lưu"

# List tokens
echo "$saved_tokens" | jq -r 'keys[]' | while read -r url; do
  token=$(echo "$saved_tokens" | jq -r --arg url "$url" '.[$url]')
  masked_token="${token:0:10}...${token: -4}"
  gum style --foreground 49 "  • $url: $masked_token"
done

echo ""

# Actions
action=$(gum choose "Xóa token" "Xóa tất cả" "Thoát")

case "$action" in
  "Xóa token")
    url_to_delete=$(echo "$saved_tokens" | jq -r 'keys[]' | gum choose)
    saved_tokens=$(echo "$saved_tokens" | jq --arg url "$url_to_delete" 'del(.[$url])')
    echo "$saved_tokens" > "$TOKEN_FILE"
    gum style --foreground 49 "✅ Đã xóa token cho $url_to_delete"
    ;;
  "Xóa tất cả")
    confirm=$(gum choose "Xác nhận xóa tất cả" "Hủy")
    if [[ "$confirm" == "Xác nhận xóa tất cả" ]]; then
      rm "$TOKEN_FILE"
      gum style --foreground 49 "✅ Đã xóa tất cả tokens"
    fi
    ;;
  "Thoát")
    exit 0
    ;;
esac
