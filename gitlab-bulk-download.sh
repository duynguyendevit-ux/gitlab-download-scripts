#!/bin/bash

# 🎯 GitLab Bulk Clone/Download Tool (Fixed v3)

set -euo pipefail

# Trap để debug
trap 'echo "ERROR: Script exited at line $LINENO"' ERR
trap 'echo "Script interrupted"' INT TERM

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gitlab-config.sh
source "$SCRIPT_DIR/gitlab-config.sh"

usage() {
  cat <<'EOF'
Usage:
  ./gitlab-bulk-download.sh
  ./gitlab-bulk-download.sh --ref-list <file>
  cat refs.txt | ./gitlab-bulk-download.sh --ref-list -

Ref-list format:
  project/path:git-ref
  project/path:tag@tag-name
  project/path:commit@abcdef1

The ref-list mode resolves and checks out the requested tag or commit over SSH,
then exports source below ./gitlab-repos/<resolved/project/path>.
EOF
}

REF_LIST_FILE=""
REF_LIST_FROM_STDIN=0
REF_LIST_TEMP=""
REF_TEMP_ROOT=""
ACTIVE_ITEM_TMP=""
MANIFEST_PATHS=()
MANIFEST_REFS=()
MANIFEST_CONFLICT_PATHS=()
MANIFEST_CONFLICT_REFS=()

cleanup_ref_temps() {
  if [[ -n "$ACTIVE_ITEM_TMP" ]]; then
    rm -rf -- "$ACTIVE_ITEM_TMP" 2>/dev/null || true
    ACTIVE_ITEM_TMP=""
  fi
  if [[ -n "$REF_TEMP_ROOT" ]]; then
    rm -rf -- "$REF_TEMP_ROOT" 2>/dev/null || true
    REF_TEMP_ROOT=""
  fi
  if [[ -n "$REF_LIST_TEMP" && -f "$REF_LIST_TEMP" ]]; then
    rm -f -- "$REF_LIST_TEMP" 2>/dev/null || true
    REF_LIST_TEMP=""
  fi
}

