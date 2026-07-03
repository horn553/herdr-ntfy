# Herdr ntfy

Herdr agentが `done` または `blocked` になったとき、ntfyへ通知するHerdr pluginです。

This Herdr plugin sends an ntfy notification when a Herdr agent reaches `done` or `blocked`.

## 機能 / Features

- `done` は `✅`、`blocked` は `🚫` で通知します。
- 通知タイトルは `<emoji> <workspace>・<tab> (<NTFY_TITLE>)` です。
- 通知本文はagent paneの直近出力です。
- `Priority` ヘッダーは送信しません。
- `dry-run` actionで設定内容とサンプル通知を確認できます。ntfyには送信しません。

- `done` uses `✅`; `blocked` uses `🚫`.
- The notification title is `<emoji> <workspace>・<tab> (<NTFY_TITLE>)`.
- The notification body is recent output from the agent pane.
- The plugin does not send a `Priority` header.
- The `dry-run` action checks configuration and prints a sample notification without sending to ntfy.

## 必要なもの / Requirements

- Herdr 0.7.0 or newer
- `sh`
- `curl`
- `jq`

## インストール / Install

```sh
herdr plugin install horn553/herdr-ntfy
config_dir="$(herdr plugin config-dir horn553.herdr-ntfy)"
$EDITOR "$config_dir/.env"
```

`$config_dir/.env` に以下を設定してください。

Put this in `$config_dir/.env`.

```sh
NTFY_URL=https://ntfy.sh/your-private-topic
NTFY_TITLE=Herdr
NTFY_TOKEN=
NTFY_LINES=12
```

推測されにくいprivate topic名を使ってください。保護されたtopicを使う場合は `NTFY_TOKEN` を設定します。

Use a hard-to-guess private topic name. For protected topics, set `NTFY_TOKEN`.

## dry-run

設定内容を確認し、サンプル通知内容を表示します。ntfyには送信しません。

Check configuration and print a sample notification. Nothing is sent to ntfy.

```sh
herdr plugin action invoke dry-run
```

成功時の例:

Example success output:

```text
Herdr ntfy dry-run

curl: ok
jq: ok
NTFY_URL: ok (https://ntfy.sh/your-p...)
NTFY_TITLE: Herdr
NTFY_TOKEN: not set
NTFY_LINES: 12

Sample title:
✅ verification・dry-run (Herdr)

Sample body:
Herdr ntfy dry-run: no notification was sent.

Result: ok
```

## 通知例 / Notification Examples

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

## ローカル開発 / Local Development

```sh
herdr plugin link .
config_dir="$(herdr plugin config-dir horn553.herdr-ntfy)"
cp .env.example "$config_dir/.env"
```

ローカル開発中は `./.env` もfallbackとして読みます。

During local development, `./.env` is also read as a fallback.

## Marketplace

Herdr marketplaceは `herdr-plugin` topicが付いたpublic GitHub repositoryを自動indexします。

Herdr's marketplace automatically indexes public GitHub repositories tagged with the `herdr-plugin` topic.
