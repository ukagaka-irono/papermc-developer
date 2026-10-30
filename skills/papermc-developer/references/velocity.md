# Velocity のプラグイン

Velocity（https://papermc.io/software/velocity ）は、PaperMC のプロキシ。プレイヤーは Velocity に接続し、Velocity が後ろにある複数の Paper サーバーへ振り分ける。**Velocity のプラグインは、Paper のプラグインとは別物**（API、記述ファイル、動く場所が違う）。プロキシで動くので、ワールドやブロック、エンティティには触れない。触れるのは、接続、プレイヤーの移動（サーバー間）、チャット、プロキシのコマンド、プラグインメッセージなど。

ワールドを触る機能と、サーバーをまたぐ機能の両方が要るなら、Paper のプラグインと Velocity のプラグインを 2 つ作り、プラグインメッセージで連絡させる（作者と構成を決める）。

## 作る

`scripts/new-plugin.ps1 -Name <名前> -Velocity`（版は `-VelocityVersion`、既定は最新の安定版）。

| ファイル | 中身 |
|---|---|
| `build.gradle.kts` | `compileOnly` と `annotationProcessor` に `com.velocitypowered:velocity-api:<版>`、Java のツールチェーン、`BuildConstants` を作るタスク、run-velocity（`./gradlew runVelocity`） |
| `<Main>.java` | `@Plugin(id, name, version = BuildConstants.VERSION, ...)`、Guice の `@Inject` で `ProxyServer` と `Logger` を受け取るコンストラクタ、`ProxyInitializeEvent` でリスナーとコマンドを登録 |
| `HelloCommand.java` | `BrigadierCommand` の `/hello`（プロキシのコマンド） |
| `JoinListener.java` | `PostLoginEvent` で MiniMessage のあいさつ |

- **`velocity-plugin.json` は書かない。** コンパイルのときに、注釈処理（annotation processor）が `@Plugin` から作る。`annotationProcessor` の行を消すと作られず、プロキシがプラグインを読み込まない（`scripts/check.ps1` が知らせる）。
- `id` は小文字、数字、`-`、`_`（英字で始め、64 文字まで）。ほかのプラグインから依存されるときの名前でもあるので、後から変えない。
- 版は `build.gradle.kts` の `version` の 1 か所で管理する。`BuildConstants.VERSION` は、それをビルドのたびにコードにしたもの（`build/generated/` にでき、コミットしない）。
- テストの仕組み（MockBukkit のようなもの）は無い。確かめるのはテストのプロキシ（下）と、ロジックを Velocity から切り離して書いた普通の JUnit のテスト。

## 書き方の要点

PaperMC のドキュメント（`https://docs.papermc.io/llms.txt` の `/velocity/dev/` のページ）と Javadoc（https://jd.papermc.io/velocity/ ）で確かめてから書く。Velocity の API は Bukkit / Paper とまったく違うので、Paper の書き方を持ち込まない。

| やりたいこと | 使うもの | 資料 |
|---|---|---|
| 始まりと終わり | `@Subscribe` で `ProxyInitializeEvent` / `ProxyShutdownEvent`（Paper の `onEnable` / `onDisable` にあたる） | `/velocity/dev/api-basics/index.md` |
| イベント | `@Subscribe` のメソッドを持つクラスを `server.getEventManager().register(plugin, listener)`。接続は `LoginEvent`、`PostLoginEvent`、`ServerPreConnectEvent`、`ServerConnectedEvent`、`DisconnectEvent` など | `/velocity/dev/event-api/index.md` |
| コマンド | `BrigadierCommand`、`SimpleCommand`、`RawCommand`。`commandManager.metaBuilder("名前").plugin(this).build()` で登録 | `/velocity/dev/command-api/index.md` |
| 後で・くり返し実行 | `server.getScheduler().buildTask(plugin, runnable).delay(...).repeat(...).schedule()`。Velocity にメインスレッドは無く、どれも別スレッドで動く | `/velocity/dev/scheduler-api/index.md` |
| メッセージ | Adventure（`Component`、MiniMessage）。プレイヤーも `CommandSource` も `Audience` | |
| 設定 | `@DataDirectory Path` をコンストラクタで受け取り、そこにファイルを置く（Velocity 自体は設定の仕組みを持たない。Configurate などを使うなら依存の追加を作者に確かめる） | `/velocity/dev/api-basics/index.md` |
| Paper サーバーとの連絡 | プラグインメッセージ（`ChannelIdentifier`、`PluginMessageEvent`） | `/velocity/dev/plugin-messaging/index.md` |
| ほかのプラグインに依存 | `@Plugin(dependencies = @Dependency(id = "..."))` | `/velocity/dev/velocity-plugin-json/index.md` |

