<!-- papermc-developer:plugin-template -->
<!-- ↑ この 2 行は、下書きを作者が確かめて書き終えたら消す。 -->
# @@PLUGIN_NAME@@

AI エージェントが作業の前に読む、このプラグインに固有の情報。分からない欄は空けたままにして、作者に聞く。

## 概要

（何をするプラグインか。誰が、どんな場面で使うか。1〜3 行）

## 対象

| | |
|---|---|
@@BEGIN:PAPER@@
| サーバー | Paper @@MINECRAFT@@ |
@@BEGIN:FOLIA@@
| Folia | 対応する（`folia-supported: true`。スケジューラはリージョン用のものだけを使う） |
@@END:FOLIA@@
@@BEGIN:NO_FOLIA@@
| Folia | 対応しない |
@@END:NO_FOLIA@@
@@END:PAPER@@
@@BEGIN:VELOCITY@@
| サーバー | Velocity @@MINECRAFT@@（プロキシ。後ろの Paper サーバーには入らない） |
@@END:VELOCITY@@
| Java | @@JAVA@@ |
| 形式 | @@DESCRIPTOR@@ |
| 依存プラグイン | なし |

## コマンドと権限

| コマンド | 権限 | 既定 | 内容 |
|---|---|---|---|
@@BEGIN:PAPER@@
| `/hello` | `@@PERMISSION_PREFIX@@.hello` | 全員 | あいさつを返す（ひな形の例。消してよい） |
@@END:PAPER@@
@@BEGIN:VELOCITY@@
| `/hello`（プロキシのコマンド） | なし | 全員 | あいさつを返す（ひな形の例。消してよい） |
@@END:VELOCITY@@

## 設定ファイル

@@BEGIN:PAPER@@
`config.yml` のキーと意味。メッセージは MiniMessage で書く。

| キー | 既定 | 意味 |
|---|---|---|
| `join-message` | `<green>Welcome, <player>!` | 参加したときのメッセージ（ひな形の例） |
@@END:PAPER@@
@@BEGIN:VELOCITY@@
（ひな形には設定ファイルが無い。足すなら、プラグインのデータフォルダ（`@DataDirectory`）に置くファイルと、そのキー）
@@END:VELOCITY@@

## データ

保存するもの（PDC、ファイル、データベース）と、その場所と形式。

## 構成

| パッケージ / クラス | 役割 |
|---|---|
| `@@PACKAGE@@.@@MAIN_CLASS@@` | プラグイン本体 |

## 決まり

@@BEGIN:PAPER@@
- メッセージは `config.yml` に置き、コードに直接書かない。
@@END:PAPER@@
- 

## 動作確認

テストサーバーで、何をすると何が起きるべきか（`scripts/rcon.ps1` で打つコマンドと、期待する結果）。

| 操作 | 期待する結果 |
|---|---|
@@BEGIN:PAPER@@
| `hello`（RCON から） | `Hello!` が返る |
@@END:PAPER@@
@@BEGIN:VELOCITY@@
| `hello`（プロキシのコンソールから） | ログに `Hello from the proxy!` が出る |
| プロキシ（`localhost:<ポート>`）にクライアントで入る | `Welcome to the proxy, <名前>!` が出て、後ろの Paper サーバーに着く |
@@END:VELOCITY@@

## ブランチ

| ブランチ | 役割 |
|---|---|
| `main` | 配布した版だけ。リリースのタグはここに付ける。直接コミットしない |
| `develop` | 次の版の変更を集める。直接コミットしない |
| `〇〇〇〇-fix` | 1 つの作業ごと（例: `hello-command-fix`）。`develop` から作り、`develop` に戻す |

リリースは `develop` → `main`。

## 配布

| | |
|---|---|
| 配布先 | （GitHub Releases / Hangar / Modrinth） |
| ライセンス | （未定） |
