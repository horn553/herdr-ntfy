#!/bin/sh
set -eu

load_env() {
  local_env="${HERDR_PLUGIN_ROOT:-.}/.env"

  if [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ] && [ -f "$HERDR_PLUGIN_CONFIG_DIR/.env" ]; then
    # shellcheck disable=SC1090
    . "$HERDR_PLUGIN_CONFIG_DIR/.env"
  elif [ -f "$local_env" ]; then
    # shellcheck disable=SC1090
    . "$local_env"
  fi
}

json_value() {
  name="$1"
  json="${2:-}"
  query="$3"

  if [ -z "$json" ]; then
    return 0
  fi

  printf '%s' "$json" | jq -r "$query // empty" 2>/dev/null || {
    echo "failed to parse $name with jq" >&2
    return 1
  }
}

first_value() {
  for value in "$@"; do
    if [ -n "$value" ] && [ "$value" != "null" ]; then
      printf '%s' "$value"
      return 0
    fi
  done
}

clean_label() {
  label="$1"
  fallback="$2"

  label="$(printf '%s' "$label" | tr '\n\r\t' '   ' | sed 's/  */ /g; s/^ //; s/ $//')"
  if [ -n "$label" ]; then
    printf '%s' "$label"
  else
    printf '%s' "$fallback"
  fi
}

status_state_file() {
  pane_id="$1"

  if [ -z "$pane_id" ]; then
    return 0
  fi

  state_base="${HERDR_PLUGIN_CONFIG_DIR:-${HERDR_PLUGIN_ROOT:-.}}"
  state_dir="$state_base/.state"
  pane_key="$(printf '%s' "$pane_id" | cksum | sed 's/ /-/g')"

  printf '%s/%s.status' "$state_dir" "$pane_key"
}

read_previous_status() {
  state_file="$1"

  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    sed -n '1p' "$state_file"
  fi
}

remember_status() {
  state_file="$1"
  status="$2"

  if [ -z "$state_file" ]; then
    return 0
  fi

  state_dir="${state_file%/*}"
  state_tmp="${state_file}.$$"

  if ! mkdir -p "$state_dir"; then
    echo "failed to create status state directory: $state_dir" >&2
    return 0
  fi

  if ! printf '%s\n' "$status" >"$state_tmp"; then
    echo "failed to write status state: $state_tmp" >&2
    return 0
  fi

  if ! mv "$state_tmp" "$state_file"; then
    echo "failed to save status state: $state_file" >&2
    rm -f "$state_tmp"
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_http_url() {
  case "$1" in
    http://* | https://*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_positive_integer() {
  case "$1" in
    '' | *[!0-9]*)
      return 1
      ;;
    *)
      [ "$1" -gt 0 ]
      ;;
  esac
}

redact_url() {
  url="$1"

  case "$url" in
    http://*/* | https://*/*)
      base="${url%/*}"
      topic="${url##*/}"
      prefix="$(printf '%s' "$topic" | cut -c 1-6)"
      printf '%s/%s...' "$base" "$prefix"
      ;;
    *)
      printf '%s' "$url"
      ;;
  esac
}

url_encode() {
  printf '%s' "$1" | jq -sRr @uri
}

collie_click_url() {
  collie_url="$1"
  pane_id="$2"

  if [ -z "$collie_url" ] || [ -z "$pane_id" ]; then
    return 0
  fi

  if ! is_http_url "$collie_url"; then
    echo "invalid COLLIE_URL; expected http:// or https://" >&2
    return 0
  fi

  printf '%s/pane/%s' "${collie_url%/}" "$(url_encode "$pane_id")"
}

send_ntfy() {
  title="$1"
  body="$2"
  click_url="${3:-}"

  set -- -H "Title: $title" -H "Content-Type: text/plain; charset=utf-8"

  if [ -n "$click_url" ]; then
    set -- "$@" -H "Click: $click_url"
  fi

  if [ -n "${NTFY_TOKEN:-}" ]; then
    set -- "$@" -H "Authorization: Bearer $NTFY_TOKEN"
  fi

  printf '%s' "$body" | curl -fsS "$@" --data-binary @- "$ntfy_url"
}

dry_run() {
  load_env

  ok=1
  ntfy_url="${NTFY_URL:-}"
  ntfy_title="$(clean_label "${NTFY_TITLE:-Herdr}" "Herdr")"
  lines="${NTFY_LINES:-12}"

  echo "Herdr ntfy dry-run"
  echo

  if command_exists curl; then
    echo "curl: ok"
  else
    echo "curl: missing"
    ok=0
  fi

  if command_exists jq; then
    echo "jq: ok"
  else
    echo "jq: missing"
    ok=0
  fi

  if [ -n "$ntfy_url" ]; then
    if is_http_url "$ntfy_url"; then
      echo "NTFY_URL: ok ($(redact_url "$ntfy_url"))"
    else
      echo "NTFY_URL: invalid; expected http:// or https://"
      ok=0
    fi
  else
    echo "NTFY_URL: missing"
    ok=0
  fi

  echo "NTFY_TITLE: $ntfy_title"

  if [ -n "${NTFY_TOKEN:-}" ]; then
    echo "NTFY_TOKEN: set"
  else
    echo "NTFY_TOKEN: not set"
  fi

  if is_positive_integer "$lines"; then
    echo "NTFY_LINES: $lines"
  else
    echo "NTFY_LINES: invalid; expected a positive integer"
    ok=0
  fi

  collie_url="${COLLIE_URL:-}"
  if [ -n "$collie_url" ]; then
    if is_http_url "$collie_url"; then
      echo "COLLIE_URL: ok ($collie_url)"
    else
      echo "COLLIE_URL: invalid; expected http:// or https://"
      ok=0
    fi
  else
    echo "COLLIE_URL: not set (notifications will have no click action)"
  fi

  echo
  echo "Sample title:"
  echo "✅ verification・dry-run (${ntfy_title})"
  echo
  echo "Sample body:"
  echo "Herdr ntfy dry-run: no notification was sent."

  if [ -n "$collie_url" ] && is_http_url "$collie_url"; then
    echo
    echo "Sample click URL:"
    echo "$(collie_click_url "$collie_url" "wE:p1")"
  fi

  if [ "$ok" -eq 1 ]; then
    echo
    echo "Result: ok"
    return 0
  fi

  echo
  echo "Result: failed"
  return 1
}

