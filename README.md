# Herdr ntfy

Send an ntfy notification when a Herdr agent reaches `done` or `blocked`.

The notification title is:

```text
<emoji> <workspace>・<tab> (<NTFY_TITLE>)
```

The notification body is the recent output from the agent pane.

## Requirements

- Herdr 0.7.0 or newer
- `sh`
- `curl`
- `jq`

## Install

```sh
herdr plugin install horn553/herdr-ntfy
config_dir="$(herdr plugin config-dir horn553.herdr-ntfy)"
$EDITOR "$config_dir/.env"
```

Put this in `$config_dir/.env`:

```sh
NTFY_URL=https://ntfy.sh/your-private-topic
NTFY_TITLE=Herdr
NTFY_TOKEN=
NTFY_LINES=12
```

Use a hard-to-guess private topic name. For protected topics, set `NTFY_TOKEN`.

## Local Development

```sh
herdr plugin link .
config_dir="$(herdr plugin config-dir horn553.herdr-ntfy)"
cp .env.example "$config_dir/.env"
```

During local development, `./.env` is also read as a fallback.

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

## Marketplace

Herdr's marketplace is an automatic index of public GitHub repositories tagged
with the `herdr-plugin` topic. Publish this repository publicly and add that
topic to make it discoverable.
