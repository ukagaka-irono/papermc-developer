# プロジェクトの構成

`scripts/new-plugin.ps1` が作るプロジェクト（Gradle Kotlin DSL、Java）を例に、どのファイルが何をするか。既存のプロジェクトが Maven や Groovy DSL、Kotlin でも、考え方は同じ。

```
<プロジェクト>/
  settings.gradle.kts         プロジェクト名（jar の名前になる）と、JDK を自動で取る foojay-resolver
  build.gradle.kts            依存、Java の版、plugin.yml への版の埋め込み、テスト、runServer
  gradle.properties           Gradle の動作設定（キャッシュなど）
  gradlew, gradlew.bat        Gradle Wrapper。Gradle を入れなくてもビルドできる。コミットする
  gradle/wrapper/             Wrapper の本体（gradle-wrapper.jar と .properties）。コミットする。手で編集しない
  src/main/java/<パッケージ>/  コード
  src/main/resources/
    plugin.yml                プラグインの記述（または paper-plugin.yml）
    config.yml                既定の設定。saveDefaultConfig() が plugins/<名前>/config.yml に書き出す
  src/test/java/<パッケージ>/  MockBukkit のテスト（references/testing.md）
  PLUGIN.md                   このプラグインに固有の情報（AI が最初に読む）
  AGENTS.md, CLAUDE.md        PLUGIN.md とスキルを使うことの短い案内
  .github/workflows/          GitHub Actions（-Workflow のとき。references/workflows/ci.md）
  build/                      ビルドの成果物（build/libs/*.jar、build/release/）。コミットしない
  run/                        ./gradlew runServer のサーバー。コミットしない
```

## build.gradle.kts の要点

- **paper-api は `compileOnly`。** サーバーが持っているので jar に入れない（`implementation` にすると jar にサーバーの API が入り、動かない・巨大になる。`scripts/build-release.ps1` が見つける）。
- API の依存の書き方は、Minecraft の版で違う。**26.1 以降は `io.papermc.paper:paper-api:<版>.build.+`**（例: `26.3.build.+`。特定のビルドなら `26.3.build.229-stable`）、**1.17〜1.21.11 は `io.papermc.paper:paper-api:<版>-R0.1-SNAPSHOT`**、1.9.4〜1.16.5 は `com.destroystokyo.paper:paper-api`、1.7.10 と 1.8.8 は `org.github.paperspigot:paperspigot-api`（`references/versions.md`）。今の値は `scripts/versions.ps1 -Minecraft <版>`。
- リポジトリは `https://repo.papermc.io/repository/maven-public/`。
- Java は `java { toolchain.languageVersion.set(JavaLanguageVersion.of(N)) }`。N は対象の Minecraft が要求する版（`versions.ps1` の `Java minimum`）。ツールチェーンの JDK が無ければ、foojay-resolver が取ってくる。
- `processResources` の `expand` で、`plugin.yml` の `version: '${version}'` に `build.gradle.kts` の `version` を埋め込む。版は `build.gradle.kts` の 1 か所で管理する。`plugin.yml` に `$` を書くときは `$$` のように扱いに注意（Groovy のテンプレートとして展開される）。
- `-Xlint:deprecation` で、非推奨の API を使うと警告が出る。`scripts/check.ps1` がそれを表示する。
- ライブラリを jar に同梱するときは shadow（`com.gradleup.shadow`）を足し、`relocate` でパッケージ名を変える（ほかのプラグインの同じライブラリとぶつからないように）。Paper プラグインなら、`loader`（`PluginLoader` と `MavenLibraryResolver`）で起動時に取らせる方法もある。`plugin.yml` の `libraries:` も Maven Central のものを起動時に取らせられる。どれにするかは作者と決める。

## plugin.yml と paper-plugin.yml

| | `plugin.yml`（Bukkit 形式） | `paper-plugin.yml`（Paper プラグイン） |
|---|---|---|
| 動くサーバー | Paper、Spigot など | Paper（と Folia）だけ |
| 状態 | 安定 | Paper のドキュメントでは「実験的」 |
| コマンド | `commands:` に書いて `getCommand` で処理、または Brigadier（ライフサイクル API） | Brigadier（ライフサイクル API）だけ。`commands:` は無く、`getCommand` は null |
| 依存 | `depend:`、`softdepend:`、`loadbefore:` | `dependencies:` の `bootstrap:` と `server:`（`load`、`required`、`join-classpath`） |
| 起動前の処理 | 無い | `bootstrapper:`（データパックやレジストリへの登録）、`loader:`（ライブラリ） |
| クラスの見え方 | ほかのプラグインのクラスが見える | 宣言した依存のものだけ見える |

迷ったら `plugin.yml` にする（テンプレートの既定）。`bootstrapper` で起動前にしかできないこと（カスタムのエンチャントなどのレジストリ登録）が要るときに `paper-plugin.yml` を選ぶ。両方を 1 つの jar に入れると、Paper は `paper-plugin.yml` を使う。

**必須の項目**: `name`（英数字と `_` `.` `-`。空白不可）、`version`、`main`（`JavaPlugin` を継承したクラスの完全名）。**1.13 以降を対象にするなら `api-version` も必ず書く**（無いと古いプラグインとして扱われ、遅く、古い素材名に変換される。`paper-plugin.yml` では必須）。`api-version` は、そのプラグインが動く**いちばん古い**サーバーの版で、ビルドに使う paper-api より新しくしない。1.20.5 より前のサーバーは `1.<マイナー>`（`'1.16'`）しか受け付けない。1.12.2 以前には `api-version` は無い（`references/versions.md`）。

1.20.4 以前を対象にするテンプレートは、コマンドを `plugin.yml` の `commands:` に宣言し（`permission:` も付ける）、`CommandExecutor` で処理する。項目の一覧は https://docs.papermc.io/paper/dev/plugin-yml/index.md 。

権限は `permissions:` に、`default: true`（全員）/ `op` / `not op` / `false` で宣言する。宣言しない権限は OP だけが持つ。

## コミットするもの・しないもの

コミットする: `src/`、ビルドファイル、`gradlew`、`gradlew.bat`、`gradle/wrapper/`、`PLUGIN.md`、`AGENTS.md`、`CLAUDE.md`、`.gitignore` など。
コミットしない（`templates/gitignore` が除外する）: `build/`、`.gradle/`、`run/`、`target/`、IDE の設定、作ったサーバーの jar。トークンやパスワードの入ったファイルは、どこにも置かない。
