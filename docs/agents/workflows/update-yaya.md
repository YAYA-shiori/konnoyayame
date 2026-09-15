# YAYA（yaya.dll とシステム辞書）の更新

## 使うとき

作者が「YAYA を更新して」「YAYA を新しくして」「yaya.dll を更新して」「システム辞書を更新して」「yaya-dic を更新して」「SHIORI を最新に」と言ったとき。

**作者にはっきり頼まれたときだけ行う。自分から始めない。** GitHub からのダウンロードと、yaya.dll やシステム辞書のファイルの置き換えを伴う。

yaya.dll（YAYA 本体）とシステム辞書（[yaya-dic](https://github.com/YAYA-shiori/yaya-dic)）は、組にして更新するのが望ましい（システム辞書は、新しい YAYA で入った関数を使うことがある）。どちらか一方だけを頼まれたときも、もう一方も一緒に更新することを勧める。作者が片方だけでよいと言ったら、`-SkipSystemDic`（yaya.dll だけ）か `-SkipDll`（システム辞書だけ）を付ける。

## 注意: システム辞書の場所と形は決まっていない

過去のゴーストでは、システム辞書が `ghost/master/dic/system/` にあるとは限らない。`ghost/master/system/` の下や、`ghost/master/` の直下に置かれていることもある。形も、git の submodule のことも、git で管理された普通のファイルのことも、git で管理すらされていないこと（nar をインストールしたフォルダなど）もある。

場所と形を決めつけず、そのゴーストが実際にどのファイルをどう読み込んでいるかを調べてから、柔軟に対応する。今の yaya-dic の構成になっていなければ、下の「古い構成のシステム辞書を再編する」に沿って辞書群を再編してから更新する。

## tools/update-yaya.ps1 がすること

- yaya.dll: yaya-shiori のリリースの `yaya.zip` から取る（最新リリース、または `-Tag`）。
- システム辞書: yaya-dic にはリリースもタグも無いので、既定のブランチの最新のコミットを取る。`ghost/master/dic/system/`、`ghost/master/system/` の順に、今の yaya-dic の構成（`yaya_base/shiori3.dic` がある）のフォルダを探し、その形によって次のように動く。

| システム辞書のフォルダ | 動作 |
|---|---|
| git のチェックアウト（submodule など。フォルダに `.git` がある） | `git fetch` して最新のコミットに切り替える。未コミットの変更や、yaya-dic に無いコミットがあるときは何もしない |
| 普通のファイル（git で管理したフォルダでも、nar をインストールしただけのフォルダでも） | 最新のコミットの zip から、変わったファイルを置き換え、無いファイルを作る。作者が設定のために変えることのある `yaya_base/config.dic` と `_loading_order.txt` は、手元と違えば置き換えず、新しい版を `<ファイル>.yaya-dic-new` として横に置く。yaya-dic に無いファイルは `extra` と表示するだけで残す |
| 上のどちらでもない（`yaya_shiori3.dic` などの古い名前で置かれている、`yaya_base/` が無い） | 何もしない |

- yaya.dll、システム辞書の順に置き換え、それぞれの後で `tools/check-dic.ps1` を実行する。チェックに失敗したら、その部分を元に戻し、その先は更新しない。
- システム辞書を更新できない状態のときは、yaya.dll も含めて何も変えない。
- 終了コード: 0 更新した・最新だった・確認のみ / 1 失敗 / 2 システム辞書に手作業が要る（古い構成、手元の変更、`.yaya-dic-new` のマージ待ち）。

## 手順

1. 確認だけを行う（GitHub からダウンロードすることを一言伝える。作者が YAYA のタグを指定したときだけ `-Tag <タグ>` を付ける）:
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-yaya.ps1 -DryRun`
   次を短くまとめて伝える。
   - yaya.dll: 今の版（`current`）と更新先（`release`）
   - システム辞書: 場所、形（`kind`）、今の版と最新（`current` / `latest`）。普通のファイルなら `update` / `create` / `CONFLICT` / `extra` の行
2. 終了コードが 2 なら、出力に応じて先に片付ける。
   - `another layout than yaya-dic`: 古い構成。下の「古い構成のシステム辞書を再編する」へ進む。
   - `no system dictionary was found`: git clone したフォルダなら、`tools/setup.ps1` で submodule を取得する。そうでないのに見つからないときは、`ghost/master/yaya.txt` から読み込みの行をたどって、どこにあるかを調べる（「注意」の節）。
   - `uncommitted changes`: システム辞書のフォルダに手が入っている。`git -C <フォルダ> diff` を作者に見せ、残す必要があるかを相談する。残すなら、`git -C <フォルダ> stash` で退避してから更新し、`git -C <フォルダ> stash pop` で戻す（ぶつかったら、新しい版を土台にマージする）。システム辞書そのものの不具合を直したものなら、上流の yaya-dic に提案することも勧める。
   - `not in the history`: 手元でコミットしたか、フォークを使っている。どうするかを作者に聞き、勝手に切り替えない。
3. SSP でこのゴーストを起動していると、yaya.dll が使用中で置き換えられない。ゴーストを終了してもらう。
4. 了承を得てから、`-DryRun` を外して実行する。
5. 終了コードが 2 で `<ファイル>.yaya-dic-new` が残ったら、1 つずつ次のように片付ける。
   1. 差分を読む（`git diff --no-index <ファイル> <ファイル>.yaya-dic-new`）。
   2. 新しい版を土台に、手元の設定（`config.dic` の `#globaldefine` の値、`_loading_order.txt` で読むようにした・外した辞書など）を活かしたマージ案を作り、差分を見せる。手元のファイルが古い版のままだっただけなら、新しい版をそのまま使う。
   3. 了承を得てから元のファイルに書き込み、`.yaya-dic-new` を消す。
   4. `tools/check-dic.ps1` を通す。
6. `extra` の行があれば、そのファイルがどこかから読み込まれていないか（各 `_loading_order.txt`、`ghost/master/yaya.txt` とそこから `include` しているファイルの `dic` / `dicdir` の行）を確かめる。
   - 古い版の yaya-dic のファイル（`yaya_shiori3.dic` など）で、どこからも読み込まれていなければ、作者に確認して消す。
   - 作者が自分で置いたファイルなら、ゴーストの辞書のフォルダ（`dic/` の下など）に移すことを提案する。
7. 確かめる。
   - `tools/check-dic.ps1` はスクリプトが実行済み。加えて `tools/shiori.ps1 -Eval '1+2'` が `3` を返すことを確かめる（システム辞書の `??` の処理を通る）。
   - 作者が SSP で試したいと言えば、`docs/agents/workflows/try-in-ssp.md` の手順で起動する。
8. 変わったことを伝える。
   - yaya.dll: 出力の `notes` のリリースノートを読み、互換性に関わる変更があれば要約する。
   - システム辞書: git なら出力の `changes` の URL、普通のファイルなら `history` の URL のコミット一覧（手元がどの版だったかは分からないので、`update` になったファイルに関わる最近のもの）を読み、主な変更を要約する。
9. git の作業コピーなら、変更をコミットするか聞く（勝手にコミットしない）。submodule を更新したときは、ゴーストのリポジトリで submodule のフォルダ（例: `ghost/master/dic/system`）の変更をコミットしないと、新しい版が記録されない。

## 古い構成のシステム辞書を再編する

「注意」の節のとおり、古いゴーストのシステム辞書は、さまざまな場所と形で置かれている。`tools/update-yaya.ps1` はそのままでは更新できないので、作者の了承を得てから、今の yaya-dic の構成に辞書群を再編する。

### 1. 調べる（まだ何も変えない）

- `ghost/master/yaya.txt`、そこから `include` しているファイル（`system_config.txt` など）、緊急モードの `ghost/master/yaya_emerg.txt` を読み、システム辞書を読み込んでいる行（`dic, ...` / `dicdir, ...`）をすべて探す。
- 読み込まれているファイルのうち、どれがシステム辞書かを見分ける。yaya-dic は 2022 年 6 月にフォルダ分けと改名をしたので、それより前のゴーストでは次の名前になっている。

  | 古い名前 | 今の yaya-dic |
  |---|---|
  | `yaya_shiori3.dic` | `yaya_base/shiori3.dic` |
  | `yaya_optional.dic` | `yaya_base/optional.dic` |
  | `yaya_compatible.dic` | `yaya_base/compatible.dic` |
  | `yaya_config.txt`（古いテンプレートが `ghost/master/` に置いていた設定辞書）、`yaya_config.dic` | `yaya_base/config.dic` |
  | `aya_lilith.dic`、`aya_lilith_ex.dic` | `aya_lilith/aya_lilith.dic`、`aya_lilith/aya_lilith_ex.dic` |

  名前が違っていても、中身が yaya-dic と同じ辞書（`SHIORI3FW.`、古い版では `SHIORI_FW.` で始まる関数を定義している）なら、システム辞書として扱う。見分けがつかないものや、YAYA より前（文 / AYA）の辞書は、作者に相談する。
- 作者が手を入れたところを探す。
  - ゴーストが git で管理されていれば、`git log` でシステム辞書のファイルの変更履歴を見る。
  - そうでなければ、yaya-dic を一時フォルダに clone し、今の名前のパスの履歴（例: `git log --follow -- yaya_base/shiori3.dic`。改名の前もたどれる）から中身の近い版を探して差分を取る（改行コードの違いは無視する）。
  - 特に引き継ぐもの: 設定辞書（`yaya_config.txt` / `config.dic`）の `#globaldefine` などの値、`yaya_optional.dic` や `yaya_compatible.dic` を読んでいたかどうか、あやりりす（`aya_lilith`）を使っていたかどうか。
  - システム辞書の関数そのものを書き換えていたら、ゴーストの辞書の側で実現できないか、上流の yaya-dic に提案するかを作者と相談する。
- 分かったこと（今の置き場所と読み込みの行、作者の変更、再編の案）を作者に見せ、了承を得る。

### 2. 再編する

置き場所は、テンプレートから作ったゴーストと同じ `ghost/master/dic/system/` にする。既存の `ghost/master/system/` を使い続けたいと作者が言えば、そこでもよい（開発キットのスクリプトはどちらにも対応している）。

1. yaya-dic を置く。
   - ゴーストを git で管理していて、作者が submodule を望むとき: `git submodule add https://github.com/YAYA-shiori/yaya-dic.git ghost/master/dic/system`。GitHub Actions でチェックやリリースをしているなら、checkout で submodule も取得する設定（`submodules: recursive`）になっているか確かめる。
   - それ以外（submodule を使わない、git を使っていない）: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-yaya.ps1 -SkipDll -SystemDicDir dic/system` で、空のフォルダに最新の yaya-dic を置く。`system/` を使うときは、古いファイルを片付けてから `-SystemDicDir system` にする。
2. 作者の設定を引き継ぐ。`yaya_base/config.dic` の値と、`_loading_order.txt` で読む辞書（`optional.dic`、`compatible.dic`、`aya_lilith`）を、調べた結果に合わせる。書き方は、yaya-dic の `README.md` と各フォルダの `_loading_order.txt` を読んで合わせる。submodule の中のファイルを変えると、更新のたびに退避と復元が要るようになることも伝える。
3. 読み込みの行を書き換える。`yaya.txt`、そこから `include` しているファイル、`yaya_emerg.txt` にある古いシステム辞書の行を消し、ほかの辞書より前に `dicdir, dic/system` の 1 行を置く（テンプレートでは `system_config.txt` に書き、`yaya.txt` と `yaya_emerg.txt` の最初で `include` している）。緊急モードでもシステム辞書が読まれるようにする。
4. 古いシステム辞書のファイルを消す（git で管理していれば `git rm`）。
5. ネットワーク更新で配布しているゴーストでは、利用者の環境に古いファイルが残る。消したファイルを `delete.txt` に書くことを提案する（書式は https://ssp.shillest.net/ukadoc/manual/descript_install.html ）。
6. `GHOST.md` の辞書の構成の説明を、新しい置き場所に合わせて直す。

### 3. 確かめる

1. `tools/check-dic.ps1` を通す。`charset.dic` が UTF-8 でないゴーストでは、文字化けによるエラーが出ていないか特に気をつける（yaya-dic の `_loading_order.txt` は、各ファイルを `UTF-8` と指定して読み込んでいる）。
2. `tools/shiori.ps1 -Eval '1+2'` が `3` を返す。
3. `tools/doctor.ps1` の `system dictionary` が新しい置き場所（例: `ghost/master/dic/system`）になっている。
4. `tools/update-yaya.ps1 -DryRun` で、システム辞書が `already up to date` になる。続けて、上の「手順」に戻って yaya.dll も更新する。
5. 作者に SSP で起動して確かめてもらう（`docs/agents/workflows/try-in-ssp.md`）。起動、ランダムトーク、メニューなど、ふだんの動きを一通り見る。
6. git の作業コピーなら、変更をコミットするか聞く（勝手にコミットしない）。
