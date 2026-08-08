# herdr-ntfy

[English](README.md)

[Herdr](https://herdr.dev/)にて、agentが `done` または `blocked` になったとき、または `working` から直接 `idle` に変化したとき、ntfyへ通知するプラグインです。
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

- `done` と `working → idle` は `✅`、`blocked` は `🚫` で通知します。
- `working → idle` の変化を判定するため、paneごとの直近statusをplugin config directoryに保存します。
- 通知タイトルは `<emoji> <workspace>・<tab> (<NTFY_TITLE>)` です。
- 通知本文はagent paneの直近出力です。
- `COLLIE_URL` を設定すると、通知に [Collie](https://github.com/AltanS/collie) の対象paneを開く `Click` アクションが付きます（`<COLLIE_URL>/pane/<pane_id>`）。
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
COLLIE_URL=
```

保護されたtopicを使う場合は `NTFY_TOKEN` を設定します。

`COLLIE_URL` に [Collie](https://github.com/AltanS/collie) インスタンスのベースURL（例: `https://your-tailnet-host.ts.net`、末尾スラッシュなし）を設定すると、通知が発生したpaneへ直接遷移するclickアクションが追加されます。未設定の場合はclickアクションを付けません。

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
COLLIE_URL: ok (https://your-tailnet-host.ts.net)

Sample title:
✅ verification・dry-run (Herdr)

Sample body:
Herdr ntfy dry-run: no notification was sent.

Sample click URL:
https://your-tailnet-host.ts.net/pane/wE%3Ap1

Result: ok
```

`action invoke` は非同期で実行されます。dry-runの出力はplugin logで確認してください。

## test

ntfyへ実際にテスト通知を送信します。

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

## ローカル開発

```sh
herdr plugin link .
config_dir="$(herdr plugin config-dir horn553.herdr-ntfy)"
cp .env.example "$config_dir/.env"
```

ローカル開発中は `./.env` もfallbackとして読みます。

status変化のテストは以下で実行できます。

```sh
sh tests/notify_test.sh
```

## Marketplace

Herdr marketplaceは `herdr-plugin` topicが付いたpublic GitHub repositoryを自動indexします。

## License

[MIT](LICENSE)
