# このスキル自身を直す・育てる人へ

`papermc-developer`（スキルの本体、スクリプト、資料、テンプレート）を直すときの注意です。プラグインを作るときの指示は `skills/papermc-developer/SKILL.md` と `references/`、利用者向けの案内は `README.md` にあります。このフォルダ（`docs/maintaining/`）はリポジトリにだけあり、スキルの一部としては配られません。

## 方針

- **プロジェクトの外に置く。** プラグインのプロジェクトにはスクリプトをコピーしない。プロジェクトに置くのは、プロジェクトのものである `PLUGIN.md`、短い `AGENTS.md` / `CLAUDE.md`、`.gitignore` などだけ（`templates/`）。
- **公式情報にリンクする。** Paper API の細かい使い方は複製せず、PaperMC のドキュメント（`llms.txt` と `index.md` のページ）と Javadoc に誘導する。スキルに書くのは、手順、落とし穴、そして「どの資料を読むか」。
- **変わりやすい事実を書かない。** Minecraft / Paper の版、必要な Java、paper-api の版、Gradle とそのプラグインの版、MockBukkit の成果物名は、文書やテンプレートに固定で書かず、スクリプトが実行時に調べる（`scripts/lib/common.ps1` の `Get-PaperDev*`、`scripts/versions.ps1`）。テンプレートの版は `@@TOKEN@@` で、`new-plugin.ps1` が埋める。例外は GitHub Actions のアクションの版（`templates/github/`）で、これは見直すときに上げる。
- **外に出る操作は、作者の確認を取ってから。** スクリプトは公開（タグの push、Releases、Hangar、Modrinth）をしない。EULA への同意は `setup.ps1 -AcceptEula` が記録するだけで、エージェントが作者の代わりに同意しない（`SKILL.md` の作業のルール）。

## 構成

```
.claude-plugin/plugin.json, marketplace.json   version を書かない
agents/papermc-researcher.md                      仕様調査（haiku）
skills/papermc-developer/                         ← コピー導入では、このフォルダだけが配られる。自己完結させる
  SKILL.md                                      入口。500 行以下。allowed-tools に読み取り・検査だけのスクリプト
  scripts/                                      スクリプト。lib/common.ps1（共通）、lib/templates.ps1、lib/server.ps1
  references/                                   引く資料。workflows/ と共通の資料
  templates/                                    project/（ひな形）、descriptor/（plugin.yml / paper-plugin.yml）、入門用ファイル、github/
docs/maintaining/                               この文書
tests/check-repo.ps1                            リポジトリの検査（CI でも走る）
tests/e2e.ps1                                   ひな形を作ってビルドとテストを通す（ネットワークと JDK が要る）
```

- **`skills/papermc-developer/` の外のファイルを、スクリプトや資料から参照しない。** コピー導入では外が無い。
- **スキルのフォルダには書き込まない。** 書き込む先はホームフォルダ（`Get-PaperDevHome`。`PAPERMCDEV_HOME`）。

## `scripts/*.ps1` の書き方

- Windows PowerShell 5.1 と PowerShell 7（Windows、macOS、Linux）の両方で動かす。`??`、`?.`、三項演算子、パイプラインの `&&` など、7 だけの構文は使わない。
- **ASCII 文字だけで書く**（BOM のないファイルに日本語を書くと、日本語版 Windows の 5.1 は CP932 として読んで壊れる）。ASCII でない文字が要るときは、正規表現の `\uXXXX` で書く。`tests/check-repo.ps1` が確かめる。**注意: エディタやエージェントの編集道具が `\uXXXX` を実際の文字に戻してしまうことがある。** 書いた後で check-repo を走らせる。
- 冒頭のコメントヘルプ（`.SYNOPSIS`、`.DESCRIPTION`、終了コード、`.EXAMPLE`）を書き、`. (Join-Path $PSScriptRoot 'lib/common.ps1')` と `Initialize-PaperDevConsole` で始める。プロジェクトは `Resolve-PaperDevProject $ProjectRoot` で決める（`-ProjectRoot` を持たせる）。
- 終了コードをそろえる: 0 OK / 1 失敗・エラー / 2 注意が要る / 3 道具が無くて確かめられない。
- 外部のプログラムは `Invoke-PaperDevProcess` で呼ぶ（出力を取り込み、ウィンドウを出さない）。**Gradle（と Maven）は `Invoke-PaperDevDetachedProcess`**: Gradle は新しいデーモンを残し、デーモンは呼び出し元のハンドルを継承する。パイプで呼ぶと、デーモンが生きている間（既定で 3 時間）、スクリプトを呼んだエージェントのコマンドが終わらない。`ShellExecute`（`Start-Process`）で起動し、出力は一時ファイルに書かせる。長く動かし続けるもの（テストサーバー）も同じ理由で `Start-Process` で切り離す（`run-server.ps1`）。
- PowerShell の落とし穴（どれも実際に踏んだ）: `$Matches` は次の `-match` で上書きされる（グループは先に変数へ移す）。配列の中では `,` が `+` より強い（`@('-Xms' + $m, '-Xmx' + $m)` は 1 つの文字列になる。`@(('-Xms' + $m), ...)` と括弧で囲む）。`return ,$array` した関数の結果を直接パイプに流すと、配列が 1 つのオブジェクトとして流れる（いったん変数に入れてから流す）。値の無い `[string[]]` の引数を配列に足すと `''` が混ざる（`Where-Object` で除く）。
- ダウンロードは `Save-PaperDevDownload`（WebClient。5.1 の `Invoke-WebRequest -OutFile` は大きなファイルで非常に遅い）。チェックサムがあれば必ず渡す。
- 使い方の例は `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/<名前>.ps1` の形にそろえる。`SKILL.md` の `allowed-tools` はこの形で許可している。許可するのは読み取り・検査だけのもの（`run-server`、`rcon`、`new-plugin`、`init-plugin`、`setup`、`update-*`、`build-release` は、PC やサーバーの状態を変えるので許可しない）。
- スクリプトを足したら、`SKILL.md` の表、`references/commands.md`、必要なら `allowed-tools` を直す。

