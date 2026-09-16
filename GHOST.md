# GHOST.md

「紺野ややめ」に固有の情報です。AI エージェントは、作業の前に `AGENTS.md` とあわせて読みます。
作者が自由に書き換えるファイルで、開発キットの更新（`tools/update-devkit.ps1`）で上書きされることはありません。

## このゴーストについて

- 伺か（ukagaka）のゴースト「紺野ややめ」（`name` は「はろーYAYAワールド」）。SHIORI「YAYA」の**テンプレートゴースト**で、これを土台にして自分のゴーストを作ってもらうためのもの。
- 配布元: https://github.com/YAYA-shiori/konnoyayame （nar は Releases から）
- このリポジトリは、AI 開発キットの配布元も兼ねている。キットそのものを変えるときは `DEVKIT-MAINTAINING.md` を読む（リポジトリにだけあり、nar には入らない）。

## ライセンス

- シェル以外（辞書など）は Public Domain (Unlicense)。
- **シェル `shell/master/` は SATO M 氏の作品で、CC BY-NC-ND 2.1 JP**（`shell/master/descript.txt` 参照）。改変した画像の配布や商用利用はできない。画像そのものは編集しない。

## 辞書の構成

- `ghost/master/yaya.txt` が `dic/normal` を読む。辞書エラーのときは `yaya_emerg.txt` が `dic/emerg` を読む（緊急モード）。
- `ghost/master/dic/system/` はシステム辞書（yaya-dic の submodule）。
- `yaya_tmpl_util.dic` のテンプレート処理（`AYATEMPLATE.*`）が、マウス反応などの関数を名前で呼び出す。

## イベントと辞書ファイルの対応

| ファイル（`ghost/master/dic/normal/`） | 主な中身 |
|---|---|
| `yaya_aitalk.dic` | ランダムトーク（`RandomTalkEx`）、チェイントーク（例: `siritori`）、キー入力 `OnKeyPress`、時報と重なり `OnMinuteChange`（`--` の使用例）、見切れ |
| `yaya_bootend.dic` | 初回起動 `OnFirstBoot`、起動 `OnBoot`、終了 `OnClose`、時間帯の判定 `GetTimeSlot` |
| `yaya_mouse.dic` | なで・つつきへの反応。関数名は「種別＋スコープ番号＋当たり判定名」（例: `MouseMove0Head`、`MouseDoubleClick1`）。種別は `MouseMove`、`MouseDoubleClick`、`MouseWheelUp`、`MouseWheelDown`。テンプレートが自動で呼ぶ |
| `yaya_menu.dic` | メニュー `OpenMenu` と、選択肢ごとの処理 `Menu_*` |
| `yaya_communicate.dic` | ユーザーとの会話、他のゴーストとの会話（`TalkTo*` / `ReplyTo*`） |
| `yaya_change.dic` | ゴーストの切り替えや呼び出しのときのトーク |
| `yaya_etc.dic` | シェル変更、インストール、消滅（vanish）、ネットワーク更新、ヘッドライン、時刻合わせなどのイベント |
| `yaya_string.dic` | ユーザー名の初期値、メニュー項目の文字列などのリソース（`On_*`） |
| `yaya_word.dic` | トーク中に `%(ms)` のように埋め込む単語 |
| `yaya_homeurl.dic` | ネットワーク更新の URL（`On_homeurl`） |
| `yaya_tmpl_util.dic` | テンプレートの内部処理（`AYATEMPLATE.*`）と、それが名前を組み立てて呼ぶ関数を lint に伝える `OnSHIORI3FW.Lint.UsedFunctions`。必要なとき以外は触らない |

新しいイベントに反応させる関数は、内容の近い辞書ファイルに書く。`dic/normal/` に新しい `.dic` ファイルを置いた場合も自動で読み込まれる。

## キャラクターとサーフェス

| スコープ | キャラクター | 人物像（既存のトークから） | 使えるサーフェス |
|---|---|---|---|
| `\0`（`\h`） | 紺野ややめ | 一人称「わたし」。元気で天然ボケ、子どもっぽい。「ぷー」「えへへ」。自分がサンプルゴーストだと知っていて、メタな発言が多い | 0 素 / 1 照れ / 2 驚き / 3 不安 / 4 はうー / 5 笑い / 6 目閉じ / 7 怒り |
| `\1`（`\u`） | マック朗 | 一人称「おれ」。ツッコミ役で、口が悪い（「〜だろ」「やめろ」）。リンゴ（かじられた跡）にまつわるネタが多い | 10 素 / 11 刮目 |

- ややめの当たり判定（`surfaces.txt` の `collision`）は `Head`、`Face`、`Bust`、`Twintail`。
- 1030〜1033 と 1040〜1043 はアニメーション用の部品（`surfacetable.txt` の `__disabled` グループ）なので、トークでは使わない。
- トークでは上の表にある番号だけを使う。

## トークの書き方

- 話し始める側のスコープと表情を最初に指定する（`\0\s[5]...`）。両方の表情を先に決める `\u\s[10]\0\s[3]...` という書き方もある。
- 話し手を交代する前に `\w8` を入れる。同じ話し手の中の間は `\w5`〜`\w9`。沈黙の「‥‥」は `‥\w5‥\w5` と書く。
- 同じ話し手の中で改行するときは `\w9\n`。
- すでに話したスコープに戻って話すときは、`\n\n` で空行を入れてから続ける。
- ユーザーは `%(username)` で呼ぶ。

例（`yaya_aitalk.dic` より）:

```
'\0\s[1]マック朗って‥\w5‥\w5\w8\1なんだ？\w8\0\s[4]\n\n美味しくなさそうだよね。\w8\1\n\n‥\w5‥\w5かじったの、お前じゃないのか。\e'
```

- ややめが「おれ」と言う、マック朗が丁寧語で話す、のように口調を混ぜない。

## テンプレートから独立させるときの追加項目

`docs/agents/standalone.md` に加えて、このテンプレートでは次も変える。

- [ ] ネットワーク更新の URL は 2 か所ある: `ghost/master/dic/normal/yaya_homeurl.dic` と `ghost/master/dic/emerg/yaya_homeurl.dic` の `On_homeurl`
- [ ] シェル: `shell/master/` は SATO M 氏の CC BY-NC-ND シェルなので、改変した画像は配布できない
- [ ] 辞書に直接書かれたゴースト名: `yaya_menu.dic` の `OnStampInfo`（スタンプ帳で自分のスタンプを見分けるための `'はろーYAYAわーるど'` / `'紺野ややめ'`）
- [ ] ややめとマック朗に固有の台詞（`OnFirstBoot` の自己紹介、ランダムトーク、マウスへの反応など）
- [ ] `.github/workflows/auto_release.yml` の nar ファイル名（`yayame.nar`）とリリースの説明文。このワークフローは push のたびに**既存のリリースとタグをすべて削除して**作り直すので、残したいリリースがあるリポジトリでは書き換える
- [ ] nar をインストールしたフォルダから始めた場合、`ghost/master/dic/system/` は submodule ではなく普通のフォルダとしてコミットしてよい
- [ ] クレジットの例:「紺野ややめ（https://github.com/YAYA-shiori/konnoyayame）をもとに作成」
- [ ] この `GHOST.md` を新しいゴーストの内容に書き直し、この節は済んだら消す
