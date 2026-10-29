# ビルドとテストのチェック、エラーの直し方

## 使うとき

作者が「ビルドして」「チェックして」「エラーを直して」「テストが落ちる」「コミットする前に確認して」と言ったとき。コードや記述ファイル、ビルドの設定を変えた後は、頼まれなくても必ず行う。

## 手順

1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check.ps1` を実行する。記述ファイルの検査、コンパイル、テストを順に行う。
   - `skipped`（終了コード 3）は、Java かビルドの道具が無い。`scripts/doctor.ps1` で見て、`references/workflows/setup.md`。
   - 初回や依存を変えた後は、ダウンロードで時間がかかる。
2. 結果は次の優先順で扱う。
   1. **記述ファイルの error**（`plugin.yml` / `paper-plugin.yml`）: サーバーがプラグインを読み込まない原因になる。main クラスの名前、`api-version`、`getCommand` と `commands:` の食い違いなど。表示された行を直す。
   2. **コンパイルの error**: `ファイル:行: 内容` と、問題の行が出る。存在しないメソッドやクラスは、推測で別の名前に変えず、Javadoc（https://jd.papermc.io/paper/ ）か PaperMC のドキュメントで正しい API を確かめる。版を上げた直後なら `references/workflows/update-paper.md` の「API の変更」。
   3. **落ちたテスト**: 名前とメッセージ、スタックトレースの先頭が出る。テストが正しく仕様を表しているなら、コードを直す。テストのほうを、通るように書き換えて済ませない（仕様が変わったなら、作者に確かめてから直す）。`UnimplementedOperationException` は MockBukkit が未実装の API（`references/testing.md`）。
   4. **警告**（非推奨 `[deprecation]` など）: 今回書いた・直したコードのものは直す（`references/paper-api.md` に置き換え先）。もとからあるものは、数と主なものを報告するだけにする。
   5. **ビルドの道具のエラー**（依存が見つからない、プラグインの版、ツールチェーン）: 表示された「What went wrong」を読む。依存が見つからないなら、版の書き方（`references/layout.md`）とリポジトリを確かめる。ネットワークの問題かもしれないので、もう一度だけ試してから作者に伝える。
3. 直したら 1 をもう一度実行し、error がなくなるまで繰り返す。
4. 記述ファイルやコマンド、イベントを直したときは、テストサーバーでも確かめる（`references/workflows/try-on-server.md`）。ビルドが通っても、サーバーで有効にならないことがある（依存プラグインが無い、`onEnable` で例外）。
5. 最後に、直したことと残っている警告を短く報告する。

## サーバーで出たエラーを直すとき

作者が「サーバーでエラーが出る」とログやスタックトレースを貼ったとき:

1. スタックトレースの、**このプラグインのパッケージの最初の行**を探す（その上は Paper や Java の中）。`Caused by:` があれば、いちばん下の `Caused by:` が根本の原因。読み方は https://docs.papermc.io/paper/dev/reading-stacktraces/index.md 。
2. よくあるもの: `NullPointerException`（`getCommand` が null、設定のキーが無い、プレイヤーがもういない）、`IllegalStateException: Asynchronous ...`（非同期のスレッドからワールドを触った）、`NoClassDefFoundError` / `ClassNotFoundException`（依存のライブラリを同梱していない、依存プラグインが無い）、`UnsupportedClassVersionError`（サーバーの Java が古い）、`Could not load ... Unsupported API version`（`api-version` がサーバーより新しい）。
3. 同じことをテストサーバーで再現させてから直し、直ったことも同じ手順で確かめる。

## 関連

- コマンドと終了コードの一覧: `references/commands.md`
- テストの書き方: `references/testing.md`