## 外部のものとの付き合い方（実装メモ）

| もの | 使い方と理由 |
|---|---|
| Fill API v3（`https://fill.papermc.io/v3/projects/<paper|folia>`） | 版の一覧（新しい順）、`/versions/<v>` の `java.version.minimum` と `support.status`、`/builds/latest` の `channel`、`downloads."server:default"` の URL と SHA-256。最新の安定版は「プレリリースでなく、最新ビルドが STABLE の、いちばん新しい版」。旧 API（`api.papermc.io/v2`）は使わない |
| 版の時代（era） | `Get-PaperDevEra` が、版ごとの Brigadier / MiniMessage / api-version / paper-plugin.yml / フラットワールド / Java の範囲を返す。テンプレートの `@@BEGIN:BRIGADIER@@`、`LEGACY_COMMANDS`、`MINIMESSAGE`、`LEGACY_TEXT`、`API_VERSION` の各ブロックは、`new-plugin.ps1` がこれで選ぶ。境目を変えたら `references/versions.md` の表も直し、`tests/e2e.ps1` の版で確かめる。境目の根拠: Brigadier のライフサイクル API は 1.20.6、MiniMessage が API に入ったのは 1.18.2、api-version は 1.13（3 桁は 1.20.5）、フラットワールドの生成設定の今の形式は 1.19、サーバーの `--nogui` は 1.16 から（1.12.2 以前の CraftBukkit は `--nogui` を知らずに使い方を表示して終わるので、`nogui` を渡す）。これらは実際にビルドとテストサーバーで確かめた（1.7.10、1.8.8、1.12.2、1.16.5、1.18.2、1.20.4、1.21.11、26.3） |
| API の依存 | `Get-PaperDevApiDependency`。1.7.10 / 1.8.8 は `org.github.paperspigot:paperspigot-api`、1.9.4〜1.16.5 は `com.destroystokyo.paper:paper-api`、1.17 以降は `io.papermc.paper:paper-api`。古いスナップショットは、成果物の `maven-metadata.xml` の一覧に載っていないことがあるので、版のフォルダの `maven-metadata.xml` を直接見る |
| テストサーバーの Java | 古いサーバーは新しい Java で起動しない。`Find-PaperDevJdks` が JDK の `release` ファイルから版を読み（実行しない）、`Get-PaperDevServerJava` が版に合うものを選ぶ。無ければ `setup.ps1 -Jdk <n>` が Adoptium API から Temurin を入れる（SHA-256 を確かめる） |
| paper-api の版 | 26.1 以降は `<版>.build.<n>-<channel>`（Gradle では `<版>.build.+`、Maven では `[<版>.build,)`）、1.21.11 以前は `<版>-R0.1-SNAPSHOT`。`Get-PaperDevApiCoordinate`。最新のビルドは `repo.papermc.io` の `maven-metadata.xml` |
| MockBukkit | Maven Central の `org/mockbukkit/mockbukkit/` の一覧から `mockbukkit-v<版>`、なければ `mockbukkit-v<major.minor>`。新しい版には遅れて出る。main クラスが `final` だと読み込めない（テンプレートが `final` でない理由） |
| Gradle | `services.gradle.org/versions/current` と、配布物の `.sha256`。Wrapper は、ホームフォルダに取った Gradle で `gradle wrapper` を実行して作る |
| javac の出力 | JDK の表示言語で level の語が変わる（`error` / `エラー`）。Gradle は失敗時に同じメッセージを字下げして繰り返す。`Get-PaperDevCompilerMessages` は語を緩く読み、重複を除く |
| テストサーバー | Windows は `cmd /d /s /c ""java" ... > console.log 2>&1"` を `Start-Process -WindowStyle Hidden` で（PID は cmd のもの。止めるときは `taskkill /T`）。その他は `sh -c 'exec java ...'`。起動の判定は `logs/latest.log` の `]: Done (`。停止は RCON の `stop`。RCON は Source RCON の形式で、分割された返事の終わりを知るため、未知の種類のパケットを続けて送り、その返事を区切りにする |
| Folia | `folia-supported: true`（`new-plugin.ps1 -Folia`、テンプレートの `FOLIA` ブロック）と paper-api のまま。テストは `run-server.ps1 -Platform folia` が Fill API の `folia` から jar を取る（チャンネルが ALPHA のことがある）。Folia でも RCON は動く。`check.ps1` の Folia の検査は `getServer()` / `Bukkit` / `server` の `.getScheduler()` だけを見る（`entity.getScheduler()` は Folia の正しい API）。PowerShell の名前は大文字小文字を区別しないので、`-Platform` の引数とスクリプトの `$platform` は同じ変数（実際に踏んだ） |
| Velocity | プロジェクトは `velocity-api` を含むビルドファイルで見分ける（`Kind = velocity`、記述ファイル無し）。`@Plugin` は `Get-PaperDevVelocityPlugin` が正規表現で読む。テンプレート（`templates/velocity/`）は `BuildConstants` を Gradle のタスクで作り、`@Plugin(version = BuildConstants.VERSION)` にする。テストのプロキシ（`run-proxy.ps1`）は、`velocity.toml` を jar の `default-velocity.toml` から作って書き換え（1 回の起動で済む）、バックエンドの `config/paper-global.yml` は無ければ `proxies.velocity` だけを書く（Paper が残りを補う）。Velocity には RCON が無いので、`lib/console-bridge.ps1`（隠れた PowerShell）が java の標準入力をつなぎ、キューのファイルに足された行を送る。ログの形式は `[時刻] [スレッド/LEVEL] [ロガー]: ` で、プラグインのロガー名はプラグインの id |
| `latest.log` | 行頭が `[HH:MM:SS] [スレッド/LEVEL]: ` の行が 1 件の始まり。それ以外の行（スタックトレース）は直前の件に付ける。プラグインの出力は `[プラグイン名] ` で始まる |

