# 今の Paper での書き方

コードを書く・直す前に読む。ここは「どの API を使うか」と「何をしてはいけないか」の要点で、細かい使い方は複製しない。**書く前に、該当するドキュメントのページを読む**（`SKILL.md` の「仕様を調べる」。目次は https://docs.papermc.io/llms.txt ）。Paper は古い Bukkit の API を非推奨にして新しいものに置き換え続けているので、知識にある書き方が今も正しいとは限らない。

**この文書は最新の版（1.20.6 以降）向け。** プロジェクトが 1.20.4 以前を対象にしているとき（`scripts/doctor.ps1` の `target`）は、ここにある API の多く（Brigadier のライフサイクル API、MiniMessage、データコンポーネント、レジストリ、Dialog など）が無い。`references/versions.md` を読み、その版の API で書く。古い版では、下の「AI がやりがちな失敗」の 1〜3 の「古い書き方」が正しい書き方になることもある。迷ったら Javadoc（https://jd.papermc.io/paper/ ）と、`scripts/check.ps1` の非推奨の警告で確かめる。

## 書き方の要点

| やりたいこと | 使うもの | 資料 |
|---|---|---|
| メッセージ、表示名、タイトル、ボスバー | Adventure の `Component`。文字列で書くなら MiniMessage（`MiniMessage.miniMessage().deserialize(...)`、`sendRichMessage(...)`）。プレイヤー名などは `Placeholder` で差し込む | `/paper/dev/component-api/introduction/index.md`、`/adventure/minimessage/format/index.md` |
| コマンド | Brigadier。`onEnable` で `getLifecycleManager().registerEventHandler(LifecycleEvents.COMMANDS, e -> e.registrar().register(...))`。引数は `ArgumentTypes`（プレイヤー、座標、アイテムなど）。権限は `.requires(...)`。単純なものは `BasicCommand` | `/paper/dev/command-api/basics/introduction/index.md` |
| イベント | `Listener` と `@EventHandler`（`priority`、`ignoreCancelled = true`）。`registerEvents` で登録する。チャットは `AsyncChatEvent`（Paper のもの） | `/paper/dev/event-listeners/index.md`、`/paper/dev/chat-events/index.md` |
| 後で・くり返し実行 | `getServer().getScheduler()` の `runTask` / `runTaskLater` / `runTaskTimer`（メインスレッド）、`runTaskAsynchronously`（重い処理）。Folia では下の「Folia」 | `/paper/dev/scheduler/index.md` |
| 設定 | `saveDefaultConfig()`、`getConfig()`、`reloadConfig()`。独自のファイルは `YamlConfiguration.loadConfiguration(file)` | `/paper/dev/plugin-configurations/index.md` |
| アイテムやエンティティにデータを付ける | Persistent Data Container（`NamespacedKey(plugin, "key")` と `PersistentDataType`） | `/paper/dev/pdc/index.md` |
| アイテムの見た目や性質 | `ItemStack#editMeta`、データコンポーネント API | `/paper/dev/data-component-api/index.md` |
| エンチャント、バイオームなどの取得 | レジストリ（`RegistryAccess.registryAccess().getRegistry(RegistryKey.X)`）。名前の文字列から探す古いメソッドは使わない | `/paper/dev/registries/index.md` |
| テレポート | `teleportAsync`（チャンクの読み込みを待つ） | `/paper/dev/entity-teleport/index.md` |
| インベントリの画面 | 独自の `InventoryHolder` で、どの画面かを判別する（タイトルの文字列で判別しない） | `/paper/dev/custom-inventory-holder/index.md` |
| ダイアログ、表示用エンティティ、パーティクル | Dialog API、Display エンティティ | `/paper/dev/dialogs/index.md`、`/paper/dev/display-entities/index.md` |
| データベース | 接続プール（HikariCP など）を非同期で使う | `/paper/dev/using-databases/index.md` |
| ログ | `getComponentLogger()` か `getSLF4JLogger()`。`System.out` は使わない | |
| ほかのプラグインとの連携 | `plugin.yml` の `depend` / `softdepend`（`paper-plugin.yml` は `dependencies`）を書き、`getServer().getPluginManager().getPlugin(...)` か Services API | `/paper/dev/getting-started/paper-plugins/index.md` |

## スレッド

- サーバーのほとんどの処理は**メインスレッド**で動く。ここで時間のかかること（ファイル、HTTP、データベース、大量のループ）をすると、サーバー全体が止まる（TPS が落ちる）。
- **非同期のスレッドから、ワールド、ブロック、エンティティ、プレイヤーのインベントリを触らない。** 非同期で計算や I/O をして、結果を `runTask` でメインスレッドに戻して反映する。`AsyncChatEvent` などの非同期のイベントの中も同じ。
- メッセージの送信（`sendMessage`）はどのスレッドからでもよい。
- 共有するデータは、スレッドをまたぐなら `ConcurrentHashMap` などにする。

## Folia

Folia（https://papermc.io/software/folia ）は、ワールドを地域（リージョン）に分けて、別々のスレッドで同時に動かす Paper。プレイヤーの多い大きなサーバー向けで、メインスレッドが無い。Folia のビルドがあるのは 1.19.4 以降の一部の版（`scripts/versions.ps1` の `Folia versions`）。Folia のビルドは実験的（Fill API の channel が ALPHA などのことがある）。対応するには:

1. `plugin.yml`（または `paper-plugin.yml`）に `folia-supported: true` を書く。書かないと Folia はプラグインを読み込まない。新しく作るなら `scripts/new-plugin.ps1 -Folia`。
2. 依存は paper-api のままでよい（Folia 用の API は paper-api に入っている。`folia-api` にする必要はない）。こうすると、1 つの jar が Paper でも Folia でも動く。
3. `BukkitScheduler`（`getServer().getScheduler()`、`Bukkit.getScheduler()`、`BukkitRunnable`）を使わない（Folia では `UnsupportedOperationException`）。代わりに、場所に結びつく処理は `getServer().getRegionScheduler()`、エンティティ（プレイヤーを含む）に結びつく処理は `entity.getScheduler()`、どこにも結びつかない処理は `getServer().getGlobalRegionScheduler()`、非同期は `getServer().getAsyncScheduler()`。これらは Paper でも動く（Paper では今までどおりメインスレッドで動く）ので、両対応のプラグインはこちらに統一する。`scripts/check.ps1` は、`folia-supported: true` のプラグインで BukkitScheduler を見つけると error にする。
4. **あるリージョンのスレッドから、別のリージョンのブロックやエンティティを触らない。** イベントは、そのイベントの場所（プレイヤーなど）のリージョンのスレッドで呼ばれる。ほかのプレイヤーやほかの場所を触るときは、相手の `entity.getScheduler()` や、その場所の `getRegionScheduler()` に処理を渡す。全プレイヤーへのループ（`getOnlinePlayers()` で各プレイヤーを操作するなど）も、プレイヤーごとにそのスケジューラへ渡す。
5. テレポートは `teleportAsync()`（`check.ps1` は `teleport(` を warning にする）。
6. 静的なフィールドやプラグインのフィールドを、複数のリージョンから同時に読み書きする（スレッドが違う）。`ConcurrentHashMap`、`AtomicInteger` などにする。
7. 実行中の環境が Folia かどうかで処理を変えるなら、`io.papermc.paper.threadedregions.RegionizedServer` のクラスがあるかで判断する（`/paper/dev/folia-support/index.md` の `isFolia()`）。
8. **確かめるのは Folia のサーバーで**: `scripts/run-server.ps1 -Platform folia`（プロジェクトの版に Folia のビルドが無ければ `-Minecraft <Folia のある版>`）。Paper のサーバーでも動くことを、ふだんの `scripts/run-server.ps1` で確かめる。

資料: `/paper/dev/folia-support/index.md`、Folia の仕組み: `/folia/reference/overview/index.md`

## AI がやりがちな失敗

古い情報（Spigot 時代のフォーラムや記事）に引きずられた書き方。`scripts/check.ps1` の非推奨の警告にも出るので、新しく書いたコードの警告は直す。

1. **`ChatColor` や `§` の色コード、文字列のメッセージ**（`sendMessage("§aHello")`、`setDisplayName(String)`）。→ Adventure の `Component` と MiniMessage。
2. **`AsyncPlayerChatEvent`**。→ `io.papermc.paper.event.player.AsyncChatEvent`。
3. **`plugin.yml` に書いていないコマンドを `getCommand("x")` で取る**（null で `NullPointerException`）。Paper プラグインではそもそも使えない。→ Brigadier（`check.ps1` が見つける）。
4. **非同期のスレッドからワールドを触る**、**メインスレッドで I/O をする**（上の「スレッド」）。
5. **`Player` を Map やフィールドに持ち続ける**（退出後も残り、メモリを食う）。→ `UUID` で持ち、`PlayerQuitEvent` で消す。名前（`getName()`）は変わるので、データの鍵にしない。
6. **`Bukkit.getOfflinePlayer(String 名前)`** をメインスレッドで呼ぶ（Mojang への問い合わせで止まる）。→ UUID で引く、`getOfflinePlayerIfCached`。
7. **paper-api を `implementation` にして jar に入れる**（`references/layout.md`）。
8. **`api-version` を書かない、またはビルドより新しい版にする**（`check.ps1` が見つける）。
9. **`saveResource("config.yml", true)` で、利用者が変えた設定を毎回上書きする**。→ `saveDefaultConfig()`（無いときだけ書く）。設定に項目を足したら、既定値をコード側にも持つ（`getString("key", "既定")`）。
10. **`/reload` での再読み込みを前提にする**。Paper は `/reload` を勧めていない。確かめるときはサーバーを再起動する（`run-server.ps1` がそうする）。
11. **イベントリスナーの登録忘れ**、`@EventHandler` の付け忘れ（メソッドが呼ばれない。エラーも出ない）。
12. **NMS（`net.minecraft`、CraftBukkit のクラス）やリフレクションに手を出す**。版ごとに壊れる。API で無理なときだけ、作者と相談して paperweight-userdev を使う。
13. **main クラスを `final` にしたまま MockBukkit で読み込む**（`Cannot subclass ... final types`）。テンプレートの main クラスが `final` でないのはそのため。
14. 存在しないメソッドやイベントを「ありそう」で書く。書いたら必ずコンパイルする（`check.ps1`）。
