# GitHub Actions（push ごとのビルドと、タグでのリリース）

プロジェクトを GitHub で管理しているときの自動化。ワークフローは Gradle を直接呼ぶので、GitHub 側にこのスキルは要らない。

## 入れる

`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/init-plugin.ps1 -Workflow`（`new-plugin.ps1 -Workflow` でも入る）で、無いときだけ作られる。

| ファイル | いつ | すること |
|---|---|---|
| `.github/workflows/check.yml` | push と pull request | JDK を入れ、`./gradlew build`（コンパイルとテスト）。jar を成果物（Artifacts）として残す |
| `.github/workflows/release.yml` | `v*` のタグの push | ビルドして、`gh release create` で GitHub Releases に jar を付けて公開する |

- JDK の版は、作ったときの対象の Java（`java-version`）。版を上げたら `scripts/update-paper.ps1` が一緒に直す。
- Maven のプロジェクトでは、`./gradlew build` を `./mvnw -B package` に、`build/libs` を `target` に直す。
- `gradlew` に実行権限が無いと Linux のランナーで失敗する。Windows で作ったリポジトリなら、`git update-index --chmod=+x gradlew` をしてコミットする（作者の了承を得てから）。

## リリースの流れ

1. `build.gradle.kts` の `version` をリリースの版にし、`scripts/build-release.ps1 -Tag v<版>` で版とタグの一致と jar の中身を確かめる。
2. コミットして push する（作者の了承を得てから）。
3. タグを打って push する（作者の了承を得てから）: `git tag v<版>`、`git push origin v<版>`。
4. Actions の結果を見る（`gh run list`、`gh run watch`）。失敗したら、ログ（`gh run view --log-failed`）を読んで直す。

## Hangar や Modrinth にも自動で出すなら

`release.yml` に、Gradle プラグイン（`references/workflows/release.md`）のタスクを呼ぶ手順を足し、トークンを `${{ secrets.HANGAR_API_TOKEN }}` などで渡す。Secrets は作者に GitHub の Settings → Secrets and variables → Actions で登録してもらう（値をチャットに貼らせない）。
