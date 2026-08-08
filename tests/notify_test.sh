#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

calls="$test_dir/calls"
body="$test_dir/body"
config_dir="$test_dir/config"
pane_id="pane-transition-test"

call_count() {
  if [ -f "$calls" ]; then
    wc -l <"$calls" | tr -d ' '
  else
    printf '0'
  fi
}

assert_call_count() {
  expected="$1"
  actual="$(call_count)"

  if [ "$actual" != "$expected" ]; then
    echo "expected $expected notification(s), got $actual" >&2
    exit 1
  fi
}

run_event() {
  agent_status="$1"

  HERDR_PLUGIN_EVENT_JSON="{\"data\":{\"agent_status\":\"$agent_status\",\"pane_id\":\"$pane_id\"}}" \
  HERDR_PLUGIN_CONTEXT_JSON='{"workspace_label":"workspace","tab_label":"tab"}' \
  HERDR_PLUGIN_CONFIG_DIR="$config_dir" \
  NTFY_URL='https://ntfy.example/topic' \
  COLLIE_URL="${COLLIE_URL:-}" \
  NTFY_TEST_CALLS="$calls" \
  NTFY_TEST_BODY="$body" \
  PATH="$root/tests/bin:$PATH" \
    sh "$root/notify.sh" >/dev/null
}

run_event idle
assert_call_count 0

run_event working
assert_call_count 0
run_event idle
assert_call_count 1
grep -q 'Title: ✅ workspace・tab (Herdr)' "$calls"
grep -q 'Agent output from the test pane.' "$body"

run_event idle
assert_call_count 1

run_event working
run_event done
assert_call_count 2
run_event idle
assert_call_count 2

run_event blocked
assert_call_count 3
grep -q 'Title: 🚫 workspace・tab (Herdr)' "$calls"

run_event working
run_event done
assert_call_count 4
grep -q 'Click:' "$calls" && {
  echo "expected no Click header without COLLIE_URL" >&2
  exit 1
}

COLLIE_URL='https://collie.example.ts.net' run_event working
COLLIE_URL='https://collie.example.ts.net' run_event done
assert_call_count 5
grep -q "Click: https://collie.example.ts.net/pane/pane-transition-test" "$calls"

echo "notify tests: ok"
