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

load_env

event_json="${HERDR_PLUGIN_EVENT_JSON:-}"
context_json="${HERDR_PLUGIN_CONTEXT_JSON:-}"

status="$(first_value \
  "$(json_value HERDR_PLUGIN_EVENT_JSON "$event_json" '.data.agent_status')" \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.focused_pane_status')" \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.agent_status')" \
)"
status="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"

case "$status" in
  done)
    emoji="✅"
    ;;
  blocked)
    emoji="🚫"
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

ntfy_title="$(clean_label "${NTFY_TITLE:-Herdr}" "Herdr")"
pane_id="$(first_value \
  "$(json_value HERDR_PLUGIN_EVENT_JSON "$event_json" '.data.pane_id')" \
  "$(json_value HERDR_PLUGIN_CONTEXT_JSON "$context_json" '.pane_id')" \
  "${HERDR_PANE_ID:-}" \
)"
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

if [ -n "${NTFY_TOKEN:-}" ]; then
  printf '%s' "$body" | curl -fsS \
    -H "Title: $title" \
    -H "Content-Type: text/plain; charset=utf-8" \
    -H "Authorization: Bearer $NTFY_TOKEN" \
    --data-binary @- \
    "$ntfy_url"
else
  printf '%s' "$body" | curl -fsS \
    -H "Title: $title" \
    -H "Content-Type: text/plain; charset=utf-8" \
    --data-binary @- \
    "$ntfy_url"
fi
