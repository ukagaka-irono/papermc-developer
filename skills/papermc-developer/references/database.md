# データベース（SQLite と MySQL）

プラグインのデータを、SQLite（プラグインのフォルダの 1 ファイル）か MySQL（MariaDB も）に保存するときの書き方と確かめ方。プレイヤーの数が少なく、1 台のサーバーだけで使うなら SQLite、複数のサーバー（Velocity の後ろの Paper など）でデータを共有する、または大きいなら MySQL。どちらにも切り替えられるように書くのが、配布するプラグインの普通の形。

## ドライバー

**Paper、Spigot、CraftBukkit は、SQLite と MySQL の JDBC ドライバーをサーバーに同梱している**（26.3 で確かめた: Paper は `org.xerial:sqlite-jdbc` と `com.mysql:mysql-connector-j`、Spigot も同じ 2 つ。古い版にも入っている）。プラグインの jar にドライバーを入れない（`compileOnly` にも要らない。`java.sql` の API だけで書く）。

- ドライバーのクラス: SQLite は `org.sqlite.JDBC`、MySQL は新しいサーバーで `com.mysql.cj.jdbc.Driver`、古いサーバー（MySQL Connector/J 5.x を同梱）で `com.mysql.jdbc.Driver`。テンプレートの `Database` は両方を試す。
- 古いサーバーの古いドライバーは、新しい MySQL（8.x の既定の認証 `caching_sha2_password`）につながらないことがある。そのときは MySQL の側でユーザーを `mysql_native_password` にするか、新しい版のサーバーを使う。
- **Velocity はドライバーを同梱していない。** Velocity のプラグインでデータベースを使うなら、ドライバー（と HikariCP）を shadow で jar に入れ、`relocate` する。依存の追加なので、作者に確かめてから。
- 接続を使い回すプール（HikariCP）はサーバーに入っていない。接続の多いプラグインで使うなら、`plugin.yml` の `libraries:`（1.16.5 以降。起動時に Maven Central から取る）か shadow で入れる。小さなプラグインなら、テンプレートの 1 本の接続で足りる。

## ひな形（`new-plugin.ps1 -Database`）

Paper、Folia、Spigot、CraftBukkit のどの版でも使える（Velocity は除く）。

| ファイル | 中身 |
|---|---|
| `Database.java` | `config.yml` の `database` から SQLite か MySQL の接続を作る。**クエリは専用のスレッド（単一スレッドの `ExecutorService`）だけで行う**。`start()`（接続と表の作成。`onEnable` で待つので、設定の誤りは有効化のときに分かる）、`countHello(name)`（`CompletableFuture` を返す）、`close()`（`onDisable`）。MySQL が切った接続は、次のクエリでつなぎ直す |
| `config.yml` の `database` | `type: sqlite`（既定。`data.db`）か `mysql`（`host`、`port`、`database`、`user`、`password`、`properties`） |
| `HelloCommand` | `/hello` を言った回数を表 `hello_counts` に数え、返事に `(#回数)` を付ける。結果はデータベースのスレッドから返る（`sendMessage` はどのスレッドからでもよい）。回数はログにも出す |
| `DatabaseTest`（1.21 以降のテスト付き） | 一時フォルダの SQLite で `Database` を直接試す（テストには `sqlite-jdbc` を `testRuntimeOnly` で入れている） |

ひな形の表と `/hello` の数え方は見本なので、作者の作りたいものに置き換える。

## 書くときの決まり

1. **メインスレッドでクエリを実行しない。** ファイルでもネットワークでも、データベースは遅い（MySQL は特に）。`Database` のスレッドで行い、結果でワールドやプレイヤーを操作するなら、メインスレッドに戻す（`getServer().getScheduler().runTask(...)`。Folia なら `player.getScheduler().run(...)`）。メッセージの送信だけなら戻さなくてよい。
2. **`PreparedStatement` の `?` で値を渡す。** プレイヤー名やチャットの文字列を SQL に文字列として埋め込まない（SQL インジェクション）。
3. **SQL は SQLite と MySQL の両方で通る書き方にする。** 違いが出やすいもの: 「無ければ作る、あれば更新」（SQLite は `ON CONFLICT ... DO UPDATE`、MySQL は `ON DUPLICATE KEY UPDATE`。古い SQLite には無い。テンプレートは UPDATE してから、無ければ INSERT）、自動の番号（`AUTOINCREMENT` と `AUTO_INCREMENT`）、型（`VARCHAR(n)`、`INT`、`BIGINT`、`TEXT` なら両方で通る）。どうしても違うなら、`Database` の中で `mysql` かどうかで分ける。
4. 表を変えるとき（列を足すなど）は、作成済みのデータベースを壊さないよう、`ALTER TABLE` で移行する処理を書く（`CREATE TABLE IF NOT EXISTS` は既存の表を変えない）。表に版の番号を持たせるとよい。
5. UUID で持つ（名前は変わる）。`VARCHAR(36)` の文字列が両方で扱いやすい。
6. `onDisable` で必ず閉じる（`close()`。キューに残ったクエリを終えてから閉じる）。
7. **パスワードをリポジトリに入れない。** `config.yml` の既定値は空にし、利用者が自分のサーバーで書く。テストサーバーの設定は、スキルがサーバーのフォルダにだけ書く。

## 確かめる

- **テスト**: `scripts/check.ps1`（`DatabaseTest` は本物の SQLite で動く）。
- **SQLite でテストサーバー**: `scripts/run-server.ps1 -Database sqlite`（`plugins/<名前>/config.yml` の `database` を SQLite にする）。`scripts/rcon.ps1 "hello"` を何度か送ると、ログに `said hello N time(s)` が出る。サーバーを再起動しても数が続けば、保存されている。
- **MySQL でテストサーバー**: `scripts/run-server.ps1 -Database mysql`。**テスト用の MySQL サーバー**が立ち、プラグインの `config.yml` がそこを向く。
  - テスト用の MySQL は、この PC に入っている MySQL（または MariaDB）の `mysqld` を、ホームフォルダの `mysql/` を専用のデータフォルダにして、別のポート（33306 から）、127.0.0.1 だけで動かしたもの。**作者がふだん使っている MySQL のサービスとデータには触らない。** ユーザーは `root`（パスワード無し）、データベースは `papermc_test`。
  - 中身を見る: `scripts/test-db.ps1 -Query "SELECT * FROM hello_counts"`。止める: `scripts/test-db.ps1 -Stop`。状態: `scripts/test-db.ps1`。消して作り直す: `scripts/test-db.ps1 -Reset`（作者に確かめてから）。
  - MySQL も MariaDB も入っていなければ、終了コード 3。入れるかは作者に聞く（Windows: `winget install --id Oracle.MySQL -e`）。入れないなら SQLite で確かめる。
- 作者が自分の MySQL で動かしたいときは、作者が `config.yml` の `database.mysql` に接続先を書く（パスワードをチャットに貼らせない）。
