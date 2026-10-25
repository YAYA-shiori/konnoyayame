# テンプレートゴースト 紺野ややめ

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

紺野ややめは、SHIORI「YAYA」で自分のゴーストを作るための土台（テンプレート）です。辞書を編集して、自分のゴーストを作ってください。

## 手で編集する

- 辞書の本体は `ghost/master/dic/normal/` にある `.dic` ファイルです。文字コードは UTF-8（BOM なし）です。
- どのファイルに何が書いてあるか（ランダムトーク、起動・終了、マウスへの反応、メニューなど）、キャラクターと使えるサーフェス番号、トークの書き方の決まりは、[GHOST.md](GHOST.md) にまとめてあります。
- 詳しい仕様は、次を見てください。
  - YAYA の文法と関数: yaya-docs（https://yaya-shiori.github.io/yaya-docs/ ）
  - さくらスクリプト、SHIORI イベント、設定ファイル: UKADOC（https://ssp.shillest.net/ukadoc/manual/ ）
- 辞書にエラーがあると、ゴーストは緊急モードで起動し、ほとんど話さなくなります。
- シェル（`shell/master/`）は SATO M 氏の作品で、CC BY-NC-ND 2.1 JP です。画像を改変したものは配布できません。
- 自分のゴーストとして配布するときに変えるところ（名前、作者、インストール先、ネットワーク更新の URL など）は、[GHOST.md](GHOST.md) の「テンプレートから独立させるときの追加項目」にチェックリストがあります。

# ライセンス

Public Domain (Unlicense)

煮るなり焼くなり好きにしてください。

ただし、シェル（`shell/master/`）は SATO M 氏の作品で、CC BY-NC-ND 2.1 JP です（`shell/master/descript.txt` を参照）。
