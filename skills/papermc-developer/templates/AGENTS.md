# AGENTS.md

Minecraft の Paper サーバー用プラグインのプロジェクトです。開発には、AI エージェント用のスキル `papermc-developer` を使います。

- **作業を始める前に、ルートの `PLUGIN.md` を読むこと。** 何をするプラグインか、対象のサーバーと Java、コマンドと権限、設定、決まりなど、このプラグインに固有の情報はそこにある。`PLUGIN.md` が無いときや、先頭に `<!-- papermc-developer:plugin-template -->` が残っている（まだ書かれていない）ときは、コードを読んで下書きすることを作者に提案する。
- `papermc-developer` スキルが使えるときは、その `SKILL.md` に従う。コードを変えたら、スキルのスクリプトで確かめる。
- スキルが入っていないときは、導入を作者に提案する。入れるのは作者の確認を取ってから。導入の手順は https://github.com/ukagaka-irono/papermc-developer にある。
- **ブランチは `main` / `develop` / `〇〇〇〇-fix`。** コードを変える前に今のブランチを確かめ、`main` か `develop` にいるなら、`develop` から `〇〇〇〇-fix`（例: `hello-command-fix`）を作ってから変える。`main` と `develop` には直接コミットしない。作業ブランチは `develop` に戻し、リリースのときだけ `develop` を `main` に入れる。コミット、push、マージは作者に頼まれたときだけ。
- このプラグインだけの決まりは `PLUGIN.md` に書く。
