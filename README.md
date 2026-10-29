# papermc-developer

Minecraft の **PaperMC**（[Paper](https://papermc.io/software/paper)、[Folia](https://papermc.io/software/folia)、[Velocity](https://papermc.io/software/velocity)）のプラグインを、AI と一緒に作る・直す・動かして確かめる・配布するための**スキル**です。Bukkit/Spigot 互換の `plugin.yml` のプラグインと、`paper-plugin.yml` の Paper プラグインに対応し、Folia への対応も手伝います。**Paper 1.7.10 から最新の 26.x まで**、どの版のサーバー向けにも作れます。Folia（リージョンごとに並列で動く Paper）で動くプラグイン、Velocity（プロキシ）のプラグイン、Spigot / CraftBukkit でも動く Bukkit API だけのプラグインも作れます。

日本語で「〜するプラグインを作って」「エラーを直して」「サーバーで動かして見せて」と頼むだけで、AI が次のことをします。

| | |
|---|---|
| 作る | 対象の版に合わせたプロジェクトのひな形（Gradle、Java、コマンド、メッセージ、テスト）。最新の版なら Brigadier と MiniMessage と MockBukkit、1.8.8 などの古い版なら `plugin.yml` のコマンドと色コードと Java 8、というように、API の依存、Java、`api-version` まで版ごとに変わる。版はその場で調べる |
| 書く | コマンド、イベント、設定、権限、スケジューラ、PDC、データベース（SQLite / MySQL）など。対象の版の API で書く（最新の版では、AI がやりがちな古い書き方（`ChatColor`、`getCommand` の宣言漏れ、非同期でのワールド操作など）を避け、古い版では、その版に無い API を使わない） |
| 確かめる | 記述ファイルの検査、コンパイル、テストを 1 回で行い、エラーを `ファイル:行` で示して直す。javac の表示が日本語でも読む |
| 動かして見せる | 作者のサーバーとは別のテスト用 Paper / Folia / Spigot / CraftBukkit サーバー（Spigot と CraftBukkit は、作者の了承を得て BuildTools で作る）、または Velocity プロキシとその後ろの Paper サーバーをバックグラウンドで立て、プラグインが有効になったか、ログのエラーを報告する。RCON でコマンドを送って結果を見る。作者はクライアントで `localhost` に入って触れる |
| 配布する | 中身を検査した配布用 jar（サーバーの API を同梱していないか、版が埋まっているか）。GitHub Actions、GitHub Releases、Hangar、Modrinth への公開の手伝い |
| 更新する | Paper / Minecraft の版を上げる（paper-api、Java、MockBukkit、ワークフローをまとめて直し、ビルドを確かめる） |

## 必要なもの

| | |
|---|---|
| AI と会話できる開発道具 | Claude Code、Codex、Antigravity など |
| JDK | Gradle を動かす Java 17 以上。テストサーバーには、その版のサーバーが動く Java（1.16.5 以前は 8、1.17〜1.20.4 は 17、1.20.5〜1.21 は 21、26.x は 25）。入っている JDK から自動で選び、無ければ AI が確認したうえで Eclipse Temurin を入れます |
| PowerShell | スクリプトが PowerShell で書かれています。Windows では最初から入っているもの（5.1）で動きます。macOS / Linux では PowerShell 7（`pwsh`）を入れてください |
| Minecraft の EULA への同意 | テストサーバーを動かすときだけ。最初に使うときに AI が確認します |

Gradle や Paper のサーバーは、スクリプトが必要なときに取ってきます（SHA-256 を確かめて、ホームフォルダに置きます）。

## インストール

### Claude Code の場合（プラグイン）

プラグインのプロジェクトのフォルダ（これから作るなら、空のフォルダ）で Claude Code を開いて、

```
claude plugin marketplace add ukagaka-irono/papermc-developer
claude plugin install papermc-developer --scope project
```

入れたら、**Claude Code をいったん終了して、開き直します**（入れた直後のセッションには読み込まれません）。`claude plugin list` に `papermc-developer` が出れば成功です。

| | |
|---|---|
| `--scope project` | いま開いているプロジェクトだけ（`.claude/settings.json` に記録され、リポジトリで共有される） |
| `--scope user` | どのプロジェクトでも |
| `claude plugin uninstall papermc-developer --scope project` | 消す。入れたときと同じ `--scope` を渡す |

プラグインには、スキルのほか、仕様調査用のサブエージェント（`papermc-researcher`）が入っています。

### Codex / Antigravity など、フォルダのコピーで入れる場合

このページの **Code** → **Download ZIP** で落として展開し、中の `skills/papermc-developer/` を、プロジェクトのフォルダの `.agents/skills/` に置きます。

```
プロジェクト\
  .agents\
    skills\
      papermc-developer\
        SKILL.md
        scripts\
        references\
        templates\
  src\
  build.gradle.kts
```

どのプロジェクトでも使うなら、Codex は `%USERPROFILE%\.agents\skills\`、Antigravity は `%USERPROFILE%\.gemini\antigravity\skills\` に置きます。置いたら、いったん終了して開き直します。

## 使いかた

日本語でそのまま頼みます。

```
セットアップして
夜をスキップする投票のプラグインを作りたい
Folia でも動くようにして
Velocity のプラグインを作って
Spigot でも動くように作って
プレイヤーのデータを MySQL に保存できるようにして
/home コマンドを足して
チェックして
サーバーで動かして見せて
配布用の jar を作って
Paper を最新にして
```

必要になった資料とスクリプトを AI が自分で読んで、使います。何ができるのかは、「できる？」と聞けば答えます。

## プロジェクトの側に残るもの

スキルはプロジェクトにスクリプトをコピーしません。プロジェクトに置くのは、プロジェクトのものである次のファイルだけです。

| ファイル | 内容 |
|---|---|
| `PLUGIN.md` | そのプラグインに固有の情報（何をするか、対象の版、コマンドと権限、設定、決まり、動作確認の手順）。AI が作業の前に読む。「セットアップして」で、コードから下書きしてもらえる |
| `AGENTS.md`、`CLAUDE.md` | `PLUGIN.md` を読むこと、スキルを使うことだけを書いた短い案内 |
| `.gitignore`、`.gitattributes`、`.editorconfig` | リポジトリの設定（無いときだけ） |
| `.github/workflows/check.yml`、`release.yml` | GitHub で push ごとのビルド、タグでのリリース（任意） |

ダウンロードした Gradle とサーバーの jar、テストサーバー、設定（`local.json`）は、ホームフォルダ（`%LOCALAPPDATA%\papermc-developer`。環境変数 `PAPERMCDEV_HOME` で変えられます）に置かれます。

## テストサーバーについて

- 作者がふだん使っているサーバーとは別に、ホームフォルダの中に、プロジェクトごとのテスト用 Paper サーバーを作ります。`127.0.0.1` だけで待ち受けるので、ほかの PC からは入れません。
- Minecraft のサーバーを動かすには、[Minecraft の EULA](https://aka.ms/MinecraftEULA) への同意が必要です。AI は、作者が同意すると答えたときだけ、それを記録します（`scripts/setup.ps1 -AcceptEula`）。
- 自分のターミナルでサーバーのコンソールを触りたいときは、ひな形に入っている run-paper の `./gradlew runServer` も使えます。

## 許可の確認を減らす

Claude Code は、スクリプトを実行するたびに許可を確認します。このスキルは、読み取りや検査だけのスクリプト（`doctor`、`versions`、`check`、`server-log`、`update-paper -DryRun`）を `SKILL.md` の `allowed-tools` で許可していますが、**許可されるのは、スキルを使っているターンの間だけ**です。毎回の確認が煩わしいときは、Claude Code に `/fewer-permission-prompts` を実行させるか、`.claude/settings.json` の `permissions.allow` に規則を足します。

```json
{
  "permissions": {
    "allow": [
      "Bash(powershell -NoProfile -ExecutionPolicy Bypass -File *papermc-developer*scripts/doctor.ps1*)",
      "Bash(powershell -NoProfile -ExecutionPolicy Bypass -File *papermc-developer*scripts/check.ps1*)",
      "Bash(powershell -NoProfile -ExecutionPolicy Bypass -File *papermc-developer*scripts/server-log.ps1*)"
    ]
  }
}
```

`run-server.ps1` はサーバーを起動し、`rcon.ps1` はサーバーにコマンドを送ります。許可に加えるかは、そのつもりで決めてください。

## 更新

| 入れ方 | 更新 |
|---|---|
| Claude Code のプラグイン | `claude plugin marketplace update papermc-developer` のあと `claude plugin update papermc-developer`。更新したら Claude Code を再起動 |
| フォルダのコピー | AI に「スキルを更新して」と頼む（`scripts/update-skill.ps1`）。または ZIP を落とし直して置き換える |

このスキルには**バージョン番号がありません**。更新は GitHub の最新のコミットを追います。Paper、Java、Gradle、MockBukkit などの版はスキルに書かれておらず、スクリプトがそのときの最新を調べます。

## 中身

```
.claude-plugin/        プラグインとマーケットプレイスの定義
agents/                仕様調査用のサブエージェント
skills/papermc-developer/
  SKILL.md             最初に読まれるもの
  scripts/             実行するもの（共通の部品は lib/）
  references/          引く資料（workflows/ と共通の資料）
  templates/           新しいプロジェクトのひな形と、プロジェクトに足す入門用ファイルの元
docs/maintaining/      このスキル自身を直す人のための資料
tests/                 リポジトリの検査（check-repo.ps1）と、ひな形からビルドまでの通し試験（e2e.ps1）
```

スキルを直す・育てる人は、`docs/maintaining/MAINTAINING.md` を読んでください。

## 謝辞

構成と考え方は、伺か（ukagaka）のゴースト開発のためのスキル [ukatech/ukagaka-developer](https://github.com/ukatech/ukagaka-developer) にならっています。

## ライセンス

[Unlicense](LICENSE)（パブリックドメイン）。作ったプラグインのライセンスとは無関係です。Paper、Minecraft のサーバー、Gradle は同梱していません（必要なときに公式の配布元から取ります）。
