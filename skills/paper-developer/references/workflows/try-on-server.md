# テストサーバーで動かして確かめる

## 使うとき

作者が「サーバーで試して」「動かして見せて」「このコマンドを打ってみて」「ログを見て」「サーバーでエラーが出る」と言ったとき。機能を作った・直した後に、本物の Paper で読み込まれて有効になるかを確かめるときも使う。

**作者がふだん使っているサーバー、公開しているサーバーには触らない。** ここで使うのは `scripts/run-server.ps1` が立てるテスト用のサーバーだけ（ホームフォルダの中にあり、127.0.0.1 だけで待ち受ける）。作者が自分のサーバーに入れたいと言ったら、`build/libs/` の jar（配布用なら `references/workflows/release.md`）を `plugins/` に置いてサーバーを再起動する、という手順を示す。

## 前提

- **Minecraft の EULA への同意。** テストサーバーは Minecraft のサーバーを動かすので、作者が EULA（https://aka.ms/MinecraftEULA ）に同意している必要がある。`run-server.ps1` が終了コード 3 で「EULA has not been agreed to」と言ったら、EULA を示して作者に読んでもらい、**作者が同意すると答えたときだけ** `scripts/setup.ps1 -AcceptEula` を実行する。同意の代行や、同意したものとしての先回りはしない。
- 対象の版が要求する Java（`scripts/doctor.ps1`）。

## 手順

1. 起動する: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-server.ps1`
   - ビルド → 動いていれば停止 → サーバーの jar の用意（初回は数十 MB をダウンロード）→ プラグインの jar を `plugins/` に入れ替え → 起動 → `Done` を待つ → 報告、を 1 回で行う。初回の起動は、ワールドの生成などで 1〜2 分かかる。
   - 報告: `plugin <名前> enabled` か `was not enabled`、ログの ERROR と、プラグインに関する WARN（スタックトレース付き）。
   - 終了コード 2 なら、表示されたエラーを直す（`references/workflows/check.md` の「サーバーで出たエラーを直すとき」）。直したら、もう一度 `run-server.ps1`（再起動して入れ替える）。
   - 依存プラグインが要るときは `-ExtraPlugin <jar のパス>`（作者に jar の場所を聞く。ダウンロードするなら、出どころを作者に確かめてから）。
   - ワールドを作り直したいときは `-Fresh`（プラグインの `plugins/<名前>/` のデータは残る）。
2. コマンドで試す: `scripts/rcon.ps1 "hello"`（先頭の `/` は不要。複数なら `scripts/rcon.ps1 "plugins" "version <名前>"`）。
   - 返事と、その間にログに増えたもの（例外など）が表示される。RCON の返事が空でも、ログにエラーが出ていないかを見る。
   - コンソールとして打つので、プレイヤーが要るコマンドは「プレイヤーだけが使える」側の動きになる。プレイヤーが要る確認は、MockBukkit のテスト（`references/testing.md`）か、作者に入ってもらう。
   - 設定を変えて試すなら、サーバーのフォルダの `plugins/<名前>/config.yml`（`run-server.ps1 -Status` でフォルダが出る）を直し、プラグインの再読み込みコマンドがあればそれで、無ければ `run-server.ps1 -NoBuild` で再起動する。
3. ログを見る: `scripts/server-log.ps1`（ERROR と、プラグインに関する WARN）、`-Plugin`（プラグインに関するもの全部）、`-Level INFO -Tail 80`（全体）。
   - タイマーなど、時間で動く処理: `scripts/server-log.ps1 -Plugin -Pattern "<出るはずの文>" -Wait 60`。
4. 作者に見てもらう: 表示された `localhost:<ポート>` に、同じ版の Minecraft で接続してもらう。何をすると何が起きるべきかを、`PLUGIN.md` の「動作確認」に沿って伝える。OP が要るなら、作者に確かめてから `scripts/rcon.ps1 "op <プレイヤー名>"`。
5. デバッガを使いたいと言われたら: `scripts/run-server.ps1 -JdwpPort 5005` で起動し、IDE の「Remote JVM Debug」で `127.0.0.1:5005` に接続してもらう。
6. 終わったら、作者に聞いてから `scripts/run-server.ps1 -Stop`（ワールドを保存して止まる）。作者がまだ遊ぶなら、そのままにしてよい。

## 報告

確かめたこと（有効になった、どのコマンドで何が返った、ログにエラーが無い）と、確かめていないこと（プレイヤーが必要な操作、見た目）を分けて伝える。

## 関連

- テストとの使い分け: `references/testing.md`
- コマンドと終了コード: `references/commands.md`
