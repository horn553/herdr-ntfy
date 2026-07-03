# herdr-ntfy

[English](README.md)

[Herdr](https://herdr.dev/)にて、agentが `done` または `blocked` になったとき、ntfyへ通知するプラグインです。
機能を最低限に抑えることで、依存関係をシンプルにしています。

## 通知例

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

- `done` は `✅`、`blocked` は `🚫` で通知します。
- 通知タイトルは `<emoji> <workspace>・<tab> (<NTFY_TITLE>)` です。
- 通知本文はagent paneの直近出力です。
- `Priority` ヘッダーは送信しません。

## 必要なもの

- Herdr >= 0.7.0
- `sh`
- `curl`
- `jq`

## インストール

```sh
herdr plugin install horn553/herdr-ntfy
config_dir="$(herdr plugin config-dir horn553.herdr-ntfy)"
touch "$config_dir/.env"
chmod 600 "$config_dir/.env"
$EDITOR "$config_dir/.env"
```

`$config_dir/.env` を作成して権限を絞り、以下を設定してください。

```sh
NTFY_URL=https://ntfy.sh/your-topic
NTFY_TITLE=Herdr
NTFY_TOKEN=
NTFY_LINES=12
```

保護されたtopicを使う場合は `NTFY_TOKEN` を設定します。

## dry-run

設定内容を確認し、サンプル通知内容を表示します。ntfyには送信しません。

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

`action invoke` は非同期で実行されます。dry-runの出力はplugin logで確認してください。

## ローカル開発

```sh
herdr plugin link .
config_dir="$(herdr plugin config-dir horn553.herdr-ntfy)"
cp .env.example "$config_dir/.env"
```

ローカル開発中は `./.env` もfallbackとして読みます。

## Marketplace

Herdr marketplaceは `herdr-plugin` topicが付いたpublic GitHub repositoryを自動indexします。

## License

[MIT](LICENSE)
