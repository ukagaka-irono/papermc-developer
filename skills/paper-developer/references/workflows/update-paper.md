# Paper の版を上げる

## 使うとき

作者が「Paper を最新にして」「1.21 から 26 に上げて」「対応バージョンを上げて」「今の最新は？」と言ったとき。`scripts/versions.ps1` や `scripts/doctor.ps1` が、新しい安定版があると知らせたときは、更新を提案してよい（行うのは作者の了承を得てから）。

## 考えること

- **ビルドに使う版（paper-api）と、`api-version` は別のもの。** paper-api を上げると、新しい API が使えるようになり、非推奨や削除された API が分かる。`api-version` は「このプラグインが動くいちばん古いサーバー」で、上げると古いサーバーでは読み込まれなくなる。作者が古いサーバーを切り捨てると決めたときだけ上げる（`-ApiVersion`）。
- 新しい版は、要求する Java が上がることがある（例: 26.1 から Java 25）。テストサーバーと、利用者のサーバーの Java も上がる。
- 1.21.x から 26.x へは、paper-api の版の書き方が変わる（`1.21.11-R0.1-SNAPSHOT` → `26.3.build.+`）。スクリプトが直す。
- MockBukkit は新しい版に遅れて出る。無い版では、テストを古い MockBukkit のまま動かすか、出るまで待つかを作者と決める。

## 手順

1. 今の状態と最新を見る: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/versions.ps1`（最近の版の一覧は `-List`）。作者に、上げる先の版を確かめる（既定は最新の安定版。作者のサーバーがあるなら、その版まで）。
2. 計画を見る: `scripts/update-paper.ps1 -DryRun`（版を指定するなら `-Minecraft <版>`、`api-version` も上げるなら `-ApiVersion`）。変わる行と、手で直すところ（`manual`）を作者に伝える。
3. 了承を得てから、`-DryRun` を外して実行する。書き換える前のファイルがホームフォルダの `backups/` に置かれ、最後に `check.ps1` が走る。
4. `manual` があれば、その行を手で直す（version catalog の `libs.versions.toml`、`gradle.properties` の変数など）。直したら `scripts/check.ps1`。
5. **API の変更**でコンパイルが通らない、非推奨の警告が増えたときは:
   - PaperMC のドキュメントの更新情報と、Javadoc の該当クラス（`@Deprecated` の説明に置き換え先が書いてある）を読む。
   - 推測で別のメソッド名に変えない。1 つ直すごとにコンパイルして確かめる。
   - 直す量が多いときは、件数と主なものを作者に見せて、進め方を相談する。
6. テストサーバーで確かめる（`scripts/run-server.ps1`。新しい版のサーバーの jar を取る。ワールドは新しい版に変換されるので、古い版に戻すなら `-Fresh`）。
7. 必要なら Gradle の Wrapper も上げる: `./gradlew wrapper --gradle-version <版>`（版は `scripts/versions.ps1` の gradle。作者の了承を得てから）。
8. 変えたこと（版、Java、直した API）を短く報告する。`PLUGIN.md` の「対象」の版も直す。

## 関連

- 版の書き方: `references/layout.md`
