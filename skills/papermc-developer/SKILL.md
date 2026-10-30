---
name: papermc-developer
description: Minecraft の PaperMC のプラグイン（Paper サーバー用（Bukkit/Spigot 互換の plugin.yml と、paper-plugin.yml。Paper 1.7.10 から最新の 26.x まで）、Folia 対応、Velocity プロキシ用、Spigot / CraftBukkit 用）を作る・直す・動かして確かめる・配布する。新しいプラグインのひな形を作る、コマンド・イベント・設定・権限・スケジューラ・データベース（SQLite、MySQL）などのコードを書く、ビルドやテストのエラーを直す、テスト用の Paper / Folia / Spigot / CraftBukkit サーバー（Spigot と CraftBukkit は BuildTools で作る）や Velocity プロキシ（と後ろの Paper サーバー）を立ててコマンドを送りログを見る、配布用の jar を作って GitHub Releases / Hangar / Modrinth に出す、Paper の版（paper-api、Java）を上げる、といったとき。settings.gradle.kts / build.gradle.kts（または pom.xml）と src/main/resources/plugin.yml（Velocity なら velocity-api の依存と @Plugin）のあるフォルダが対象。Minecraft plugin, SQLite, MySQL, JDBC, Paper, Spigot, CraftBukkit, Bukkit, BuildTools, Folia, Velocity, proxy, Brigadier, Adventure, MiniMessage, MockBukkit, run-paper, run-velocity の話題を含む。
allowed-tools:
  - 'Bash(powershell -NoProfile -ExecutionPolicy Bypass -File ${CLAUDE_SKILL_DIR}/scripts/doctor.ps1*)'
  - 'Bash(powershell -NoProfile -ExecutionPolicy Bypass -File ${CLAUDE_SKILL_DIR}/scripts/versions.ps1*)'
  - 'Bash(powershell -NoProfile -ExecutionPolicy Bypass -File ${CLAUDE_SKILL_DIR}/scripts/check.ps1*)'
  - 'Bash(powershell -NoProfile -ExecutionPolicy Bypass -File ${CLAUDE_SKILL_DIR}/scripts/server-log.ps1*)'
  - 'Bash(powershell -NoProfile -ExecutionPolicy Bypass -File ${CLAUDE_SKILL_DIR}/scripts/update-paper.ps1 -DryRun*)'
  - 'PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File ${CLAUDE_SKILL_DIR}/scripts/doctor.ps1*)'
  - 'PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File ${CLAUDE_SKILL_DIR}/scripts/versions.ps1*)'
  - 'PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File ${CLAUDE_SKILL_DIR}/scripts/check.ps1*)'
  - 'PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File ${CLAUDE_SKILL_DIR}/scripts/server-log.ps1*)'
  - 'PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File ${CLAUDE_SKILL_DIR}/scripts/update-paper.ps1 -DryRun*)'
  - 'WebFetch(domain:docs.papermc.io)'
  - 'WebFetch(domain:jd.papermc.io)'
  - 'WebFetch(domain:fill.papermc.io)'
  - 'WebFetch(domain:docs.mockbukkit.org)'
  - 'WebFetch(domain:papermc.io)'
---

# papermc-developer

Minecraft の **PaperMC** のプラグインを、AI と一緒に作る・直す・動かして確かめる・配布するためのスキル。対象は **Paper のプラグイン（1.7.10 から最新の 26.x まで）、その Folia 対応、Velocity（プロキシ）のプラグイン、Spigot / CraftBukkit のプラグイン**。Velocity のプラグインは Paper のプラグインとは別物（`references/velocity.md`）。版によって使える API、Java、記述ファイルの書き方が違う（`references/versions.md`）。作者（ユーザー）は「何を作りたいか」に集中し、決まった作業（環境の準備、ビルドとテスト、テストサーバーでの確認、配布用 jar の作成、版の更新）はこちらで引き受ける。

作者は、スキルの名前もコマンドも知らない。「〜して」という普通の言葉で頼まれる。何ができるかを聞かれたときや、準備を終えたときは、「〜と頼んでください」の形で例を示す。作者が Java や Gradle に慣れているとは限らない。説明は、何が起きたか・次に何をするかを先に、用語は短く添える程度にする。

## このスキルのフォルダ

この文書（`SKILL.md`）のあるフォルダを「スキルのフォルダ」と呼ぶ。以降の `scripts/`、`references/`、`templates/` は、すべてそこからの相対パス。

```
SKILL.md
scripts/       実行する（共通の部品は scripts/lib/）
references/    引く。必要な文書だけを読む（下の「こう頼まれたら」と「資料」）
  workflows/   作業ごとの手順書
templates/     新しいプロジェクトのひな形（project/、descriptor/）と、プロジェクトに足す入門用ファイル（PLUGIN.md など）
```

