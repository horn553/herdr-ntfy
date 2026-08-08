# herdr-ntfy

[日本語](README-ja.md)

A [Herdr](https://herdr.dev/) plugin that sends ntfy notifications when an agent reaches `done` or `blocked`, or changes directly from `working` to `idle`.
The feature set is intentionally small to keep dependencies simple.

## Notification Examples

```text
Title: ✅ herdr-ntfy・main (Herdr)

Implemented the ntfy plugin.
Tests not run.
```

```text
Title: 🚫 herdr-ntfy・main (Herdr)

Blocked because NTFY_URL is not configured.
Set it in the plugin config directory .env file.
```

- `done` and `working → idle` use `✅`; `blocked` uses `🚫`.
- The plugin stores the latest status for each pane under the plugin config directory so it can recognize `working → idle` transitions.
- The notification title is `<emoji> <workspace>・<tab> (<NTFY_TITLE>)`.
- The notification body is recent output from the agent pane.
- When `COLLIE_URL` is set, the notification includes a `Click` action that opens the source pane in [Collie](https://github.com/AltanS/collie) at `<COLLIE_URL>/pane/<pane_id>`.
- The plugin does not send a `Priority` header.

## Requirements

- Herdr >= 0.7.0
- `sh`
- `curl`
- `jq`

## Install

```sh
herdr plugin install horn553/herdr-ntfy
config_dir="$(herdr plugin config-dir horn553.herdr-ntfy)"
touch "$config_dir/.env"
chmod 600 "$config_dir/.env"
$EDITOR "$config_dir/.env"
```

Create `$config_dir/.env`, restrict its permissions, and put this in it.

```sh
NTFY_URL=https://ntfy.sh/your-topic
NTFY_TITLE=Herdr
NTFY_TOKEN=
NTFY_LINES=12
COLLIE_URL=
```

Set `NTFY_TOKEN` when using a protected topic.

Set `COLLIE_URL` to your [Collie](https://github.com/AltanS/collie) instance's base URL (for example `https://your-tailnet-host.ts.net`, no trailing slash) to add a click action that deep-links straight to the pane that triggered the notification. Leave it unset to omit the click action.

## dry-run

Check configuration and print a sample notification. Nothing is sent to ntfy.

```console
$ herdr plugin action invoke dry-run
{"id":"cli:plugin","result":{"log":{"log_id":"plugin-log-113","status":"running"},"type":"plugin_action_invoked"}}

$ herdr plugin log list --plugin horn553.herdr-ntfy --limit 1 | jq -r '.result.logs[-1].stdout'
Herdr ntfy dry-run

curl: ok
jq: ok
NTFY_URL: ok (https://ntfy.sh/your-...)
NTFY_TITLE: Herdr
NTFY_TOKEN: not set
NTFY_LINES: 12
COLLIE_URL: ok (https://your-tailnet-host.ts.net)

Sample title:
✅ verification・dry-run (Herdr)

Sample body:
Herdr ntfy dry-run: no notification was sent.

Sample click URL:
https://your-tailnet-host.ts.net/pane/wE%3Ap1

Result: ok
```

`action invoke` runs asynchronously. Check the plugin log for the dry-run output.

## test

Send a real test notification to ntfy.

```console
$ herdr plugin action invoke test
{"id":"cli:plugin","result":{"log":{"log_id":"plugin-log-114","status":"running"},"type":"plugin_action_invoked"}}

$ herdr plugin log list --plugin horn553.herdr-ntfy --limit 1 | jq -r '.result.logs[-1].stdout'
Herdr ntfy test

curl: ok
NTFY_URL: ok (https://ntfy.sh/your-...)
NTFY_TITLE: Herdr
NTFY_TOKEN: not set
COLLIE_URL: not set (notifications will have no click action)

Sending title:
🧪 verification・test (Herdr)

Sending body:
Herdr ntfy test: this notification was sent by the test action.
Sent at: 2026-07-03T00:00:00Z

ntfy response:
{"id":"...","time":...,"expires":...,"event":"message","topic":"your-topic","message":"..."}

Result: sent
```

## Local Development

```sh
herdr plugin link .
config_dir="$(herdr plugin config-dir horn553.herdr-ntfy)"
cp .env.example "$config_dir/.env"
```

During local development, `./.env` is also read as a fallback.

Run the transition tests with:

```sh
sh tests/notify_test.sh
```

## Marketplace

Herdr's marketplace automatically indexes public GitHub repositories tagged with the `herdr-plugin` topic.

## License

[MIT](LICENSE)
