# ブランチの使い方（main / develop / 〇〇〇〇-fix）

プラグインのプロジェクトを Git と GitHub で管理するときの、ブランチの決まり。**コードを変える作業は、どれもこの決まりに沿って行う。**

## 3 種類のブランチ

| ブランチ | 役割 | 直接コミット |
|---|---|---|
| `main` | **配布した版だけ**が入る。いつでも配布できる状態。リリースのタグ（`v1.2.0`）はここに付ける | しない |
| `develop` | 次の版に入る変更を集める。作業ブランチはここから作り、ここへ戻す | しない |
| `〇〇〇〇-fix` | 1 つの作業のためのブランチ。機能の追加も、不具合の修正も、この形 | する |

- `〇〇〇〇` は、作業の内容を表す短い英語（小文字、単語は `-` でつなぐ）。最後は必ず `-fix`。例: `hello-command-fix`、`join-message-fix`、`sleep-vote-fix`、`paper-26-3-fix`（版の更新）、`folia-support-fix`。
- 1 つのブランチには 1 つの作業だけを入れる。別のことを直したくなったら、別の `〇〇〇〇-fix` を作る。

```
main      ──●────────────────────●──── (v1.0.0)    (v1.1.0)
             \                  /
develop       ●──●─────●───────●
                  \   / \     /
hello-command-fix  ●─●   \   /
                          \ /
join-message-fix           ●
```

## 作業の流れ

1. **作業を始める前に、今のブランチを確かめる**（`git branch --show-current`。`scripts/doctor.ps1` の `branch` にも出る）。
   - `main` か `develop` にいるなら、コードを変える前に作業ブランチを作る:
     `git switch develop` → `git pull`（リモートがあるとき）→ `git switch -c <〇〇〇〇>-fix`
   - すでに、今の作業に合う `〇〇〇〇-fix` にいるなら、そのまま続ける。別の作業のブランチにいるなら、作者に確かめる（そのブランチに混ぜない）。
   - 作業ブランチを作ったことは、名前と一緒に作者に伝える。手元のブランチを作るのは確認なしでよい。
2. 作業ブランチで変更し、`scripts/check.ps1` を通す。テストサーバーで確かめる（`references/workflows/try-on-server.md`）。
3. **コミットは作者に頼まれたときだけ**。メッセージは、何をなぜ変えたかを 1 行目に短く書く。
4. `develop` に戻す（作者の了承を得てから）:
   - GitHub を使っているとき: `git push -u origin <〇〇〇〇>-fix` のあと、`develop` 向けの Pull Request を作る（`gh pr create --base develop`）。GitHub Actions の `check` が通ってからマージする。
   - リモートが無いとき: `git switch develop` → `git merge --no-ff <〇〇〇〇>-fix`。
   - マージした作業ブランチは消してよい（`git branch -d <〇〇〇〇>-fix`。作者に確かめてから）。
5. **リリースは `develop` から `main` へ**（`references/workflows/release.md`）。`develop` の `build.gradle.kts` の `version` をリリースの版にし、`develop` → `main` の Pull Request（リモートが無ければ `git merge --no-ff develop`）。`main` にタグを付けて push すると、`.github/workflows/release.yml` が jar を公開する。

## してはいけないこと

- `main` と `develop` に直接コミットしない。`main` に `〇〇〇〇-fix` を直接マージしない（必ず `develop` を通す）。
- 作者の了承なしに、push、Pull Request の作成とマージ、タグの push、ブランチの削除をしない。
- `git push --force`、`git reset --hard`、履歴の書き換え（rebase して push し直すなど）を、作者の明示の指示なしにしない。
- `main` や `develop` の上で作業を始めてしまったら、変更を捨てずに `git switch -c <〇〇〇〇>-fix` で作業ブランチに移す（コミット前の変更はそのまま付いてくる）。

## 初めてこの形にする

まだ `main` しか無いリポジトリでは、作者の了承を得てから:

1. `git switch main` → `git branch develop` で `develop` を作る（リモートがあれば `git push -u origin develop`）。
2. GitHub を使っているなら、Pull Request の向き先が自然に `develop` になるよう、既定のブランチを `develop` にするかを作者に聞く（`gh repo edit --default-branch develop`。GitHub の設定を変える操作なので、必ず確かめてから）。`main` を保護するなら、GitHub の Settings → Branches で、Pull Request を必須にする（作者に操作してもらう）。
3. `.github/workflows/check.yml` が `develop` と `*-fix` の push と Pull Request で動くことを確かめる（`scripts/init-plugin.ps1 -Workflow` で入るものはそうなっている）。

`main` が `master` という名前のリポジトリでは、`main` を `master` と読み替える（名前を変えるかは作者が決める）。

## 関連

- リリース: `references/workflows/release.md`
- GitHub Actions: `references/workflows/ci.md`