## 更新（プラグイン）

- `plugin.json` と `marketplace.json` に **`version` を書かない**。書かなければ、コミットのたびに新しい版になり、`claude plugin update` と自動更新で届く。
- したがって、**既定ブランチ（`main`）の先頭は、いつでも利用者に届く**。壊れたまま push しない。だから、下の「ブランチ」のとおり、`main` には `develop` からしか入れない。
- `claude plugin validate .` で、マニフェストと同梱物を確かめる。

## ブランチ

このリポジトリも、スキルがプラグインのプロジェクトに求めるのと同じ `main` / `develop` / `〇〇〇〇-fix` で運用する（プロジェクト向けの手順は `skills/papermc-developer/references/workflows/branches.md`）。

| ブランチ | 役割 |
|---|---|
| `main` | 利用者に届く版。**GitHub の既定ブランチは `main` のままにする**（プラグインのマーケットプレイスとコピー導入の `update-skill.ps1` は既定ブランチを取る）。直接コミットしない |
| `develop` | 次に `main` へ入れる変更を集める。直接コミットしない |
| `〇〇〇〇-fix` | 1 つの変更ごと（例: `branch-rules-fix`、`folia-server-fix`）。`develop` から作り、`develop` への Pull Request で戻す |

- 作業ブランチの Pull Request は `develop` 向け。CI（`.github/workflows/check.yml`。`check-repo` と `e2e`）が通ってからマージする。
- `develop` を `main` に入れる（リリース）前に、下の「確認」を `develop` で行う。テストサーバーに関わる変更は、EULA に同意した手元の環境で `run-server.ps1` まで通す（CI では動かせない）。`develop` → `main` も Pull Request で行い、マージした時点で利用者に届く。
- リリース前の `develop` を試すには、コピー導入なら `scripts/update-skill.ps1 -Ref develop`。
- `main` の不具合を急いで直すときも、`develop` から `〇〇〇〇-fix` を作り、`develop` を経て `main` に入れる（`main` だけを直さない。直したものが `develop` から消えるのを防ぐ）。
- リポジトリの場所（`ukagaka-irono/papermc-developer`）は、`scripts/lib/common.ps1` の `$PaperDevRepo`、`README.md`、`templates/AGENTS.md`、`SKILL.md`、`references/workflows/update-skill.md`、`.claude-plugin/` にある。移したら全部直す（`tests/check-repo.ps1` が食い違いを見つける）。

## 確認

スキルを変えたら、次を確かめる。

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tests/check-repo.ps1`（と `pwsh` でも）: 構文、ASCII、`SKILL.md` と文書が指すパスの実在、`allowed-tools` のパス、テンプレートのトークン、リポジトリ名のそろい。
2. `tests/e2e.ps1`: 一時フォルダに `new-plugin.ps1` でプロジェクトを作り（`plugin.yml` と `paper-plugin.yml` の両方）、`check.ps1`、`build-release.ps1`、`update-paper.ps1 -DryRun` を通す。`PAPERMCDEV_HOME` を一時フォルダにして、利用者のホームフォルダを汚さない。
3. テストサーバーを変えたとき: EULA に同意した自分の環境で、`run-server.ps1`、`rcon.ps1 "plugins"`、`server-log.ps1`、`run-server.ps1 -Stop` を通す（CI では EULA に同意できないので走らせない）。
