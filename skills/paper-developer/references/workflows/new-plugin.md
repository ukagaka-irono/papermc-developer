# 新しいプラグインを作る

## 使うとき

作者が「プラグインを作りたい」「新しいプロジェクトを作って」「ひな形を作って」と言ったとき。プロジェクトの無いフォルダで、何かを作ってほしいと頼まれたときも、まずこれ。

## 手順

1. 作者に、次のことを聞く（会話から分かるものは聞かない。分からないものは既定で進めてよいと伝える）。
   - **何をするプラグインか**（1〜3 行）。名前（英数字。例: `SleepVote`）。
   - 対象の Minecraft の版。既定は最新の安定版（`scripts/versions.ps1` で見て伝える）。作者のサーバーがあるなら、その版に合わせる。**1.7.10 以降のどの版でも作れる**（一覧は `scripts/versions.ps1 -List`）。古い版を選んだら、`scripts/versions.ps1 -Minecraft <版>` で、その版のコマンドとメッセージの書き方、Java、テストの有無を作者に伝え、`references/versions.md` を読む。複数の版で動かしたいなら、いちばん古い版で作る。
   - Folia に対応するか（既定: しない）。`paper-plugin.yml` が要るか（既定: `plugin.yml`。違いは `references/layout.md`）。
   - GitHub で管理するか（`-Workflow` で GitHub Actions を入れる）。
   - パッケージ名（既定: Git のユーザー名から `io.github.<ユーザー>.<名前>`。独自ドメインがあれば `com.example.<名前>` のように逆順で）。
2. 作るフォルダを決める。空のフォルダ（`.git` と `.idea` だけのものを含む）で頼まれたら、そこに作る。そうでなければ、名前のフォルダ（`sleep-vote` のように）を作る。
3. 確かめる: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/new-plugin.ps1 -Name <名前> -Description "<説明>" -DryRun`（ほかに `-Minecraft`、`-PaperPlugin`、`-Package`、`-Workflow`、`-Path`）。作るファイルと版を作者に伝える。
4. `-DryRun` を外して作る。版の問い合わせと、初回は Gradle のダウンロードがあることを一言伝える。
5. `scripts/check.ps1` でビルドとテストが通ることを確かめる（初回は依存のダウンロードで数分かかる）。
6. `PLUGIN.md` の「概要」「コマンドと権限」「動作確認」を、作者の説明で埋める（ひな形の `/hello` と参加メッセージの行は、本題を作るときに消してよいと伝える）。
7. 作者の作りたいものを実装する。`references/paper-api.md` を読み、該当する PaperMC のドキュメントのページを読んでから書く。書いたら `scripts/check.ps1`、テストを足す（`references/testing.md`）。
8. テストサーバーで確かめる（`references/workflows/try-on-server.md`。初回は EULA への同意を作者に確かめる）。
9. Git を使うなら、作者の了承を得てから、`main` / `develop` / `〇〇〇〇-fix` の形で始める（`references/workflows/branches.md`）: `git init -b main` → ひな形をはじめのコミットにする → `git branch develop`。この後の作業（作者の作りたい機能）は、`develop` から作った `〇〇〇〇-fix`（例: `sleep-vote-fix`）で行う。GitHub に上げるなら、リポジトリの作成と push も作者に確かめてから（`gh repo create`）。

## 補足

- ひな形の中身: `/hello` コマンド（権限 `<名前>.hello`、全員）、参加したプレイヤーへのあいさつ（`config.yml` で変えられる）、それを確かめる MockBukkit のテスト 2 つ（1.21 以降）。プラグインの骨組みの見本として置いている。版によって書き方が変わる: コマンドは 1.20.6 以降が Brigadier、それより前は `plugin.yml` の `commands:` と `CommandExecutor`。メッセージは 1.18.2 以降が MiniMessage、それより前は `&` の色コード（`references/versions.md`）。
- 既存のプロジェクトに入門用ファイルだけを足すなら `scripts/init-plugin.ps1`。
- Kotlin で書きたいと言われたら、テンプレートは Java なので、Kotlin の Gradle プラグイン（`org.jetbrains.kotlin.jvm`）を足して移すことになる。版は Gradle Plugin Portal で確かめ、作者の了承を得てから。

## 関連

- 構成と、`plugin.yml` と `paper-plugin.yml` の違い: `references/layout.md`
