<!-- papermc-developer:plugin-template -->
<!-- ↑ この 2 行は、下書きを作者が確かめて書き終えたら消す。 -->
# @@PLUGIN_NAME@@

AI エージェントが作業の前に読む、このプラグインに固有の情報。分からない欄は空けたままにして、作者に聞く。

## 概要

（何をするプラグインか。誰が、どんな場面で使うか。1〜3 行）

## 対象

| | |
|---|---|
@@BEGIN:SERVER_PAPER@@
| サーバー | Paper @@MINECRAFT@@（Spigot と CraftBukkit では動かないことがある） |
@@BEGIN:FOLIA@@
| Folia | 対応する（`folia-supported: true`。スケジューラはリージョン用のものだけを使う） |
@@END:FOLIA@@
@@BEGIN:NO_FOLIA@@
| Folia | 対応しない |
@@END:NO_FOLIA@@
@@END:SERVER_PAPER@@
@@BEGIN:SERVER_SPIGOT@@
| サーバー | Spigot @@MINECRAFT@@（Paper でも動く。Paper だけの API は使わない） |
@@END:SERVER_SPIGOT@@
@@BEGIN:SERVER_CRAFTBUKKIT@@
| サーバー | CraftBukkit @@MINECRAFT@@（Spigot と Paper でも動く。Bukkit の API だけを使う） |
@@END:SERVER_CRAFTBUKKIT@@
@@BEGIN:VELOCITY@@
| サーバー | Velocity @@MINECRAFT@@（プロキシ。後ろの Paper サーバーには入らない） |
@@END:VELOCITY@@
| Java | @@JAVA@@ |
| 形式 | @@DESCRIPTOR@@ |
| 依存プラグイン | なし |

## コマンドと権限

| コマンド | 権限 | 既定 | 内容 |
|---|---|---|---|
@@BEGIN:BUKKIT@@
| `/hello` | `@@PERMISSION_PREFIX@@.hello` | 全員 | あいさつを返す（ひな形の例。消してよい） |
@@END:BUKKIT@@
@@BEGIN:VELOCITY@@
| `/hello`（プロキシのコマンド） | なし | 全員 | あいさつを返す（ひな形の例。消してよい） |
@@END:VELOCITY@@

## 設定ファイル

@@BEGIN:BUKKIT@@
@@BEGIN:MINIMESSAGE@@
`config.yml` のキーと意味。メッセージは MiniMessage で書く。

| キー | 既定 | 意味 |
|---|---|---|
| `join-message` | `<green>Welcome, <player>!` | 参加したときのメッセージ（ひな形の例） |
@@END:MINIMESSAGE@@
@@BEGIN:LEGACY_TEXT@@
`config.yml` のキーと意味。メッセージは `&` の色コードで書く（`{player}` はプレイヤー名）。

| キー | 既定 | 意味 |
|---|---|---|
| `join-message` | `&aWelcome, {player}!` | 参加したときのメッセージ（ひな形の例） |
@@END:LEGACY_TEXT@@
@@END:BUKKIT@@
@@BEGIN:VELOCITY@@
（ひな形には設定ファイルが無い。足すなら、プラグインのデータフォルダ（`@DataDirectory`）に置くファイルと、そのキー）
@@END:VELOCITY@@

## データ

保存するもの（PDC、ファイル、データベース）と、その場所と形式。
@@BEGIN:DATABASE@@

| データベース | 既定 | 内容 |
|---|---|---|
| `config.yml` の `database.type` | `sqlite`（プラグインのフォルダの `data.db`） | `mysql` にすると `database.mysql` の接続先 |
| 表 `hello_counts` | `name VARCHAR(64)` 主キー、`count INT` | `/hello` を言った回数（ひな形の例。消してよい） |

クエリは `Database` クラスの専用のスレッドだけで行う（メインスレッドで行わない）。
@@END:DATABASE@@

## 構成

| パッケージ / クラス | 役割 |
|---|---|
| `@@PACKAGE@@.@@MAIN_CLASS@@` | プラグイン本体 |

## 決まり

@@BEGIN:BUKKIT@@
- メッセージは `config.yml` に置き、コードに直接書かない。
@@END:BUKKIT@@
- 

## 動作確認

テストサーバーで、何をすると何が起きるべきか（`scripts/rcon.ps1` で打つコマンドと、期待する結果）。

| 操作 | 期待する結果 |
|---|---|
@@BEGIN:BUKKIT@@
| `hello`（RCON から） | `Hello!` が返る |
@@END:BUKKIT@@
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
