# 「YAYA」テンプレートゴースト 紺野ややめ

- original author : umeici
- change by : ukiya
- modernized by : ponapalt and contributors

https://ms.shillest.net/yayame.xhtml

# GitHubからダウンロードする方へ

GitHubのプロジェクトページ

https://github.com/YAYA-shiori/konnoyayame

からダウンロードしようとしている方は、右横のReleasesからダウンロードしてください。

このリポジトリをzipで取得しても不完全です。

# 改造のしかた

紺野ややめは、SHIORI「YAYA」で自分のゴーストを作るための土台（テンプレート）です。辞書を手で編集しても、AI コーディングエージェントに手伝ってもらってもかまいません。

## 手で編集する

- 辞書の本体は `ghost/master/dic/normal/` にある `.dic` ファイルです。文字コードは UTF-8（BOM なし）です。
- どのファイルに何が書いてあるか（ランダムトーク、起動・終了、マウスへの反応、メニューなど）、キャラクターと使えるサーフェス番号、トークの書き方の決まりは、[GHOST.md](GHOST.md) にまとめてあります。
- YAYA の文法の要点とトークでよくある失敗は、[AGENTS.md](AGENTS.md) の「YAYA 辞書の書き方の要点」と「トーク（さくらスクリプト）の書き方」にあります。AI エージェント向けの指示書ですが、人が読んでもわかるように書いてあります。
- 詳しい仕様は、次を見てください。
  - YAYA の文法と関数: YAYA Wiki（https://emily.shillest.net/ayaya/ ）
  - さくらスクリプト、SHIORI イベント、設定ファイル: UKADOC（https://ssp.shillest.net/ukadoc/manual/ ）
- 辞書にエラーがあると、ゴーストは緊急モードで起動し、ほとんど話さなくなります。Windows なら、同梱のスクリプトで辞書をチェックできます（最初の準備は [DEVKIT-GUIDE.md](DEVKIT-GUIDE.md) の「はじめかた」）。

  ```
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-dic.ps1
  ```

- シェル（`shell/master/`）は SATO M 氏の作品で、CC BY-NC-ND 2.1 JP です。画像を改変したものは配布できません。
- 自分のゴーストとして配布するときに変えるところ（名前、作者、インストール先、ネットワーク更新の URL など）は、`AGENTS.md` の「テンプレートから独立させるとき」と、`GHOST.md` の「テンプレートから独立させるときの追加項目」にチェックリストがあります。

## AI エージェントで開発する (Vibe Coding)

このゴーストには、AI コーディングエージェント（Claude Code、Codex、GitHub Copilot など）で開発するための開発キットが入っています。
リポジトリを clone したフォルダでも、nar を SSP にインストールしたフォルダ（`<SSP>/ghost/konnoyayame/`）でも使えます。

- [DEVKIT-GUIDE.md](DEVKIT-GUIDE.md) : 開発キットの使い方（あらかじめ入れておくもの、mac・Linux で使う場合、はじめかた、キットの更新、配布物にキットを含めるかどうか）
- [AGENTS.md](AGENTS.md) : エージェント向けの指示書（構成、ルール、YAYA とさくらスクリプトの要点、独立ゴーストにするときのチェックリスト）
- [GHOST.md](GHOST.md) : このゴーストに固有の情報（キャラクター、サーフェス、ライセンス、辞書の構成）。自分のゴーストを作ったら、その内容に書き直します

まずは [DEVKIT-GUIDE.md](DEVKIT-GUIDE.md) の「あらかじめ入れておくもの」を見て、このフォルダで AI エージェントを起動し、「セットアップして」と頼んでください。

手元にある別の YAYA ゴーストにも、開発キットだけを入れられます（次の「別の YAYA ゴーストに開発キットを入れる」）。

# 別の YAYA ゴーストに開発キットを入れる

紺野ややめを元にしていない、手元の YAYA ゴーストにも、開発キットだけを入れられます。辞書やシェルには手を加えません。
先に [DEVKIT-GUIDE.md](DEVKIT-GUIDE.md) の「あらかじめ入れておくもの」を見て、AI エージェント（自分で入れる場合は PowerShell）を用意してください。

