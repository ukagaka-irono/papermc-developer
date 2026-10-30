# 配布用の jar を作る・公開する

## 使うとき

作者が「配布用の jar を作って」「リリースしたい」「Hangar に出したい」「Modrinth に出したい」「バージョンを上げて出して」と言ったとき。

**作者にはっきり頼まれたときだけ行う。自分から始めない。** jar を作るところまでは手元の作業、公開（タグの push、GitHub Releases、Hangar、Modrinth）は外に出る操作なので、その都度、作者の確認を取る。

## jar を作る

0. **リリースは `develop` から作る**（`references/workflows/branches.md`）。出したい作業ブランチ（`〇〇〇〇-fix`）がすべて `develop` に入っていることを確かめ、`develop` にいる状態で始める。版の変更も、小さな `release-1-2-0-fix` のような作業ブランチで行って `develop` に戻してよい。
1. 版を決める。`build.gradle.kts` の `version`（`plugin.yml` にはビルドで埋め込まれる）。前の版からの変更を見て、作者に版を確かめる（目安: 互換を壊すなら 1 つめ、機能を足したら 2 つめ、直しただけなら 3 つめの数字を上げる）。`-SNAPSHOT` は外す。
2. `api-version` が、動かしたい最も古いサーバーの版になっているか確かめる。
3. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-release.ps1`（タグを打つなら `-Tag v1.2.0`）。
   - `check.ps1` が通らなければ作らない。
   - jar を調べる: 記述ファイルの version が埋まっている、main クラスがある、サーバーの API を同梱していない。同梱しているライブラリの一覧が出たら、ライセンスを作者に伝える。
   - `build/release/<名前>-<版>.jar` と `.sha256` ができる。
4. できたら、テストサーバーで最後に確かめる（`scripts/run-server.ps1`。jar は同じビルドから作られる）。
5. 更新履歴（何が変わったか）を、コミットの履歴から下書きして作者に見せる。

## 公開する

どこに出すかを作者に聞く。複数でもよい。どれも、**トークンを作者にチャットへ貼らせない**。

### GitHub Releases

- GitHub Actions を使う（推奨）: `scripts/init-plugin.ps1 -Workflow` で入る `.github/workflows/release.yml` は、`v*` のタグの push で、ビルドして jar をリリースに付ける。作者の了承を得てから、`develop` → `main` の Pull Request を作ってマージし（`gh pr create --base main --head develop`）、**`main` の上で** `git tag v1.2.0` と `git push origin v1.2.0`（`references/workflows/ci.md`）。タグは `main` 以外に付けない（`release.yml` は `main` に無いタグでは失敗する）。
- 手元から: `gh release create v1.2.0 build/release/<jar> --title v1.2.0 --notes-file <更新履歴>`（gh が要る。作者の了承を得てから）。

### Hangar（PaperMC の公式の配布先）

- https://hangar.papermc.io/ 。プロジェクトのページは、作者が Web で作る（説明文、ライセンス、カテゴリ）。
- 版のアップロードは、Web から jar を上げるのがいちばん簡単。自動にするなら、Gradle プラグイン `io.papermc.hangar-publish-plugin` を足し、API キーを環境変数（`HANGAR_API_TOKEN` など）か GitHub の Secrets から読む。設定の書き方は、そのプラグインの README を読んでから書く（版は `scripts/versions.ps1`）。
- 公開の前に、Hangar の規則（https://hangar.papermc.io/guidelines ）を読む。

### Modrinth

- https://modrinth.com/ 。プロジェクトは作者が Web で作る（種類は Plugin、ローダーに Paper（と Folia、Purpur など動くもの）を選ぶ）。
- 自動にするなら、Gradle プラグイン `com.modrinth.minotaur` を足し、トークンを環境変数 `MODRINTH_TOKEN` から読む。書き方は、そのプラグインの README を読んでから書く。
- Velocity のプラグインは、Hangar でも Modrinth でも、プラットフォーム（ローダー）に Velocity を選ぶ。Folia で動くプラグインは、Modrinth ならローダーに Folia も選ぶ。
- 公開の前に、Modrinth の規則（https://modrinth.com/legal/rules ）を読む。

### 公開した後

- 公開した版とリンクを作者に伝える。
- `build.gradle.kts` の `version` を次の開発版（例: `1.2.1-SNAPSHOT`）にするかを作者に聞く。

## 関連

- 自動化: `references/workflows/ci.md`
- 配布の約束: `references/ai-guidelines.md`