## AI がやりがちな失敗

（`/velocity/dev/pitfalls/index.md` も読む）

1. **Bukkit / Paper の API（`JavaPlugin`、`plugin.yml`、`Bukkit.getPlayer`）を書く。** Velocity には無い。
2. **`velocity-plugin.json` を手で書き、`@Plugin` と食い違う**、または `annotationProcessor` を忘れる。
3. **権限が既定で通ると思う。** Velocity には権限の既定値が無く、権限プラグイン（LuckPerms など）が無ければ、プレイヤーの `hasPermission` は `false`（コンソールは `true`）。ひな形の `/hello` が権限を見ないのはそのため。管理者向けのコマンドは権限を見て、`PLUGIN.md` に必要な権限プラグインを書く。
4. **イベントの中で重い処理をする。** 接続のイベントで止めると、プレイヤーのログインが止まる。データベースや HTTP は `EventTask.async(...)` を返すか、スケジューラに回す。
5. **プレイヤーの UUID を信じすぎる。** オフラインモードのプロキシや、後ろのサーバーが Velocity の転送（forwarding）を使っていない構成では、UUID がずれる。
6. **Velocity の版の違い。** 3.x（Java 21）と 4.x（Java 25）がある。`scripts/versions.ps1` で今の版を見て、作者のプロキシの版に合わせる。

## テストのプロキシで確かめる

`scripts/run-server.ps1`（Velocity のプロジェクトでは `scripts/run-proxy.ps1` が動く）が、テスト用の **Velocity プロキシと、その後ろの Paper サーバー（バックエンド）** を立てる。

- プロキシは `127.0.0.1:25610` から、バックエンドは `127.0.0.1:25620` から（RCON は 25630 から）。どちらも 127.0.0.1 だけで待ち受ける。
- 転送は Velocity の modern forwarding（`velocity.toml` の `player-info-forwarding-mode = "MODERN"` と `forwarding.secret`、バックエンドの `config/paper-global.yml` の `proxies.velocity`）。バックエンドは `online-mode=false`（Velocity の後ろでは正しい設定。127.0.0.1 だけなので外からは入れない）。
- バックエンドは Minecraft のサーバーなので、**作者の EULA への同意が要る**（`references/workflows/try-on-server.md`）。バックエンドの版は `-Minecraft`（既定は最新の安定版。1.19 以降）。
- **Velocity には RCON が無い。** `scripts/rcon.ps1 "<コマンド>"` は、プロキシのコンソールに送り（`lib/console-bridge.ps1` が標準入力をつないでいる）、その間にログに出たものを見せる（返事もログに出る）。`velocity plugins` でプラグインの一覧、`velocity dump` で設定の確認。バックエンドには `scripts/rcon.ps1 -Backend "<コマンド>"`。
- ログ: `scripts/server-log.ps1`（プロキシ）、`-Backend`（バックエンド）。プラグインのロガーは、プラグインの `id` の名前で出る（`[proxy-test]: ...`）。
- 作者は、プロキシ（`localhost:25610`）に入ると、バックエンドに着く。プレイヤーが要る確認（`PostLoginEvent`、サーバーの移動、チャット）は、作者に入ってもらう。
- 止める: `scripts/run-server.ps1 -Stop`（プロキシ、バックエンドの順に止まる）。
- 作者が自分の Velocity に入れたいと言ったら、`build/libs/` の jar を作者の Velocity の `plugins/` に置いて再起動する手順を示す（このスキルは作者のプロキシに触らない）。

## 配布

`scripts/build-release.ps1` が、jar の `velocity-plugin.json`（`id`、`version`、`main`）と、Velocity の API（`com/velocitypowered/`）や Guice を同梱していないかを調べる。Hangar と Modrinth には、Velocity のプラグインとして（プラットフォームに Velocity を選んで）出す（`references/workflows/release.md`）。
