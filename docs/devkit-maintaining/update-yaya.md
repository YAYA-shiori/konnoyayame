# システム辞書の更新

- `tools/update-yaya.ps1` のシステム辞書（yaya-dic）:
  - yaya-dic にはリリースもタグも無いので、既定のブランチの最新のコミットを使う。git のチェックアウトでは `git fetch origin HEAD` の `FETCH_HEAD`、それ以外では GitHub API の `commits/HEAD` の SHA の zip。
  - 今の構成かどうかは `yaya_base/shiori3.dic` の有無で見る（`Test-DevkitYayaDicLayout`）。yaya-dic は 2022-06-17 に `yaya_shiori3.dic` などをフォルダに分けて改名した。古い名前は `$DevkitOldSystemDicNames` にあり（`yaya_config.txt` は古いテンプレートがゴースト側に置いていた設定辞書）、`Find-DevkitOldSystemDicFiles` が `ghost/master` の下を探す。古い構成は自動では直さず、終了コード 2 で手順書の再編に回す。doctor も、`yaya_shiori3.dic` が見つかれば system-dic を不足にしない（ゴーストは動くため）。
  - 普通のファイルには、lock のような「入れた版」の記録が無い。作者が変えることのある `yaya_base/config.dic` と `_loading_order.txt` は、新しい版と違えば置き換えずに `.yaya-dic-new` を横に置く（上流が変えただけでも衝突になるが、手順書でエージェントがマージする）。それ以外は作者が変えない前提で置き換える。`.github/` など先頭がドットのものは取り込まない。
  - git のチェックアウトは、未コミットの変更か、今のコミットが新しいコミットの祖先でなければ切り替えない。`.gitmodules` に載っていても、ルートに `.git` が無いフォルダ（nar など）は submodule として扱わない。
  - 辞書チェックは yaya.dll とシステム辞書のそれぞれの後で行い、失敗した部分だけを戻す。どちらが原因かを分けるため。
- `tools/update-yaya.ps1` の yaya.dll:
  - yaya-shiori は 500 系と 600 系を並行して（同じ日に）出す。どちらの系列が正式版かは時期によって変わる（600 系は Tc603-1 より前は pre-release だった）ので、エージェント向けの文書には今の状態を書かず、出力の `(pre-release)` で判断させる。スクリプトも、pre-release のフラグでは選ばず、**系列**で選ぶ。系列は、タグ `TcXYY-N` の X と、yaya.dll のファイルバージョン（`6, 02, 4, 0` の形）の先頭の数。
  - 一覧（`releases?per_page=100`）から `yaya.zip` があり、タグが読めるものを集め、手元の yaya.dll と同じ系列で、タグの版がいちばん大きいもの（同じなら日付の新しいもの。`Tc573-3` と `Tc573-3A`）を取る。`releases/latest` や一覧の先頭（日付順）で選ぶと、後から出した別の系列を選んでしまう。
  - 系列を変えるのは `-Series` を付けたときだけ。手元より大きい系列があれば `newer` の行で知らせる。yaya.dll が無い、ファイルバージョンが読めない、その系列のリリースが一覧に無いときは、最新の正式版（日付）の系列にする。
  - 手元より古いファイルバージョンは、`-Tag` / `-Series` / `-Force` が無ければ入れない。系列の決め方からは起きないはずだが、最後の防壁として残している。
  - 以前は `-Prerelease`（最新の正式版と最新の pre-release の版の大きいほう）だったが、600 系のゴーストで付け忘れると更新されず、600 系が正式版になると 500 系のゴーストが勝手に 600 系に上がるので、系列で選ぶ形にした。
  - Windows PowerShell 5.1 の `Invoke-RestMethod` は JSON の配列を 1 つのオブジェクトとして返すので、`foreach` で展開してから見る。
