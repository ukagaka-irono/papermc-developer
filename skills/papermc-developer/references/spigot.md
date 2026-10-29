# Spigot と CraftBukkit のプラグイン

CraftBukkit は Bukkit API の元の実装、Spigot はそれに手を入れた（速さと、BungeeCord のチャット API などを足した）サーバー、Paper は Spigot をさらに改良したもの。**Bukkit API だけで書いたプラグインは、CraftBukkit、Spigot、Paper のどれでも動く。** Spigot の追加 API を使うと CraftBukkit では動かず、Paper の API（Adventure、MiniMessage、Brigadier のライフサイクル API、`paper-plugin.yml`、Folia のスケジューラなど）を使うと Spigot と CraftBukkit では動かない。

| 書いた API | CraftBukkit | Spigot | Paper |
|---|---|---|---|
| Bukkit API だけ | 動く | 動く | 動く |
| ＋ Spigot の追加（`player.spigot()`、`net.md_5.bungee.api.chat`） | 動かない | 動く | 動く |
| ＋ Paper の API | 動かない | 動かない | 動く |

作者の利用者が Spigot や CraftBukkit のサーバーを使っているとき、または「どのサーバーでも動くように」と頼まれたときは、Spigot / CraftBukkit 向けに作る。Paper だけで十分なら、Paper 向け（既定）のほうが新しい API を使える。

## 作る

- Spigot: `scripts/new-plugin.ps1 -Name <名前> -Spigot`（`-Minecraft <版>`。既定は BuildTools が作れるいちばん新しい版）
- CraftBukkit: `scripts/new-plugin.ps1 -Name <名前> -CraftBukkit`

| | Spigot | CraftBukkit |
|---|---|---|
| 依存 | `org.spigotmc:spigot-api:<版>-R0.1-SNAPSHOT` | 1.15.2 まで `org.bukkit:bukkit:<版>-R0.1-SNAPSHOT`、それより後は `spigot-api`（Bukkit の部分だけを使う。`build.gradle.kts` の先頭の `papermc-developer: platform=craftbukkit` が目印） |
| リポジトリ | `https://hub.spigotmc.org/nexus/content/repositories/snapshots/` | 同左 |
| 版 | 1.8 から（BuildTools が作れる版。`scripts/versions.ps1`） | 同左 |
| Java | BuildTools が版ごとに決める範囲（26.3 は 25〜26、1.16.5 は 8〜16、1.12.2 は 8〜10 など） | 同左 |
| コマンド | `plugin.yml` の `commands:` と `CommandExecutor`（Brigadier のライフサイクル API は Paper だけ） | 同左 |
| メッセージ | `ChatColor` と `&` の色コード（Adventure と MiniMessage は Paper だけ）。Spigot なら BungeeCord のチャット API（`player.spigot().sendMessage(TextComponent)`）でクリックやホバーも作れる | `ChatColor` と色コードだけ |
| テスト | 無し（MockBukkit のテンプレートは Paper の API 用）。テストサーバーで確かめる | 同左 |

`api-version`、素材名、古い版の書き方の注意は Paper と同じ（`references/versions.md`）。

## 書くときの注意

- **Paper の API を使わない。** Spigot / CraftBukkit 向けのプロジェクトは `spigot-api`（または `bukkit`）でコンパイルするので、Paper だけの API はコンパイルで落ちる（`scripts/check.ps1`）。ネットや知識にある Paper の書き方（`Component`、`sendRichMessage`、`AsyncChatEvent`、`teleportAsync`、`getLifecycleManager`）を持ち込まない。
- **CraftBukkit 向けでは、Spigot の追加も使わない。** 1.16 以降は `spigot-api` でコンパイルするので、`player.spigot()` や `net.md_5.bungee` はコンパイルが通ってしまう。`scripts/check.ps1` が見つけて error にする。
- Javadoc: Spigot は https://hub.spigotmc.org/javadocs/spigot/ （最新の版。SpigotMC のサイトは、自動の読み取りを 403 で断ることがある）。読めないときや古い版、Bukkit の部分は、Paper の Javadoc（`https://jd.papermc.io/paper/<1.マイナー>/`）の `org.bukkit` パッケージを見る（Paper にしかないクラスやメソッドがあるので、最後はこのプロジェクトのコンパイルで確かめる）。
- スケジューラ、イベント、設定、PDC（1.14 以降）、権限は Bukkit API のまま使える（`references/paper-api.md` の Paper だけのもの以外）。非同期とメインスレッドの決まりも同じ。

## テストサーバー（BuildTools）

SpigotMC は、Spigot と CraftBukkit のサーバーの jar を配布していない（Minecraft のサーバーのコードを含むため）。**BuildTools**（SpigotMC の公式の道具）で、手元で作るのが唯一の方法。

1. 作者に確かめる: 「Spigot（または CraftBukkit）<版> のテストサーバーを作るには、SpigotMC の BuildTools をダウンロードして動かします。BuildTools は Minecraft のサーバーと SpigotMC のソースを取ってきてコンパイルします（数分〜十数分、ホームフォルダに 1 GB ほど）。進めてよいですか？」。了承が無ければ作らない（Paper のテストサーバーで確かめる、作者自身のサーバーで確かめる、を提案する）。
2. 了承を得てから `scripts/setup.ps1 -BuildServer spigot -Minecraft <版>`（CraftBukkit なら `-BuildServer craftbukkit`）。BuildTools の要る Java がインストールされている JDK から選ばれる。無ければ `scripts/setup.ps1 -Jdk <n>`（これも作者に確かめてから）。Windows では Git for Windows が要る（BuildTools は `sh` を使う。スクリプトが Git の `bin` を PATH に足し、長いパスも有効にして動かす。作者の Git の設定は変えない）。26.3 のビルドで 10 分ほどかかった。
   - できた jar は `<ホームフォルダ>/cache/spigot/spigot-<版>.jar`（`craftbukkit-<版>.jar`）。版ごとに 1 回でよい。BuildTools の作業フォルダは `<ホームフォルダ>/bt/`（Windows のパスの長さの制限に当たらないよう短くしてある。消してよい。次に作るとき、また取ってくる）。
   - 失敗したら、表示された BuildTools のログの最後を読む（Java の版が合わない、ネットワーク、Git が無い、が多い）。
3. `scripts/run-server.ps1`（Spigot / CraftBukkit 向けのプロジェクトなら自動でそのサーバー）。Paper 向けのプラグインが Spigot でも動くかを見るときは `-Platform spigot`（Paper の API を使っていれば `NoClassDefFoundError: io/papermc/paper/...` で読み込まれず、終了コード 2 になる）。サーバーの種類ごとに別のフォルダとワールドを使う（ある種類が作ったワールドは、ほかの種類で読めないことがある）。RCON、`rcon.ps1`、`server-log.ps1` は Paper と同じように使える。
4. 「どのサーバーでも動く」と言うには、対象のサーバーそれぞれで確かめる（`-Platform craftbukkit`、`-Platform spigot`、`-Platform paper`）。

作った jar を配布したり、作者のリポジトリに入れたりしない（SpigotMC の配布の決まり）。

## 配布

SpigotMC のリソース（https://www.spigotmc.org/resources/ ）に出すのは、作者が Web で行う（このスキルはアップロードしない）。Hangar と Modrinth にも、Spigot / Bukkit 向けとして出せる（Modrinth ならローダーに Spigot、Bukkit、Paper など動くものを選ぶ）。`scripts/build-release.ps1` は、サーバーの API（`org/bukkit`、`net/md_5/bungee` など）を jar に同梱していないかを調べる。