## 入れられるゴースト

- SHIORI が YAYA で、ゴーストのフォルダに `ghost/master/descript.txt` と `ghost/master/yaya.dll` があること
- Windows であること（mac・Linux では、[DEVKIT-GUIDE.md](DEVKIT-GUIDE.md) の「mac・Linux で使う場合」の範囲で使えます）
- SSP にインストールしたフォルダでも、git で管理しているフォルダでもかまいません

## 入るファイル

| 区分 | ファイル | 入れるとき・更新するとき |
|---|---|---|
| キット | `AGENTS.md`<br>`CLAUDE.md`<br>`DEVKIT-GUIDE.md`<br>`.mcp.json`<br>`.claude/`<br>`.github/workflows/auto_check.yml`<br>`tools/` | 入れたときに作られ、キットを更新すると新しい版に置き換わります |
| 初回だけ作るもの | `GHOST.md`<br>`.narignore`<br>`.updateignore`<br>`.gitattributes`<br>`.editorconfig`<br>`ghost/master/yayalint_config.lua` | 無いときだけ作られます。あとはゴーストのものです |

それ以外のファイル（辞書、シェル、`descript.txt`、readme など）は変わりません。同じ名前のファイル（たとえば自分で書いた `AGENTS.md`）がすでにあるときは上書きせず、キットの版を `<ファイル名>.devkit-new` として横に置きます。

## AI エージェントに頼んで入れる

作業の前に、ゴーストのフォルダをバックアップしてください（git で管理しているなら、コミットしておけば十分です）。

1. キットを入れたいゴーストのフォルダ（`ghost` と `shell` があるフォルダ）で、AI エージェントを起動します（Claude Code なら、そのフォルダで `claude`）。
2. 次のように頼みます。

   ```
   https://github.com/YAYA-shiori/konnoyayame の README にある「別の YAYA ゴーストに開発キットを入れる」の手順で、このフォルダに開発キットを入れてください。
   ```

   エージェントは導入に使うスクリプトを取得し、作られるファイルの一覧を見せてから、了承を得て導入します。同じ名前のファイルがあったときは、マージを手伝います。
3. 導入が終わったら、AI エージェントを起動し直します（キットの指示書、スキル、自動チェックは、起動したときに読み込まれます）。
4. 「セットアップして」と頼みます。チェック用ツールの取得、SSP の場所の設定、動作確認に加えて、辞書とシェルを読んで `GHOST.md` の下書きを作ります（Claude Code では `/getting-started` スキル）。
5. `GHOST.md` の下書きを読んで、キャラクターの人物像、使えるサーフェス、シェルのライセンス、トークの書き方の決まりなどを直してください（導入先に入る `DEVKIT-GUIDE.md` の「GHOST.md を仕上げる」）。

### 導入を頼まれた AI エージェントへ

この手順で導入を頼まれた AI エージェントは、次を守ってください。

1. 導入先が「入れられるゴースト」の条件を満たしているか確かめる。
2. 下の「自分で入れる」の手順 1 と 2 のコマンドでスクリプトを取得し、`-DryRun` で実行する。GitHub からダウンロードすることを、先に作者に伝える。
3. 作られるファイル、`CONFLICT`（同じ名前のファイルがすでにある）、`seed`（無かったので作る）を作者に伝え、了承を得てから `-DryRun` を外して実行する。
4. `.devkit-new` ができたら、1 つずつ差分を見せ、作者のファイルの内容を活かしたマージ案を示し、了承を得てから書き込んで `.devkit-new` を消す。ゴーストだけの決まりは `GHOST.md` に移すことを提案する。
5. 下の「すでにあるファイルとの関係」に当てはまるもの（既存の `.narignore` など）があれば、対応を提案する。
6. 取得に使った一時フォルダを消し、作者に、エージェントを起動し直してから手順 4 以降に進むよう伝える。

## 自分で入れる

