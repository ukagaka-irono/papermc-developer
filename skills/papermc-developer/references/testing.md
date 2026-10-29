# テストと動作確認

プラグインの動きを確かめる方法は 3 つあり、確かめられることが違う。新しい機能を作ったら、まず 1 と 2、仕上げに 3 を作者に頼む。

| 方法 | 確かめられること | 確かめられないこと |
|---|---|---|
| 1. MockBukkit のテスト（`scripts/check.ps1`） | ロジック、コマンドやイベントの処理、メッセージの中身、設定の読み方。速く、何度でも、プレイヤーを何人でも作れる | 本物のワールドの挙動（MockBukkit が未実装の API は例外になる）、ほかのプラグインとの組み合わせ、性能 |
| 2. テストサーバー（`scripts/run-server.ps1`、`rcon.ps1`、`server-log.ps1`） | 本物の Paper で読み込まれ、有効になるか。起動時のエラー、コンソールから打てるコマンド、タイマーの処理のログ、`onDisable` | プレイヤーが必要な操作（クリック、移動、インベントリ）。見た目 |
| 3. 作者がクライアントで入る | 見た目、操作感、プレイヤーが必要な操作 | — |

## 1. MockBukkit

- テンプレートは JUnit と MockBukkit（`org.mockbukkit.mockbukkit:mockbukkit-v<版>`）入りで作られる。MockBukkit は Minecraft の版ごとに別の成果物で、新しい版には遅れて出る（`scripts/versions.ps1` で有無を見る。無い版では `new-plugin.ps1` がテスト無しで作る）。
- **1.20.4 以前を対象にしたプロジェクトは、テスト無しで作られる**（今の MockBukkit は 1.21 から。1.13〜1.20 には古い MockBukkit（`com.github.seeseemelk:MockBukkit-v1.<マイナー>`、パッケージは `be.seeseemelk.mockbukkit`）があり、1.12.2 以前には無い）。古い版では、確かめる手段はテストサーバーが中心になる。古い MockBukkit を足すかは作者と決める（版とパッケージ名を Maven Central で確かめてから）。
- 基本の形（テンプレートの `*Test.java`）:
  - `@BeforeEach` で `server = MockBukkit.mock()` と `plugin = MockBukkit.load(Main.class)`、`@AfterEach` で `MockBukkit.unmock()`。
  - プレイヤーは `server.addPlayer()`（参加イベントも起きる）。受け取ったメッセージは `player.nextComponentMessage()`。
  - プレイヤーとしてコマンドを打つのは `player.performCommand("hello")`。時間を進めるのは `server.getScheduler().performTicks(n)`。
  - 使い方は https://docs.mockbukkit.org/ で確かめる（メソッド名を推測しない）。
- **main クラスを `final` にしない**（MockBukkit がサブクラスを作って読み込むため）。
- MockBukkit が実装していない API を呼ぶと `UnimplementedOperationException` になる。その部分はテストを分けるか、テストサーバーで確かめる。
- テストは、作者が書いた仕様（`PLUGIN.md` の「動作確認」）を確かめるものにする。実装をなぞっただけのテストを数で増やさない。

## 2. テストサーバー

手順は `references/workflows/try-on-server.md`。要点:

- `scripts/run-server.ps1` が、ビルド → 再起動 → 有効になったかとエラーの報告までを 1 回で行う。コードを直したら、もう一度これを実行する。
- `scripts/rcon.ps1 "コマンド"` はコンソールとして打つ。`sender` がプレイヤーであることを前提にしたコマンドは、コンソール向けの分岐（または「プレイヤーだけが使える」というメッセージ）を確かめることになる。
- コマンドの処理で例外が起きても、RCON の返事は空のことが多い。`rcon.ps1` は、その間にログに増えたものも表示するので、そこを見る。
- 時間で動く処理は `scripts/server-log.ps1 -Plugin -Wait 60` で、ログに出るのを待つ（確かめたいところで `getComponentLogger().info(...)` を出すとよい。確かめ終えたら、残すか消すかを作者と決める）。
- `-JdwpPort 5005` で起動すると、作者が IDE（IntelliJ IDEA の Remote JVM Debug など）でブレークポイントを使える。

## 3. 作者が入る

`run-server.ps1` が表示する `localhost:<ポート>` に、同じ版の Minecraft で接続してもらう（マルチプレイ → ダイレクト接続）。テストサーバーは 127.0.0.1 だけで待ち受けるので、ほかの PC からは入れない。OP が要るなら `scripts/rcon.ps1 "op <プレイヤー名>"`（作者に確かめてから）。何をすると何が起きるべきかを、`PLUGIN.md` の「動作確認」に沿って伝える。
