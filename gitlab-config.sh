#!/bin/bash

GITLAB_CONFIG_DIR="${HOME}/.config/gitlabdowloadtool"
GITLAB_TOKEN_FILE="$GITLAB_CONFIG_DIR/gitlab-tokens.json"
GITLAB_URL_FILE="$GITLAB_CONFIG_DIR/gitlab-url.txt"

GITLAB_LEGACY_TOKEN_FILE="${HOME}/.gitlab-tokens.json"
GITLAB_LEGACY_URL_FILE="${HOME}/.gitlab-url.txt"

gitlab_config_token_file_is_valid() {
  [[ -f "$1" ]] || return 1
  jq -e -s 'length == 1 and (.[0] | type == "object")' "$1" > /dev/null 2>&1
}

gitlab_config_atomic_save() {
  local target_file=$1
  local content=$2
  local target_dir
  local temp_file

  umask 077
  target_dir=$(dirname -- "$target_file")
  mkdir -p -- "$target_dir"
  chmod 700 -- "$target_dir"

  temp_file=$(mktemp "$target_dir/.gitlab-config.XXXXXX") || return 1
  chmod 600 -- "$temp_file"

  if ! printf '%s' "$content" > "$temp_file"; then
    rm -f -- "$temp_file"
    return 1
  fi

  chmod 600 -- "$temp_file"
  if ! mv -f -- "$temp_file" "$target_file"; then
    rm -f -- "$temp_file"
    return 1
  fi

  chmod 600 -- "$target_file"
}

gitlab_config_save_tokens() {
  local tokens=$1
  local normalized_tokens

  if ! normalized_tokens=$(printf '%s' "$tokens" | jq -c -s '
    if (length == 1) and ((.[0] | type) == "object") then .[0]
    else error("GitLab token config must be a JSON object")
    end
  '); then
    return 1
  fi

  gitlab_config_atomic_save "$GITLAB_TOKEN_FILE" "$normalized_tokens"
}

gitlab_config_save_url() {
  gitlab_config_atomic_save "$GITLAB_URL_FILE" "$1"
}

gitlab_config_init() {
  local legacy_tokens
  local legacy_url

  umask 077
  mkdir -p -- "$GITLAB_CONFIG_DIR"
  chmod 700 -- "$GITLAB_CONFIG_DIR"

  if [[ -e "$GITLAB_TOKEN_FILE" || -L "$GITLAB_TOKEN_FILE" ]]; then
    if ! gitlab_config_token_file_is_valid "$GITLAB_TOKEN_FILE"; then
      printf 'Error: GitLab token config must be a JSON object: %s\n' "$GITLAB_TOKEN_FILE" >&2
      return 1
    fi
    chmod 600 -- "$GITLAB_TOKEN_FILE"
  else
    if gitlab_config_token_file_is_valid "$GITLAB_LEGACY_TOKEN_FILE"; then
      legacy_tokens=$(<"$GITLAB_LEGACY_TOKEN_FILE")
      gitlab_config_save_tokens "$legacy_tokens"
    else
      gitlab_config_save_tokens '{}'
    fi
  fi

  if [[ ! -e "$GITLAB_URL_FILE" && -f "$GITLAB_LEGACY_URL_FILE" ]]; then
    legacy_url=$(<"$GITLAB_LEGACY_URL_FILE")
    gitlab_config_save_url "$legacy_url"
  elif [[ -e "$GITLAB_URL_FILE" ]]; then
    chmod 600 -- "$GITLAB_URL_FILE"
  fi
}