- スクリプトは `powershell -NoProfile -ExecutionPolicy Bypass -File <スキルのフォルダ>/scripts/<名前>.ps1 ...` で呼ぶ（macOS / Linux では `pwsh -NoProfile -File ...`）。Claude Code では `${CLAUDE_SKILL_DIR}/scripts/doctor.ps1` のように書ける（展開されないエージェントでは、スキルのフォルダのフルパスに読み替える）。**作業フォルダはプラグインのプロジェクトのルート**（`settings.gradle.kts` や `pom.xml` のあるフォルダ）。別の場所からは `-ProjectRoot <フォルダ>`。
- スキルのフォルダには**書き込まない**（プラグインの更新で置き換わる）。ダウンロードした Gradle とサーバーの jar、テストサーバー、設定（`local.json`）は、ホームフォルダ（`%LOCALAPPDATA%\papermc-developer`、環境変数 `PAPERMCDEV_HOME` で変更可）に置かれる。プロジェクトのフォルダには、ビルドの成果物（`build/`）以外は増やさない。
- 終了コードは、どのスクリプトも 0 OK / 1 失敗 / 2 注意が要る / 3 道具が無くて確かめられない。一覧は `references/commands.md`。

## 作業を始める前に

1. **プロジェクトのルートの `PLUGIN.md` を読む。** 何をするプラグインか、対象のサーバーと Java、コマンドと権限、設定、決まり、動作確認の手順など、このプラグインに固有の情報はそこにある。無い、または先頭に `<!-- papermc-developer:plugin-template -->` が残っている（まだ書かれていない）ときは、`references/workflows/setup.md` に沿って、コードを読んで下書きすることを作者に提案する。
2. **`scripts/doctor.ps1` を実行する**（何も変更しない）。プロジェクト、`plugin.yml` か `paper-plugin.yml` か、対象の Minecraft の版と必要な Java、ビルドの道具、足りないものと直し方が出る。`required` が足りなければ、ほかの作業の前に `references/workflows/setup.md` を提案する。
3. プロジェクトがまだ無いとき（空のフォルダで「プラグインを作りたい」と言われたとき）は、`references/workflows/new-plugin.md`。
4. **版は推測しない。** Minecraft と Paper の版、必要な Java、API の依存の書き方、Gradle プラグインの版は、時期で変わる（26.1 から版の付け方も変わった）。知識で書かず、`scripts/versions.ps1`（別の版は `-Minecraft <版>`）で今の値を見る。
5. **対象の版を確かめる。** 1.20.4 以前（とくに 1.16.5 以前）のプラグインは、コマンド、メッセージ、`api-version`、Java、素材名が今とは違う。コードを書く前に `references/versions.md` を読み、その版の API で書く。

## こう頼まれたら

対応する手順書を**読んでから**作業する。

| 作者の言い方（例） | 読むもの |
|---|---|
| 「セットアップして」「始めたい」「足りないものを入れて」「PLUGIN.md を書いて」 | `references/workflows/setup.md` |
| 「プラグインを作りたい」「新しいプロジェクトを作って」「ひな形を作って」 | `references/workflows/new-plugin.md` |
| 「コマンドを足して」「〜したら〜する機能を作って」「設定で変えられるようにして」「この動きを直して」 | `references/paper-api.md`（書き方）のあと、`references/workflows/check.md` で確かめる |
| 「ビルドして」「チェックして」「エラーを直して」「テストが落ちる」 | `references/workflows/check.md` |
| 「テストを書いて」「テストで確かめて」 | `references/testing.md` |
| 「サーバーで試して」「動かして見せて」「このコマンドを打ってみて」「ログを見て」「サーバーでエラーが出る」 | `references/workflows/try-on-server.md` |
| 「配布用の jar を作って」「リリースしたい」「Hangar（Modrinth）に出したい」 | `references/workflows/release.md` |
| 「GitHub でビルドしたい」「Actions を入れて」「タグでリリースしたい」 | `references/workflows/ci.md` |
| 「ブランチを分けたい」「develop を作って」「作業用のブランチを作って」「develop にマージして」 | `references/workflows/branches.md` |
| 「Paper を最新にして」「1.21 から 26 に上げて」「対応バージョンを上げて」「今の最新は？」 | `references/workflows/update-paper.md` |
| 「1.8.8 用のプラグインを作って」「1.12.2 のサーバーで動くようにして」「古い版にも対応したい」 | `references/versions.md`（作るなら `references/workflows/new-plugin.md`） |
| 「Folia に対応して」「Folia でも動くようにして」「Folia で試して」 | `references/paper-api.md` の「Folia」 |
| 「Spigot 用に作って」「CraftBukkit でも動くようにして」「Bukkit のプラグイン」「Spigot のサーバーで試して」 | `references/spigot.md`（作るなら `references/workflows/new-plugin.md`） |
| 「データを保存したい」「SQLite に保存して」「MySQL に対応して」「データベースを使いたい」 | `references/database.md`（作るなら `new-plugin.ps1 -Database`） |
| 「Velocity のプラグインを作って」「プロキシ用のプラグイン」「BungeeCord から Velocity に移したい」「サーバー間を移動させたい」 | `references/velocity.md`（作るなら `references/workflows/new-plugin.md`） |
| 「スキルを更新して」「papermc-developer を最新にして」 | `references/workflows/update-skill.md` |

