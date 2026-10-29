# 初回セットアップの代行

## 使うとき

作者が「セットアップして」「始めたい」「準備して」「環境を整えて」「足りないものを入れて」「PLUGIN.md を書いて」と言ったとき。`scripts/doctor.ps1` で不足が見つかったときも、ほかの作業に入る前にこれを提案する。

作者には作りたいものに集中してもらい、決まった作業はこちらで引き受ける。ただし、アプリのインストールなど作者の PC に関わる操作は、何のために必要かを説明して了承を得てから行う。

## 手順

1. 診断する: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/doctor.ps1 -Json`
   - 各項目の `level` は `required`（ないとビルドできない）、`recommended`、`optional`。`purpose` が用途、`fix` が直し方。`minecraft` が対象の版、`javaRequired` がその版に要る Java。
   - `project` が ok でないときは、プロジェクトのルート（`settings.gradle.kts` や `pom.xml` のあるフォルダ）で作業しているか確かめる。まだプロジェクトが無いなら `references/workflows/new-plugin.md`。
2. 足りないアプリがあれば、用途を一言で説明して、入手を提案する。**インストールは必ず了承を得てから行う。**
   - **JDK**（必須）: 対象の Minecraft が要求する版以上（`javaRequired`）。`fix` にある winget のコマンド（`winget install --id EclipseAdoptium.Temurin.<版>.JDK -e`）を、了承を得てから実行する。winget が無ければ https://adoptium.net/ を案内する。すでに入っているのに見つからないときは、場所を聞いて `scripts/setup.ps1 -JavaPath <java.exe か JDK のフォルダ>` で記録する。ビルドに使う JDK は Gradle のツールチェーンが自動で取るので、PC の java は Gradle を動かせる版（17 以上）でもビルドはできる。テストサーバーには `javaRequired` 以上が要る。
   - **Git**（推奨）: 変更履歴と GitHub。`winget install --id Git.Git -e`。
   - **gh**（任意）: GitHub のリリースをコマンドで作るとき。`winget install --id GitHub.cli -e`。
   - 入れた直後は PATH が反映されていないことがある。見つからないままなら、エージェントを起動し直してもらう。
3. Gradle Wrapper（`gradlew`）が無いプロジェクトなら、`scripts/new-plugin.ps1 -WrapperOnly` で足す（Gradle をホームフォルダに取ることを一言伝える）。
4. **テストサーバーを使うなら、Minecraft の EULA への同意を作者に確かめる。** https://aka.ms/MinecraftEULA を示し、「テストサーバーを動かすには、Minecraft の EULA に同意する必要があります。読んで、同意しますか？」と聞く。**作者が同意すると答えたときだけ** `scripts/setup.ps1 -AcceptEula` を実行する。同意しないなら、テストサーバーは使わず、MockBukkit のテストと作者自身のサーバーでの確認で進める。
5. `scripts/setup.ps1` で、対象の版の Paper のサーバーの jar をホームフォルダに取る（ネットワークに出ることを一言伝える）。最後に doctor の結果が出るので、`required` がすべて ok になったか確かめる。
6. 入門用のファイルが足りなければ（`PLUGIN.md`、`AGENTS.md`、`CLAUDE.md`、`.gitignore` など）、`scripts/init-plugin.ps1 -DryRun` で作るものを確かめて作者に伝え、`-DryRun` を外して実行する（あるファイルは変えない）。GitHub を使うなら `-Workflow`（`references/workflows/ci.md`）。
7. `scripts/check.ps1` で、ビルドとテストが通ることを確かめる。
8. doctor の `plugin-profile` が ok でなければ（`PLUGIN.md` が無い、または先頭に `<!-- paper-developer:plugin-template -->` が残っている）、`PLUGIN.md` を下書きする。
   - `plugin.yml` / `paper-plugin.yml`（名前、main、権限、コマンド、依存）、`build.gradle.kts`（版、依存）、`config.yml`、コード（コマンドの登録、リスナー、スケジューラ、保存しているデータ）、`README` があれば読んで埋める。
   - 何をするプラグインか、決まりなど、コードから読み取れないことは推測で足さない。わからない欄は空けたまま、作者に聞く。
   - 下書きを見せて確かめてもらい、了承を得てから書き込む。書き終えたら先頭のマーカーの 2 行を消す。
9. 作者が望めば、`scripts/run-server.ps1` でテストサーバーを立てて見せる（`references/workflows/try-on-server.md`）。
10. 最後に次のことを伝える。
    - Claude Code では、プラグインを入れた直後のセッションには読み込まれていないことがある。
    - 次にできること。作者はコマンド名を知らないので、**「〜と頼んでください」の形で 2〜3 個示す**。例:「`/home` コマンドを作って」「サーバーで動かして見せて」「配布用の jar を作って」。

## 関連

- 手順書の一覧と、作者の言い回しとの対応: `SKILL.md` の「こう頼まれたら」
- スクリプトの一覧: `references/commands.md`