handle_ref_signal() {
  local exit_code=$1
  cleanup_ref_temps
  trap - EXIT INT TERM
  exit "$exit_code"
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --ref-list)
      if [[ $# -ne 2 || -z "$2" ]]; then
        usage >&2
        exit 2
      fi
      REF_LIST_FILE="$2"
      if [[ "$REF_LIST_FILE" == "-" ]]; then
        REF_LIST_FROM_STDIN=1
      elif [[ ! -r "$REF_LIST_FILE" ]]; then
        echo "Ref-list file is not readable: $REF_LIST_FILE" >&2
        exit 2
      fi
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
fi

if [[ -n "$REF_LIST_FILE" ]]; then
  trap cleanup_ref_temps EXIT
  trap 'handle_ref_signal 130' INT
  trap 'handle_ref_signal 143' TERM
fi

gitlab_config_init
CONFIG_DIR="$GITLAB_CONFIG_DIR"
TOKEN_FILE="$CONFIG_DIR/gitlab-tokens.json"
URL_FILE="$CONFIG_DIR/gitlab-url.txt"

if [[ "$REF_LIST_FROM_STDIN" -eq 1 ]]; then
  REF_LIST_TEMP=$(mktemp "${TMPDIR:-/tmp}/gitlab-ref-list.XXXXXX")
  cat > "$REF_LIST_TEMP"
  REF_LIST_FILE="$REF_LIST_TEMP"
fi

gum_choose() {
  if [[ "$REF_LIST_FROM_STDIN" -eq 1 ]]; then
    gum choose "$@" </dev/tty
  else
    gum choose "$@"
  fi
}

gum_input() {
  if [[ "$REF_LIST_FROM_STDIN" -eq 1 ]]; then
    gum input "$@" </dev/tty
  else
    gum input "$@"
  fi
}

trim_whitespace() {
  printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

urlencode() {
  printf '%s' "$1" | jq -sRr @uri
}

is_safe_project_path() {
  local project_path=$1
  local path_segment
  local -a path_segments

  [[ -n "$project_path" && "$project_path" != /* ]] || return 1
  IFS='/' read -r -a path_segments <<< "$project_path"
  for path_segment in "${path_segments[@]}"; do
    [[ "$path_segment" == "." || "$path_segment" == ".." ]] && return 1
  done
  return 0
}

destination_has_symlink_ancestor() {
  local project_path=$1
  local ancestor="$DEST_DIR"
  local path_segment
  local -a path_segments

  [[ -L "$ancestor" ]] && return 0
  IFS='/' read -r -a path_segments <<< "$project_path"
  for path_segment in "${path_segments[@]}"; do
    ancestor="$ancestor/$path_segment"
    [[ -L "$ancestor" ]] && return 0
  done
  return 1
}

clear_active_item_temp() {
  if [[ -n "$ACTIVE_ITEM_TMP" ]]; then
    rm -rf -- "$ACTIVE_ITEM_TMP" 2>/dev/null || true
    ACTIVE_ITEM_TMP=""
  fi
}

manifest_path_is_recorded() {
  local project_path=$1
  local existing

  for existing in "${MANIFEST_PATHS[@]}"; do
    [[ "$existing" == "$project_path" ]] && return 0
  done
  return 1
}

remove_manifest_path() {
  local project_path=$1
  local index
  local -a kept_paths=()
  local -a kept_refs=()

  for index in "${!MANIFEST_PATHS[@]}"; do
    if [[ "${MANIFEST_PATHS[$index]}" != "$project_path" ]]; then
      kept_paths+=("${MANIFEST_PATHS[$index]}")
      kept_refs+=("${MANIFEST_REFS[$index]}")
    fi
  done
  MANIFEST_PATHS=("${kept_paths[@]}")
  MANIFEST_REFS=("${kept_refs[@]}")
}

check_manifest_identity() {
  local project_path=$1
  local identity=$2
  local index

  MANIFEST_CONFLICT_EXISTING_REF=""
  for index in "${!MANIFEST_CONFLICT_PATHS[@]}"; do
    if [[ "${MANIFEST_CONFLICT_PATHS[$index]}" == "$project_path" ]]; then
      MANIFEST_CONFLICT_EXISTING_REF="${MANIFEST_CONFLICT_REFS[$index]}"
      return 2
    fi
  done

  if ! manifest_path_is_recorded "$project_path"; then
    return 1
  fi
  for index in "${!MANIFEST_PATHS[@]}"; do
    if [[ "${MANIFEST_PATHS[$index]}" == "$project_path" ]]; then
      if [[ "${MANIFEST_REFS[$index]}" == "$identity" ]]; then
        return 0
      fi
      MANIFEST_CONFLICT_EXISTING_REF="${MANIFEST_REFS[$index]}"
      remove_manifest_path "$project_path"
      MANIFEST_CONFLICT_PATHS+=("$project_path")
      MANIFEST_CONFLICT_REFS+=("$MANIFEST_CONFLICT_EXISTING_REF")
      return 2
    fi
  done
  return 1
}

append_manifest_path() {
  local project_path=$1
  local identity=$2
  local duplicate_status=0

  is_safe_project_path "$project_path" || return 1
  check_manifest_identity "$project_path" "$identity" || duplicate_status=$?
  if [[ "$duplicate_status" -eq 0 ]]; then
    return 0
  fi
  [[ "$duplicate_status" -eq 2 ]] && return 2
  MANIFEST_PATHS+=("$project_path")
  MANIFEST_REFS+=("$identity")
}

publish_ref_manifest() {
  local manifest_stage="$REF_TEMP_ROOT/.gitlab-ref-projects.txt"
  local manifest_target="$DEST_DIR/.gitlab-ref-projects.txt"
  local project_path

  : > "$manifest_stage"
  for project_path in "${MANIFEST_PATHS[@]}"; do
    printf '%s\n' "$project_path" >> "$manifest_stage"
  done
  chmod 600 "$manifest_stage"
  mv -f "$manifest_stage" "$manifest_target"
}

install_ref_destination() {
  local source_dir=$1
  local destination_parent=$2
  local destination=$3

  if [[ -e "$destination" || -L "$destination" ]]; then
    return 2
  fi

  if ! mv -n "$source_dir" "$destination_parent/"; then
    return 1
  fi

  if [[ -e "$source_dir" || -L "$source_dir" ]]; then
    if [[ -e "$destination" || -L "$destination" ]]; then
      return 2
    fi
    return 1
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    return 0
  fi
  return 1
}

add_unique_candidate_path() {
  local candidate=$1
  local existing

  [[ -n "$candidate" ]] || return 0
  for existing in "${CANDIDATE_PATHS[@]}"; do
    [[ "$existing" == "$candidate" ]] && return 0
  done
  CANDIDATE_PATHS+=("$candidate")
}

build_project_candidates() {
  local input_path=$1
  local base variant
  local pass index count

  CANDIDATE_PATHS=()
  add_unique_candidate_path "$input_path"
  if [[ "$input_path" == ots/apps/* ]]; then
    add_unique_candidate_path "${input_path#ots/apps/}"
  fi
  if [[ "$input_path" == ots/* ]]; then
    add_unique_candidate_path "${input_path#ots/}"
  fi

  for pass in 1 2; do
    count=${#CANDIDATE_PATHS[@]}
    for ((index = 0; index < count; index++)); do
      base=${CANDIDATE_PATHS[$index]}
      if [[ "$base" == ttdvkh/* ]]; then
        add_unique_candidate_path "c7-ttdvkh/${base#ttdvkh/}"
      fi
      if [[ "$base" == notification/* ]]; then
        add_unique_candidate_path "notifications/${base#notification/}"
      elif [[ "$base" == */notification/* ]]; then
        variant=${base//\/notification\//\/notifications\/}
        add_unique_candidate_path "$variant"
      fi
    done
  done
}

add_unique_resolution_candidate() {
  local candidate=$1
  local existing

  [[ -n "$candidate" ]] || return 0
  for existing in "${RESOLUTION_CANDIDATES[@]}"; do
    [[ "$existing" == "$candidate" ]] && return 0
  done
  RESOLUTION_CANDIDATES+=("$candidate")
}

add_unique_project_pair() {
  local project_path=$1
  local ssh_url=$2
  local index

  for index in "${!PROJECT_PATHS[@]}"; do
    [[ "${PROJECT_PATHS[$index]}" == "$project_path" ]] && return 0
  done
  PROJECT_PATHS+=("$project_path")
  PROJECT_SSH_URLS+=("$ssh_url")
}

add_unique_match_pair() {
  local project_path=$1
  local ssh_url=$2
  local checkout_ref=$3
  local index

  for index in "${!MATCH_PATHS[@]}"; do
    [[ "${MATCH_PATHS[$index]}" == "$project_path" ]] && return 0
  done
  MATCH_PATHS+=("$project_path")
  MATCH_SSH_URLS+=("$ssh_url")
  MATCH_REFS+=("$checkout_ref")
}

resolution_candidate_summary() {
  local IFS=', '

  if [[ ${#RESOLUTION_CANDIDATES[@]} -gt 0 ]]; then
    printf '%s' "${RESOLUTION_CANDIDATES[*]}"
  else
    printf '%s' "none"
  fi
}

api_get() {
  local url=$1
  local response_file=$2
  shift 2

  API_HTTP_STATUS=""
  if ! API_HTTP_STATUS=$(curl -sS --config "$CURL_CONFIG_FILE" "$@" \
    --output "$response_file" --write-out '%{http_code}' "$url"); then
    return 1
  fi
  [[ "$API_HTTP_STATUS" =~ ^[0-9]{3}$ ]]
}

verify_project_ref() {
  local project_path=$1
  local ref_kind=$2
  local git_ref=$3
  local encoded_project encoded_ref ref_url
  local canonical_ref

  VERIFIED_CHECKOUT_REF=""

  if ! encoded_project=$(urlencode "$project_path") || ! encoded_ref=$(urlencode "$git_ref"); then
    return 2
  fi
  if [[ "$ref_kind" == "tag" ]]; then
    ref_url="$GITLAB_URL/api/v4/projects/$encoded_project/repository/tags/$encoded_ref"
  else
    ref_url="$GITLAB_URL/api/v4/projects/$encoded_project/repository/commits/$encoded_ref"
  fi

  if ! api_get "$ref_url" "$ACTIVE_ITEM_TMP/api-response.json"; then
    return 2
  fi
  case "$API_HTTP_STATUS" in
    200)
      if [[ "$ref_kind" == "commit" ]]; then
        if ! canonical_ref=$(jq -r '.id // empty' "$ACTIVE_ITEM_TMP/api-response.json") || \
          [[ ! "$canonical_ref" =~ ^[0-9A-Fa-f]{40}$ ]]; then
          return 2
        fi
        VERIFIED_CHECKOUT_REF="$canonical_ref"
      else
        VERIFIED_CHECKOUT_REF="$git_ref"
      fi
      return 0
      ;;
    404) return 1 ;;
    *) return 2 ;;
  esac
}

resolve_project_for_ref() {
  local input_path=$1
  local ref_kind=$2
  local git_ref=$3
  local candidate encoded_candidate project_url project_path ssh_url
  local search_term search_url response_file
  local exact_projects_found=0
  local api_errors=0
  local verify_status
  local search_page page_count
  local -a search_terms=()
  local -a search_paths=()
  local -a search_ssh_urls=()
  local index

  RESOLVED_PATH=""
  RESOLVED_SSH_URL=""
  RESOLVED_CHECKOUT_REF=""
  RESOLUTION_REASON=""
  RESOLUTION_CANDIDATES=()
  PROJECT_PATHS=()
  PROJECT_SSH_URLS=()
  MATCH_PATHS=()
  MATCH_SSH_URLS=()
  MATCH_REFS=()

  build_project_candidates "$input_path"
  for candidate in "${CANDIDATE_PATHS[@]}"; do
    add_unique_resolution_candidate "$candidate"
    if ! encoded_candidate=$(urlencode "$candidate"); then
      api_errors=$((api_errors + 1))
      continue
    fi
    project_url="$GITLAB_URL/api/v4/projects/$encoded_candidate"
    response_file="$ACTIVE_ITEM_TMP/project-response.json"
    if ! api_get "$project_url" "$response_file"; then
      api_errors=$((api_errors + 1))
      continue
    fi
    [[ "$API_HTTP_STATUS" == "404" ]] && continue
    if [[ "$API_HTTP_STATUS" != "200" ]]; then
      api_errors=$((api_errors + 1))
      continue
    fi

    if ! project_path=$(jq -r '.path_with_namespace // empty' "$response_file") || \
      ! ssh_url=$(jq -r '.ssh_url_to_repo // empty' "$response_file"); then
      api_errors=$((api_errors + 1))
      continue
    fi
    if [[ -n "$project_path" && -n "$ssh_url" ]]; then
      add_unique_project_pair "$project_path" "$ssh_url"
      exact_projects_found=1
    else
      api_errors=$((api_errors + 1))
    fi
  done

  if [[ "$exact_projects_found" -eq 1 ]]; then
    for index in "${!PROJECT_PATHS[@]}"; do
      if verify_project_ref "${PROJECT_PATHS[$index]}" "$ref_kind" "$git_ref"; then
        add_unique_match_pair "${PROJECT_PATHS[$index]}" "${PROJECT_SSH_URLS[$index]}" "$VERIFIED_CHECKOUT_REF"
      else
        verify_status=$?
        [[ "$verify_status" -eq 2 ]] && api_errors=$((api_errors + 1))
      fi
    done
    if [[ ${#MATCH_PATHS[@]} -eq 1 && "$api_errors" -eq 0 ]]; then
      RESOLVED_PATH=${MATCH_PATHS[0]}
      RESOLVED_SSH_URL=${MATCH_SSH_URLS[0]}
      RESOLVED_CHECKOUT_REF=${MATCH_REFS[0]}
      return 0
    fi
    if [[ "$api_errors" -gt 0 ]]; then
      RESOLUTION_REASON="incomplete verification: API/transport/429/5xx errors occurred while checking exact candidates; candidates: $(resolution_candidate_summary)"
    elif [[ ${#MATCH_PATHS[@]} -gt 1 ]]; then
      local IFS=', '
      RESOLUTION_REASON="ambiguous exact candidates contain $ref_kind '$git_ref': ${MATCH_PATHS[*]}"
    else
      RESOLUTION_REASON="exact project candidates were found, but none contains $ref_kind '$git_ref'; candidates: $(resolution_candidate_summary)"
    fi
    return 1
  fi

  search_terms+=("$(basename "$input_path")")
  if [[ "${search_terms[0]}" == *-service && ${#search_terms[0]} -gt 8 ]]; then
    search_terms+=("${search_terms[0]%-service}")
  fi

  for search_term in "${search_terms[@]}"; do
    search_url="$GITLAB_URL/api/v4/projects"
    search_page=1
    while true; do
      response_file="$ACTIVE_ITEM_TMP/search-response.json"
      if ! api_get "$search_url" "$response_file" \
        --get --data-urlencode "search=$search_term" \
        --data-urlencode "per_page=100" --data-urlencode "page=$search_page"; then
        api_errors=$((api_errors + 1))
        break
      fi
      if [[ "$API_HTTP_STATUS" == "404" ]]; then
        break
      fi
      if [[ "$API_HTTP_STATUS" != "200" ]]; then
        api_errors=$((api_errors + 1))
        break
      fi
      if ! page_count=$(jq -er 'if type == "array" then length else error("search response is not an array") end' "$response_file"); then
        api_errors=$((api_errors + 1))
        break
      fi
      while IFS=$'\t' read -r project_path ssh_url; do
        [[ -n "$project_path" && -n "$ssh_url" ]] || continue
        add_unique_resolution_candidate "$project_path"
        local already_seen=0
        for index in "${!search_paths[@]}"; do
          if [[ "${search_paths[$index]}" == "$project_path" ]]; then
            already_seen=1
            break
          fi
        done
        if [[ "$already_seen" -eq 0 ]]; then
          search_paths+=("$project_path")
          search_ssh_urls+=("$ssh_url")
        fi
      done < <(jq -r '.[] | select(.path_with_namespace and .ssh_url_to_repo) | [.path_with_namespace, .ssh_url_to_repo] | @tsv' "$response_file")
      if [[ "$page_count" -lt 100 ]]; then
        break
      fi
      search_page=$((search_page + 1))
    done

    MATCH_PATHS=()
    MATCH_SSH_URLS=()
    MATCH_REFS=()
    for index in "${!search_paths[@]}"; do
      if verify_project_ref "${search_paths[$index]}" "$ref_kind" "$git_ref"; then
        add_unique_match_pair "${search_paths[$index]}" "${search_ssh_urls[$index]}" "$VERIFIED_CHECKOUT_REF"
      else
        verify_status=$?
        [[ "$verify_status" -eq 2 ]] && api_errors=$((api_errors + 1))
      fi
    done
    if [[ ${#MATCH_PATHS[@]} -eq 1 && "$api_errors" -eq 0 ]]; then
      RESOLVED_PATH=${MATCH_PATHS[0]}
      RESOLVED_SSH_URL=${MATCH_SSH_URLS[0]}
      RESOLVED_CHECKOUT_REF=${MATCH_REFS[0]}
      return 0
    fi
    if [[ "$api_errors" -gt 0 ]]; then
      RESOLUTION_REASON="incomplete verification: API/transport/429/5xx errors occurred while checking search pages/ref candidates; candidates: $(resolution_candidate_summary)"
      return 1
    fi
    if [[ ${#MATCH_PATHS[@]} -gt 1 ]]; then
      local IFS=', '
      RESOLUTION_REASON="ambiguous search candidates contain $ref_kind '$git_ref': ${MATCH_PATHS[*]}"
      return 1
    fi
  done

  if [[ "$api_errors" -gt 0 ]]; then
    RESOLUTION_REASON="incomplete verification: API/transport/429/5xx errors occurred; candidates checked: $(resolution_candidate_summary)"
  else
    RESOLUTION_REASON="no unique project candidate contains $ref_kind '$git_ref'; candidates checked: $(resolution_candidate_summary)"
  fi
  return 1
}

checkout_ref_with_ssh() {
  local checkout_dir=$1
  local ssh_url=$2
  local ref_kind=$3
  local git_ref=$4
  local expected_head actual_head

  if [[ "$ref_kind" == "tag" ]]; then
    git clone --depth 1 --single-branch --branch "$git_ref" "$ssh_url" "$checkout_dir" || return 1
    expected_head=$(git -C "$checkout_dir" rev-parse "refs/tags/$git_ref^{commit}") || return 1
  else
    git init "$checkout_dir" || return 1
    git -C "$checkout_dir" remote add origin "$ssh_url" || return 1
    git -C "$checkout_dir" fetch --depth 1 origin "$git_ref" || return 1
    git -C "$checkout_dir" checkout --detach FETCH_HEAD || return 1
    expected_head=$(git -C "$checkout_dir" rev-parse FETCH_HEAD) || return 1
  fi
  actual_head=$(git -C "$checkout_dir" rev-parse HEAD) || return 1
  [[ "$actual_head" == "$expected_head" ]]
}

export_checked_out_source() {
  local checkout_dir=$1
  local extract_dir=$2

  git -C "$checkout_dir" archive --format=tar HEAD | tar -xf - -C "$extract_dir"
  [[ ! -e "$extract_dir/.git" && ! -L "$extract_dir/.git" ]]
}

download_ref_list() {
  local ref_list_path=$1
  local raw_line line project_path ref_spec git_ref ref_kind
  local project_dir destination_parent project_basename extract_dir checkout_dir file_count
  local curl_config_file escaped_token
  local manifest_identity duplicate_status record_status
  local total_items=0 total_success=0 total_skipped=0 total_failed=0
  local manifest_target="$DEST_DIR/.gitlab-ref-projects.txt"
  local manifest_publish_failed=0

  if [[ ! -r "$ref_list_path" ]]; then
    echo "Ref-list file is not readable: $ref_list_path" >&2
    return 1
  fi

  echo "🚀 Downloading requested refs..."
  MANIFEST_PATHS=()
  MANIFEST_REFS=()
  MANIFEST_CONFLICT_PATHS=()
  MANIFEST_CONFLICT_REFS=()

  if [[ -L "$DEST_DIR" ]]; then
    echo "❌ Ref-list destination is a symlink: $DEST_DIR" >&2
    return 1
  fi
  if ! REF_TEMP_ROOT=$(mktemp -d "$DEST_DIR/.gitlab-bulk-download.XXXXXX"); then
    echo "❌ Could not create ref-list staging directory inside $DEST_DIR" >&2
    return 1
  fi
  if [[ "$GITLAB_TOKEN" == *$'\n'* || "$GITLAB_TOKEN" == *$'\r'* ]]; then
    echo "❌ Ref-list token contains a newline" >&2
    return 1
  fi

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line=${raw_line%$'\r'}
    line=$(trim_whitespace "$line")
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    total_items=$((total_items + 1))
    if [[ "$line" != *:* ]]; then
      echo "[$total_items] ❌ Invalid entry (expected project_path:git_ref)"
      total_failed=$((total_failed + 1))
      continue
    fi

    project_path=$(trim_whitespace "${line%:*}")
    ref_spec=$(trim_whitespace "${line##*:}")
    if [[ -z "$project_path" || -z "$ref_spec" ]] || ! is_safe_project_path "$project_path"; then
      echo "[$total_items] ❌ Invalid entry: $line"
      total_failed=$((total_failed + 1))
      continue
    fi

    case "$ref_spec" in
      tag@*)
        ref_kind="tag"
        git_ref=${ref_spec#tag@}
        ;;
      commit@*)
        ref_kind="commit"
        git_ref=${ref_spec#commit@}
        if [[ ! "$git_ref" =~ ^[0-9A-Fa-f]{7,40}$ ]]; then
          echo "[$total_items] ❌ Invalid commit ref: $ref_spec"
          total_failed=$((total_failed + 1))
          continue
        fi
        ;;
      *)
        git_ref="$ref_spec"
        if [[ "$git_ref" =~ ^[0-9A-Fa-f]{7,40}$ ]]; then
          ref_kind="commit"
        else
          ref_kind="tag"
        fi
        ;;
    esac
    if [[ -z "$git_ref" ]]; then
      echo "[$total_items] ❌ Invalid ref: $ref_spec"
      total_failed=$((total_failed + 1))
      continue
    fi
    echo "[$total_items] $project_path:$ref_spec ($ref_kind)"

    if ! ACTIVE_ITEM_TMP=$(mktemp -d "$REF_TEMP_ROOT/item.XXXXXX"); then
      echo "  ❌ Failed (could not create item staging directory)"
      total_failed=$((total_failed + 1))
      continue
    fi
    curl_config_file="$ACTIVE_ITEM_TMP/curl.conf"
    CURL_CONFIG_FILE="$curl_config_file"
    escaped_token=${GITLAB_TOKEN//\\/\\\\}
    escaped_token=${escaped_token//\"/\\\"}
    if ! printf 'header = "PRIVATE-TOKEN: %s"\n' "$escaped_token" > "$curl_config_file"; then
      echo "  ❌ Failed (could not create curl config)"
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi
    chmod 600 "$curl_config_file"

    if ! resolve_project_for_ref "$project_path" "$ref_kind" "$git_ref"; then
      echo "  ❌ Could not resolve project/ref: $RESOLUTION_REASON"
      echo "  ℹ️  Use an exact GitLab path or explicit tag@/commit@ ref; resolve API/network errors before retrying."
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi

    if ! is_safe_project_path "$RESOLVED_PATH"; then
      echo "  ❌ Failed (GitLab returned an unsafe project path)"
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi

    manifest_identity="$ref_kind:$RESOLVED_CHECKOUT_REF"
    project_dir="$DEST_DIR/$RESOLVED_PATH"
    destination_parent=$(dirname "$project_dir")
    project_basename=$(basename "$project_dir")
    echo "  ↪ Resolved project: $RESOLVED_PATH"

    if destination_has_symlink_ancestor "$RESOLVED_PATH"; then
      echo "  ❌ Failed (destination path contains a symlink)"
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi
    duplicate_status=0
    check_manifest_identity "$RESOLVED_PATH" "$manifest_identity" || duplicate_status=$?
    if [[ "$duplicate_status" -eq 2 ]]; then
      echo "  ❌ Conflicting duplicate: resolved path '$RESOLVED_PATH' was already recorded as '${MANIFEST_CONFLICT_EXISTING_REF}', but this item requests '$manifest_identity'; path excluded from manifest"
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi
    if [[ -e "$project_dir" || -L "$project_dir" ]]; then
      if [[ "$duplicate_status" -eq 0 ]]; then
        echo "  ⚠️  Skipped (destination already exists; already recorded from a successful install in this run: $project_dir)"
      else
        echo "  ⚠️  Skipped (destination already exists; excluded from manifest because the requested revision is unverified: $project_dir)"
      fi
      clear_active_item_temp
      total_skipped=$((total_skipped + 1))
      continue
    fi

    if ! mkdir -p "$(dirname "$project_dir")"; then
      echo "  ❌ Failed (could not create destination parent)"
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi
    if destination_has_symlink_ancestor "$RESOLVED_PATH"; then
      echo "  ❌ Failed (destination path contains a symlink)"
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi

    checkout_dir="$ACTIVE_ITEM_TMP/checkout"
    extract_dir="$ACTIVE_ITEM_TMP/$project_basename"
    mkdir "$extract_dir"
    if ! checkout_ref_with_ssh "$checkout_dir" "$RESOLVED_SSH_URL" "$ref_kind" "$RESOLVED_CHECKOUT_REF"; then
      echo "  ❌ Failed (SSH checkout of $ref_kind '$git_ref')"
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi
    if ! export_checked_out_source "$checkout_dir" "$extract_dir"; then
      echo "  ❌ Failed (git archive export)"
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi
    if destination_has_symlink_ancestor "$RESOLVED_PATH"; then
      echo "  ❌ Failed (destination path contains a symlink)"
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi
    duplicate_status=0
    check_manifest_identity "$RESOLVED_PATH" "$manifest_identity" || duplicate_status=$?
    if [[ "$duplicate_status" -eq 2 ]]; then
      echo "  ❌ Conflicting duplicate: resolved path '$RESOLVED_PATH' was already recorded as '${MANIFEST_CONFLICT_EXISTING_REF}', but this item requests '$manifest_identity'; path excluded from manifest"
      clear_active_item_temp
      total_failed=$((total_failed + 1))
      continue
    fi
    if [[ -e "$project_dir" || -L "$project_dir" ]]; then
      if [[ "$duplicate_status" -eq 0 ]]; then
        echo "  ⚠️  Skipped (destination appeared before install; already recorded from a successful install in this run: $project_dir)"
      else
        echo "  ⚠️  Skipped (destination appeared before install; excluded from manifest because the requested revision is unverified: $project_dir)"
      fi
      clear_active_item_temp
      total_skipped=$((total_skipped + 1))
      continue
    fi

    if install_ref_destination "$extract_dir" "$destination_parent" "$project_dir"; then
      file_count=$(find "$project_dir" -type f 2>/dev/null | wc -l)
      record_status=0
      append_manifest_path "$RESOLVED_PATH" "$manifest_identity" || record_status=$?
      if [[ "$record_status" -eq 2 ]]; then
        echo "  ❌ Conflicting duplicate: resolved path '$RESOLVED_PATH' was already recorded as '${MANIFEST_CONFLICT_EXISTING_REF}', but this item requests '$manifest_identity'; path excluded from manifest"
        clear_active_item_temp
        total_failed=$((total_failed + 1))
        continue
      elif [[ "$record_status" -ne 0 ]]; then
        echo "  ❌ Failed (unsafe resolved path for manifest)"
        clear_active_item_temp
        total_failed=$((total_failed + 1))
        continue
      fi
      echo "  ✅ Downloaded ($file_count files)"
      total_success=$((total_success + 1))
    elif [[ -e "$project_dir" || -L "$project_dir" ]]; then
      duplicate_status=0
      check_manifest_identity "$RESOLVED_PATH" "$manifest_identity" || duplicate_status=$?
      if [[ "$duplicate_status" -eq 2 ]]; then
        echo "  ❌ Conflicting duplicate: resolved path '$RESOLVED_PATH' was already recorded as '${MANIFEST_CONFLICT_EXISTING_REF}', but this item requests '$manifest_identity'; path excluded from manifest"
        total_failed=$((total_failed + 1))
        clear_active_item_temp
        continue
      elif [[ "$duplicate_status" -eq 0 ]]; then
        echo "  ⚠️  Skipped (destination appeared during install; already recorded from a successful install in this run: $project_dir)"
      else
        echo "  ⚠️  Skipped (destination appeared during install; excluded from manifest because the requested revision is unverified: $project_dir)"
      fi
      total_skipped=$((total_skipped + 1))
    else
      echo "  ❌ Failed (could not install destination)"
      total_failed=$((total_failed + 1))
    fi
    clear_active_item_temp
  done < "$ref_list_path"

  if ! publish_ref_manifest; then
    echo "❌ Failed to publish ref-list manifest: $manifest_target" >&2
    manifest_publish_failed=1
    total_failed=$((total_failed + 1))
  fi

  echo ""
  echo "🎉 Ref-list download complete"
  echo "📊 Summary:"
  echo "  • Total: $total_items"
  echo "  • Downloaded: $total_success"
  echo "  • Skipped: $total_skipped"
  echo "  • Failed: $total_failed"
  echo "📁 Location: $DEST_DIR"
  echo "📜 Ref manifest: $manifest_target (${#MANIFEST_PATHS[@]} projects)"
  echo "  • Manifest includes successful installs from this run only; existing/race skips are excluded"

  [[ "$total_failed" -eq 0 && "$manifest_publish_failed" -eq 0 ]]
}

gum style --border double --padding "1" --margin "1" \
  --border-foreground 33 --foreground 15 \
  "📦 GitLab Bulk Clone/Download Tool"

[[ -f "$TOKEN_FILE" ]] && saved_tokens=$(cat "$TOKEN_FILE") || saved_tokens="{}"
[[ -f "$URL_FILE" ]] && saved_url=$(cat "$URL_FILE") || saved_url=""

gum style --foreground 33 "🔧 GitLab URL:"
if [[ -n "$saved_url" ]]; then
  gum style --foreground 14 "   Đã lưu: $saved_url"
  use_saved_url=$(gum_choose "Dùng URL đã lưu" "Nhập URL mới")
  if [[ "$use_saved_url" == "Dùng URL đã lưu" ]]; then
    GITLAB_URL="$saved_url"
  else
    GITLAB_URL=$(gum_input --placeholder "http://your-gitlab-host")
    [[ -z "$GITLAB_URL" ]] && { gum style --foreground 196 "❌ URL trống!"; exit 1; }
    gitlab_config_save_url "$GITLAB_URL"
  fi
else
  GITLAB_URL=$(gum_input --placeholder "http://your-gitlab-host")
  [[ -z "$GITLAB_URL" ]] && { gum style --foreground 196 "❌ URL trống!"; exit 1; }
  gitlab_config_save_url "$GITLAB_URL"
fi

saved_token=$(echo "$saved_tokens" | jq -r --arg url "$GITLAB_URL" '.[$url] // empty')

if [[ -n "$saved_token" ]]; then
  gum style --foreground 14 "🔑 Tìm thấy token đã lưu"
  use_saved=$(gum_choose "Dùng token đã lưu" "Nhập token mới")
  
  if [[ "$use_saved" == "Dùng token đã lưu" ]]; then
    GITLAB_TOKEN="$saved_token"
    gum style --foreground 49 "✅ Đang dùng token đã lưu"
  else
    GITLAB_TOKEN=$(gum_input --placeholder "Nhập GitLab Personal Access Token" --password)
    [[ -z "$GITLAB_TOKEN" ]] && { gum style --foreground 196 "❌ Token trống!"; exit 1; }
    saved_tokens=$(echo "$saved_tokens" | jq --arg url "$GITLAB_URL" --arg token "$GITLAB_TOKEN" '.[$url] = $token')
    gitlab_config_save_tokens "$saved_tokens"
    gum style --foreground 49 "✅ Đã lưu token mới"
  fi
else
  GITLAB_TOKEN=$(gum_input --placeholder "Nhập GitLab Personal Access Token" --password)
  [[ -z "$GITLAB_TOKEN" ]] && { gum style --foreground 196 "❌ Token trống!"; exit 1; }
  saved_tokens=$(echo "$saved_tokens" | jq --arg url "$GITLAB_URL" --arg token "$GITLAB_TOKEN" '.[$url] = $token')
  gitlab_config_save_tokens "$saved_tokens"
  gum style --foreground 49 "✅ Đã lưu token"
fi

# 📁 Thư mục đích (dùng thư mục hiện tại)
DEST_DIR="$(pwd)/gitlab-repos"
mkdir -p "$DEST_DIR"
gum style --foreground 49 "📁 Sẽ lưu vào: $DEST_DIR"

if [[ -n "$REF_LIST_FILE" ]]; then
  if download_ref_list "$REF_LIST_FILE"; then
    exit 0
  else
    exit 1
  fi
fi

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