## 作業のルール

0. **ブランチは `main` / `develop` / `〇〇〇〇-fix` に分ける**（`references/workflows/branches.md`）。Git で管理しているプロジェクトでコードを変えるときは、先に今のブランチを確かめ、`main` か `develop` にいるなら `develop` から `〇〇〇〇-fix`（例: `hello-command-fix`）を作ってから変える。`main` と `develop` には直接コミットしない。作業ブランチは `develop` に戻し、リリースのときだけ `develop` を `main` に入れる。コミット、push、Pull Request、マージ、タグは作者に頼まれたときだけ。
1. **コードやビルドの設定、`plugin.yml` / `paper-plugin.yml` を変えたら、必ず `scripts/check.ps1` を通す。** 記述ファイルの検査（main クラスの実在、api-version、`getCommand` と宣言の食い違い）、コンパイル、テストを行う。error が残ったまま「できました」と言わない。非推奨（deprecation）の警告は、新しく書いたコードのものは直す。
2. **動きを確かめるときは、テスト（MockBukkit）とテストサーバーを使い分ける**（`references/testing.md`）。サーバーで確かめるときは `scripts/run-server.ps1` が立てる**テスト用のサーバー**だけを使う（ホームフォルダの中、127.0.0.1 だけで待ち受ける）。作者がふだん使っているサーバーや、公開しているサーバーには、作者に頼まれても、作者が自分で入れる手順を示すにとどめる。
3. **Spigot と CraftBukkit のテストサーバーは BuildTools で作る**（SpigotMC はサーバーの jar を配布していない）。BuildTools は外部のコードをダウンロードして動かすので、作るのは作者の了承を得てから（`references/spigot.md`）。
4. **Minecraft のサーバーを動かすには、作者が Minecraft の EULA（https://aka.ms/MinecraftEULA ）に同意している必要がある。** 同意はこちらで代わりにしない。テストサーバーを初めて使うときは、EULA の場所を示して作者に読んでもらい、作者が同意すると言ったときだけ `scripts/setup.ps1 -AcceptEula` を実行する。
5. 仕様（Paper API のクラスやメソッド、イベント、`plugin.yml` / `paper-plugin.yml` の項目、Brigadier の引数型、Adventure / MiniMessage の書式）を**推測で書かない**。確かでないときは、下の「仕様を調べる」で確かめる。とくに、古い Bukkit / Spigot の書き方（`ChatColor`、`§`、文字列のメッセージ、`getCommand` と `CommandExecutor`、`BukkitRunnable` での世界の操作を非同期で行うことなど）を、知識のままで書かない（`references/paper-api.md` の「AI がやりがちな失敗」）。
6. **サーバーのメインスレッドを止めない。** ファイル、データベース、ネットワークの処理は非同期で行い、ワールドやエンティティ、プレイヤーの操作はメインスレッド（Folia では、その場所のリージョン）に戻して行う。
7. 依存の追加（ライブラリ、ほかのプラグイン）は、何のためか、ライセンス、jar に同梱するのか（shadow）を作者に伝えてから行う。サーバーの API（paper-api、Adventure、Brigadier）は `compileOnly` にし、jar に入れない。
8. **編集しないもの**: `gradle/wrapper/` の中身（版を変えるのは `gradlew wrapper --gradle-version`）、`build/`、`run/`（`./gradlew runServer` の作業フォルダ）、他人のプラグインの jar。サーバーの内部（NMS、`net.minecraft`、paperweight-userdev）を使うのは、API で実現できないと確かめ、作者が版ごとの保守を引き受けると言ったときだけ。
9. 既存のコードや作者が書いたメッセージを、頼まれていないのに大量に書き換えたり消したりしない。使われていないクラスや設定に気づいても、報告するだけにする。
10. **作者の確認を取ってから行うこと**: アプリ（JDK、Git など）のインストール、EULA への同意の記録、Paper の版の更新、スキルの更新、リリース（タグの push、GitHub Releases、Hangar、Modrinth への公開）、ほかのサーバーへの jar の配置など、手元のファイル編集を超える操作。公開用のトークン（Hangar / Modrinth の API キー、GitHub のトークン）を、作者にチャットへ貼らせない。環境変数か、GitHub の Secrets に入れてもらう。
11. `scripts/` の外から papermc-developer のスクリプトを書き換えない。足したい機能は、プロジェクトの側に置くか、https://github.com/ukagaka-irono/papermc-developer に提案する。