作業の前に、ゴーストのフォルダをバックアップしてください。

1. PowerShell を開き（Windows はスタートメニューの「Windows PowerShell」、mac・Linux はターミナルで `pwsh`）、次を実行して、導入に使うスクリプトを取得します。

   ```powershell
   [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
   $work = Join-Path ([IO.Path]::GetTempPath()) 'ghost-devkit'
   Remove-Item $work, "$work.zip" -Recurse -Force -ErrorAction SilentlyContinue
   Invoke-WebRequest -UseBasicParsing https://github.com/YAYA-shiori/konnoyayame/archive/refs/heads/master.zip -OutFile "$work.zip"
   Expand-Archive "$work.zip" $work
   $installer = Join-Path $work 'konnoyayame-master/tools/update-devkit.ps1'
   ```

2. 同じ PowerShell で、`-DryRun` を付けて実行します。ここでは何も書き込まず、作られるファイルの一覧だけが表示されます。`-Target` のフォルダは、キットを入れるゴーストのフォルダ（`ghost` と `shell` があるフォルダ）に置き換えてください。

   Windows:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Target 'C:\SSP\ghost\myghost' -DryRun
   ```

   mac・Linux:

   ```powershell
   pwsh -NoProfile -File $installer -Target '/Users/me/ghosts/myghost' -DryRun
   ```

3. 一覧を確かめたら、`-DryRun` を外して同じコマンドをもう一度実行します。キットそのものは、このリポジトリの最新リリース（自動チェックを通った版）から取得されます。最後に `merge each file below ...` と表示されたら、`.devkit-new` ができています（下の「すでにあるファイルとの関係」を見てください）。
4. 取得に使った一時フォルダは、消してかまいません（`Remove-Item $work, "$work.zip" -Recurse -Force`）。
5. その後は、上の「AI エージェントに頼んで入れる」の手順 3 から続けてください。

## すでにあるファイルとの関係

- **`AGENTS.md`、`CLAUDE.md`、`.claude/settings.json` などを自分で置いていた場合**: 上書きされず、キットの版が `<ファイル名>.devkit-new` として置かれます。見比べて、必要な部分を元のファイルにまとめてから、`.devkit-new` を消してください。AI エージェントにマージを頼むこともできます（Claude Code では `/update-devkit` スキル）。自分のゴーストだけの決まりは `GHOST.md` に移しておくと、次にキットを更新したときに衝突しません。
- **`.narignore` をすでに使っていた場合**: 上書きされません。ダウンロードしたツールや各自の設定を nar から除外するために、`.narignore` に次の 1 行を足してください。足さないと、`tools/bin/` や `tools/local.json` が nar に入ってしまいます。

  ```
  include:tools/devkit.narignore
  ```

  `.updateignore` を使っていて、その中で `include:.narignore` をしていない場合は、`.updateignore` にも同じ行を足します。
- **古い形式の `developer_options.txt` を使っている場合**: `.narignore` と両方あると、両方が処理されて紛らわしくなります。`.narignore` / `.updateignore` に移すことをおすすめします。
- **`.gitignore`**: 追記は要りません。除外が必要なものは、キットの `tools/.gitignore` と `.claude/.gitignore` で除外しています。
- **GitHub**: `.github/workflows/auto_check.yml` が入り、`main` / `master` ブランチに push するたびに辞書チェックが走ります。要らなければ消してかまいません（消したファイルは、キットを更新しても戻りません）。自動リリースのワークフローは入りません。

## 導入した後

キットの更新、配布物（nar）にキットを含めるかどうかなど、導入した後の使い方は、導入先に入る `DEVKIT-GUIDE.md` にあります。

`tools/devkit.lock.json` は、どの版のキットを入れたかの記録です。消さずに残し、git で管理しているならコミットしてください。

# ライセンス

Public Domain (Unlicense)

煮るなり焼くなり好きにしてください。

ただし、シェル（`shell/master/`）は SATO M 氏の作品で、CC BY-NC-ND 2.1 JP です（`shell/master/descript.txt` を参照）。
