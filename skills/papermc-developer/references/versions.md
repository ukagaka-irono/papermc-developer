# 対応する版と、版ごとの違い

このスキルは、Paper の **1.7.10 から最新（26.x）まで**のプラグインを扱う。古い版のサーバー向けに作る・直すときは、版によって使える API、Java、記述ファイルの書き方が大きく違うので、この表で確かめてから書く。対象の版は、`build.gradle.kts`（または `pom.xml`）の API の依存で決まる（`scripts/doctor.ps1` と `scripts/versions.ps1` が表示する）。

**この表の値はスクリプトと同じ**（`scripts/lib/common.ps1` の `Get-PaperDevEra` と `Get-PaperDevApiDependency`）。版ごとの値を確かめるときは `scripts/versions.ps1 -Minecraft <版>` を使う。

## API の依存（`compileOnly`）

| Minecraft | 依存 | 置き場所 |
|---|---|---|
| 26.1 〜 | `io.papermc.paper:paper-api:<版>.build.+` | `https://repo.papermc.io/repository/maven-public/` |
| 1.17 〜 1.21.11 | `io.papermc.paper:paper-api:<版>-R0.1-SNAPSHOT` | 同上 |
| 1.9.4 〜 1.16.5 | `com.destroystokyo.paper:paper-api:<版>-R0.1-SNAPSHOT` | 同上 |
| 1.7.10、1.8.8 | `org.github.paperspigot:paperspigot-api:<版>-R0.1-SNAPSHOT` | 同上 |

## 版ごとの違い

| | 1.7.10 〜 1.12.2 | 1.13 〜 1.16.5 | 1.17 〜 1.18.1 | 1.18.2 〜 1.20.4 | 1.20.5 / 1.20.6 〜 1.21.11 | 26.1 〜 |
|---|---|---|---|---|---|---|
| サーバーの Java | 8 | 8〜11 | 17 | 17〜21 | 21〜25 | 25〜 |
| ビルドの Java（ツールチェーン） | 8 | 8 | 17 | 17 | 21 | 25 |
| `api-version` | 無い（書いても無視） | `'1.13'` 〜 `'1.16'`（`1.<マイナー>` だけ） | `'1.17'` / `'1.18'` | `'1.18'` 〜 `'1.20'` | `'1.20.5'` 以降は 3 桁も可 | `'26.3'` など |
| コマンド | `plugin.yml` の `commands:` と `CommandExecutor` | 同左 | 同左 | 同左 | 1.20.6 から Brigadier（ライフサイクル API）。`plugin.yml` の書き方も使える | Brigadier |
| メッセージ | `ChatColor` と `&` / `§` の色コード（文字列） | 同左（1.16.5 から Adventure の `Component` も） | `Component`（Adventure） | `Component` と MiniMessage | 同左 | 同左 |
| `paper-plugin.yml` | 無い | 無い | 無い | 1.19.3 から（実験的） | テンプレートは 1.20.6 から | ある |
| 素材名 | 数値 ID と古い名前（`WOOL` に data 値） | 1.13 で平坦化（`WHITE_WOOL`） | | | | |
| MockBukkit（テンプレートのテスト） | 無し | 無し | 無し | 無し | 1.21 から | ある |
| テストサーバーのワールド | 普通のワールド | 普通のワールド | 普通のワールド | 1.19 からフラット | フラット | フラット |

- 1.7.10 のサーバーが要求する Java は 6 以上だが、このスキルは Java 8 で作り、動かす。
- **古いサーバーは新しい Java では起動しない。** 1.16.5 以前は Java 8（1.13 以降は 11 まで）、1.17 は Java 17。テストサーバーには、その版に合う JDK が要る（`scripts/doctor.ps1` の `server-java`）。無ければ、作者に確かめてから `scripts/setup.ps1 -Jdk 8` などで Eclipse Temurin を入れる。
- Gradle 自体は Java 17 以上で動く。古い版のプラグインも、ビルドは Gradle のツールチェーンが Java 8 などの JDK を使う（無ければ foojay-resolver が取ってくる）。

## Folia と Velocity の版

- Folia のビルドは 1.19.4 以降の一部の版だけ（`scripts/versions.ps1` の `Folia versions`）。`folia-supported: true` はそれより前の Paper では無視されるだけなので、古い版向けのプラグインに書いても害は無いが、Folia で確かめられるのはビルドのある版だけ。
- Velocity は Minecraft の版とは別の版を持つ（3.x は Java 21、4.x は Java 25）。1 つの Velocity が、古い版から新しい版までのクライアントとサーバーをつなぐ。プラグインは、作者が使う Velocity の版の `velocity-api` でビルドする（`references/velocity.md`）。

## 古い版で書くときの注意

- **使える API は、その版の Javadoc で確かめる。** 新しい版のメソッドを書くとコンパイルで落ちる（`scripts/check.ps1`）。PaperMC のドキュメントは最新の版のもので、古い版には無いものが多い。古い版の Javadoc は `https://jd.papermc.io/paper/<1.マイナー>/`（例: `https://jd.papermc.io/paper/1.16/`、`https://jd.papermc.io/paper/1.12/`、`https://jd.papermc.io/paper/1.8/`）。1.7.10 は PaperMC に無いので、第三者が置いた Bukkit の Javadoc（`https://helpch.at/docs/1.7.10/`）を参考にし、最後はコンパイルで確かめる。
- Java の書き方も、その Java の版に合わせる（Java 8 では `var`、`switch` 式、テキストブロック、`record`、`List.of` が使えない）。
- 1.12.2 以前の素材は、新しい名前（`Material.WHITE_WOOL` など）が無い。複数の版で動かすなら、`Material.matchMaterial` で名前から引くか、版ごとに分ける。
- 1.16.4 以前は Adventure が無いので、メッセージは `ChatColor.translateAlternateColorCodes('&', 文字列)` で作る（テンプレートの書き方）。Adventure を jar に同梱する方法もあるが、作者に確かめてから。
- 1.20.5 以前のサーバーは、`api-version` に `1.<マイナー>` しか受け付けない（`'1.16.5'` と書くと読み込まれない）。`scripts/check.ps1` が見つける。
- 1.13 以前の非同期処理、スケジューラ、イベントの基本は今と同じ（`BukkitScheduler`、`@EventHandler`）。Folia は 1.19.4 から。

## 複数の版で動かす

1 つの jar で古い版から新しい版まで動かしたいときは、**いちばん古い版の API でビルドする**（新しい版の API は使えない）。新しいサーバーは古い API をおおむね受け付けるが、`api-version` が無いと古い素材名に変換する互換モードになる。どこまでを対象にするか、作者と決めて `PLUGIN.md` の「対象」に書く。動作は、対象の端の版（いちばん古い版と、いちばん新しい版）のテストサーバーで確かめる（`scripts/run-server.ps1 -Minecraft <版>`）。