## 仕様を調べる

Paper API、イベント、`plugin.yml` / `paper-plugin.yml` の項目、コマンド（Brigadier）、Adventure / MiniMessage、スケジューラ、Folia、MockBukkit の使い方は、推測で書かず、次の順で確かめる。

1. **PaperMC のドキュメント**（https://docs.papermc.io/ ）。AI 向けの目次 **https://docs.papermc.io/llms.txt** を読み、そこにあるページを `index.md` の形で読む（例: `https://docs.papermc.io/paper/dev/command-api/basics/introduction/index.md`）。よく使うもの:
   - プロジェクトの作り方: `/paper/dev/project-setup/index.md`、`plugin.yml`: `/paper/dev/plugin-yml/index.md`、Paper プラグイン: `/paper/dev/getting-started/paper-plugins/index.md`
   - コマンド: `/paper/dev/command-api/...`、イベント: `/paper/dev/event-listeners/index.md`、スケジューラ: `/paper/dev/scheduler/index.md`、設定: `/paper/dev/plugin-configurations/index.md`、PDC: `/paper/dev/pdc/index.md`、Folia: `/paper/dev/folia-support/index.md`、ライフサイクル: `/paper/dev/lifecycle/index.md`
   - Adventure / MiniMessage: `/adventure/minimessage/format/index.md` など
2. **Javadoc**（https://jd.papermc.io/paper/ 。古い版は `https://jd.papermc.io/paper/1.16/` のように版を付ける。`references/versions.md`）。クラスとメソッドの有無、非推奨かどうか、引数。PaperMC のドキュメントは最新の版のことしか書いていないので、古い版で書くときは、その版の Javadoc とコンパイルで確かめる。
3. **このプロジェクトの依存そのもの**。ビルドが通るかは `scripts/check.ps1` で確かめられる。メソッドがあるか迷ったら、小さく書いてコンパイルさせるのが確実。
4. MockBukkit: https://docs.mockbukkit.org/ 。版の値は `scripts/versions.ps1`。
5. それでも分からなければ Web 検索する。Spigot のフォーラムや古いブログの書き方は、Paper では非推奨や別の API になっていることが多いので、1. と 2. で確かめ直す。

調べものは、小さく速いモデルのサブエージェントに任せるとよい（Claude Code のプラグインには `papermc-researcher` が入っている）。

## 資料

必要になったときに読む。

| 資料 | 中身 |
|---|---|
| `references/commands.md` | スクリプトの一覧、オプション、終了コード、ホームフォルダ |
| `references/layout.md` | プロジェクトの構成。`build.gradle.kts`、`plugin.yml` と `paper-plugin.yml` の違い、何をコミットするか |
| `references/paper-api.md` | 今の Paper でのコードの書き方の要点と、AI がやりがちな失敗 |
| `references/spigot.md` | Spigot / CraftBukkit のプラグイン: Paper との違い（どの API がどこで動くか）、作り方、BuildTools でのテストサーバー |
| `references/database.md` | SQLite と MySQL: サーバーが同梱するドライバー、ひな形の `Database`、書くときの決まり（スレッド、`PreparedStatement`、両方で通る SQL）、テスト用の MySQL サーバー |
| `references/velocity.md` | Velocity（プロキシ）のプラグイン: 作り方、書き方の要点、AI がやりがちな失敗、テストのプロキシと後ろの Paper サーバー |
| `references/versions.md` | 対応する版（1.7.10〜）と、版ごとの API の依存、Java、`api-version`、コマンドとメッセージの書き方の違い |
| `references/testing.md` | MockBukkit のテストと、テストサーバーでの確認の使い分け |
| `references/ai-guidelines.md` | AI を使ったプラグイン制作の約束（ライセンス、安全、配布先の規則） |

## AI を使ったプラグイン制作の約束

詳しくは `references/ai-guidelines.md`。要点:

- 他人のプラグインのコードを、ライセンスを確かめずにコピーしたり言い換えたりして持ち込まない。
- 作者が頼んでいない、サーバーの運営者やプレイヤーに影響する処理（外部への通信、データの送信、OP の付与、権限の素通し、ファイルの削除、コマンドの実行）を書かない。頼まれたときも、何が起きるかを説明し、設定で切れるようにする。
- 配布先（Hangar、Modrinth）の規則に反するもの（隠れた通信、難読化、ほかのプラグインを勝手に入れるもの）を作らない。
- 作ったものは、作者が中身を確かめてから公開するものとして書く。