test_notification() {
  load_env

  ok=1
  ntfy_url="${NTFY_URL:-}"
  ntfy_title="$(clean_label "${NTFY_TITLE:-Herdr}" "Herdr")"

  echo "Herdr ntfy test"
  echo

  if command_exists curl; then
    echo "curl: ok"
  else
    echo "curl: missing"
    ok=0
  fi

  if [ -n "$ntfy_url" ]; then
    if is_http_url "$ntfy_url"; then
      echo "NTFY_URL: ok ($(redact_url "$ntfy_url"))"
    else
      echo "NTFY_URL: invalid; expected http:// or https://"
      ok=0
    fi
  else
    echo "NTFY_URL: missing"
    ok=0
  fi

  echo "NTFY_TITLE: $ntfy_title"

  if [ -n "${NTFY_TOKEN:-}" ]; then
    echo "NTFY_TOKEN: set"
  else
    echo "NTFY_TOKEN: not set"
  fi

  collie_url="${COLLIE_URL:-}"
  if [ -n "$collie_url" ]; then
    if is_http_url "$collie_url"; then
      echo "COLLIE_URL: ok ($collie_url)"
    else
      echo "COLLIE_URL: invalid; expected http:// or https://"
      ok=0
    fi
  else
    echo "COLLIE_URL: not set (notifications will have no click action)"
  fi

  if [ "$ok" -ne 1 ]; then
    echo
    echo "Result: failed"
    return 1
  fi

  sent_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  title="🧪 verification・test (${ntfy_title})"
  body="$(printf 'Herdr ntfy test: this notification was sent by the test action.\nSent at: %s' "$sent_at")"

  echo
  echo "Sending title:"
  echo "$title"
  echo
  echo "Sending body:"
  echo "$body"
  echo
  echo "ntfy response:"

  if response="$(send_ntfy "$title" "$body")"; then
    printf '%s\n' "$response"
    echo
    echo "Result: sent"
    return 0
  fi

  echo
  echo "Result: failed"
  return 1
}

if [ "${1:-}" = "--dry-run" ]; then
  dry_run
  exit $?
fi

if [ "${1:-}" = "--test" ]; then
  test_notification
  exit $?
fi

load_env

event_json="${HERDR_PLUGIN_EVENT_JSON:-}"
context_json="${HERDR_PLUGIN_CONTEXT_JSON:-}"

status="$(first_value \
  "$(json_value HERDR_PLUGIN_EVENT_JSON "$event_json" '.data.agent_status')" \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.focused_pane_status')" \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.agent_status')" \
)"
status="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"

pane_id="$(first_value \
  "$(json_value HERDR_PLUGIN_EVENT_JSON "$event_json" '.data.pane_id')" \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.pane_id')" \
  "${HERDR_PANE_ID:-}" \
)"
state_file="$(status_state_file "$pane_id")"
previous_status="$(read_previous_status "$state_file")"
remember_status "$state_file" "$status"

case "$status" in
  done)
    emoji="✅"
    ;;
  blocked)
    emoji="🚫"
    ;;
  idle)
    if [ "$previous_status" != "working" ]; then
      exit 0
    fi
    emoji="✅"
    ;;
  *)
    exit 0
    ;;
esac

ntfy_url="${NTFY_URL:-}"
if [ -z "$ntfy_url" ]; then
  echo "missing NTFY_URL" >&2
  exit 0
fi
click_url="$(collie_click_url "${COLLIE_URL:-}" "$pane_id")"

ntfy_title="$(clean_label "${NTFY_TITLE:-Herdr}" "Herdr")"
workspace_name="$(first_value \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.workspace_label')" \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.workspace.name')" \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.workspace.label')" \
  "$(json_value HERDR_PLUGIN_EVENT_JSON "$event_json" '.data.workspace_label')" \
  "$(json_value HERDR_PLUGIN_EVENT_JSON "$event_json" '.data.workspace_id')" \
  "${HERDR_WORKSPACE_ID:-}" \
)"
tab_name="$(first_value \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.tab_label')" \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.tab.name')" \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.tab.label')" \
  "$(json_value HERDR_PLUGIN_EVENT_JSON "$event_json" '.data.tab_label')" \
  "$(json_value HERDR_PLUGIN_EVENT_JSON "$event_json" '.data.tab_id')" \
  "${HERDR_TAB_ID:-}" \
)"

workspace_name="$(clean_label "$workspace_name" "workspace")"
tab_name="$(clean_label "$tab_name" "tab")"
title="${emoji} ${workspace_name}・${tab_name} (${ntfy_title})"

herdr_bin="${HERDR_BIN_PATH:-herdr}"
lines="${NTFY_LINES:-12}"
body=""

if [ -n "$pane_id" ]; then
  body="$("$herdr_bin" pane read "$pane_id" --source recent-unwrapped --lines "$lines" 2>/dev/null || true)"
fi

if [ -z "$body" ]; then
  body="$(first_value \
    "$(json_value HERDR_PLUGIN_EVENT_JSON "$event_json" '.data.message')" \
    "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.message')" \
    "$status" \
  )"
fi

send_ntfy "$title" "$body" "$click_url"
