# herdr-ntfy

[日本語](README-ja.md)

A [Herdr](https://herdr.dev/) plugin that sends ntfy notifications when an agent reaches `done` or `blocked`.
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

- `done` uses `✅`; `blocked` uses `🚫`.
- The notification title is `<emoji> <workspace>・<tab> (<NTFY_TITLE>)`.
- The notification body is recent output from the agent pane.
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
```

Set `NTFY_TOKEN` when using a protected topic.

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

Sample title:
✅ verification・dry-run (Herdr)

Sample body:
Herdr ntfy dry-run: no notification was sent.

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

## Marketplace

Herdr's marketplace automatically indexes public GitHub repositories tagged with the `herdr-plugin` topic.

## License

[MIT](LICENSE)
