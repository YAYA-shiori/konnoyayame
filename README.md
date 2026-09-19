# テンプレートゴースト 紺野ややめ ＋ バイブコーディング道具箱(YAYA/Win版)

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
- 自分のゴーストとして配布するときに変えるところ（名前、作者、インストール先、ネットワーク更新の URL など）は、[docs/agents/standalone.md](docs/agents/standalone.md) と、`GHOST.md` の「テンプレートから独立させるときの追加項目」にチェックリストがあります。

## AI エージェントで開発する (Vibe Coding)

このゴーストには、AI コーディングエージェント（Claude Code、Codex、GitHub Copilot など）で開発するための開発キットが入っています。
リポジトリを clone したフォルダでも、nar を SSP にインストールしたフォルダ（`<SSP>/ghost/konnoyayame/`）でも使えます。

開発キットは、Windows と Claude Code の組み合わせで作り、動作を確かめています。おすすめもこの組み合わせです。

- `tools/` のスクリプトの多くは、Windows でしか動きません（辞書やシェルのチェック、SSP での確認など。YAYA、SSP、チェック用ツールが Windows 用のため）。
- ほかのエージェントでも `AGENTS.md` に沿って使えますが、編集後の自動チェック、起動時の診断、仕様調査用のサブエージェントは、Claude Code でしか自動では動きません。

- [DEVKIT-GUIDE.md](DEVKIT-GUIDE.md) : 開発キットの使い方（あらかじめ入れておくもの、mac・Linux で使う場合、はじめかた、キットの更新、配布物にキットを含めるかどうか、別の YAYA ゴーストへの導入）
- [AGENTS.md](AGENTS.md) : エージェント向けの指示書（作業のルール、YAYA とさくらスクリプトの要点、依頼の言い回しと手順書の対応）。開発コマンド、構成、独立ゴーストにするときのチェックリスト、作業の手順書は `docs/agents/` にあります
- [GHOST.md](GHOST.md) : このゴーストに固有の情報（キャラクター、サーフェス、ライセンス、辞書の構成）。自分のゴーストを作ったら、その内容に書き直します

まずは [DEVKIT-GUIDE.md](DEVKIT-GUIDE.md) の「あらかじめ入れておくもの」を見て、このフォルダで AI エージェントを起動し、「セットアップして」と頼んでください。

紺野ややめを元にしていない、手元の YAYA ゴーストにも、開発キットだけを入れられます（辞書やシェルには手を加えません）。手順は [DEVKIT-GUIDE.md](DEVKIT-GUIDE.md#別の-yaya-ゴーストに開発キットを入れる) の「別の YAYA ゴーストに開発キットを入れる」にあります。

# ライセンス

Public Domain (Unlicense)

煮るなり焼くなり好きにしてください。

ただし、シェル（`shell/master/`）は SATO M 氏の作品で、CC BY-NC-ND 2.1 JP です（`shell/master/descript.txt` を参照）。
