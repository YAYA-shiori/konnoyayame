# システム辞書の更新

- `tools/update-yaya.ps1` のシステム辞書（yaya-dic）:
  - yaya-dic にはリリースもタグも無いので、既定のブランチの最新のコミットを使う。git のチェックアウトでは `git fetch origin HEAD` の `FETCH_HEAD`、それ以外では GitHub API の `commits/HEAD` の SHA の zip。
  - 今の構成かどうかは `yaya_base/shiori3.dic` の有無で見る（`Test-DevkitYayaDicLayout`）。yaya-dic は 2022-06-17 に `yaya_shiori3.dic` などをフォルダに分けて改名した。古い名前は `$DevkitOldSystemDicNames` にあり（`yaya_config.txt` は古いテンプレートがゴースト側に置いていた設定辞書）、`Find-DevkitOldSystemDicFiles` が `ghost/master` の下を探す。古い構成は自動では直さず、終了コード 2 で手順書の再編に回す。doctor も、`yaya_shiori3.dic` が見つかれば system-dic を不足にしない（ゴーストは動くため）。
  - 普通のファイルには、lock のような「入れた版」の記録が無い。作者が変えることのある `yaya_base/config.dic` と `_loading_order.txt` は、新しい版と違えば置き換えずに `.yaya-dic-new` を横に置く（上流が変えただけでも衝突になるが、手順書でエージェントがマージする）。それ以外は作者が変えない前提で置き換える。`.github/` など先頭がドットのものは取り込まない。
  - git のチェックアウトは、未コミットの変更か、今のコミットが新しいコミットの祖先でなければ切り替えない。`.gitmodules` に載っていても、ルートに `.git` が無いフォルダ（nar など）は submodule として扱わない。
  - 辞書チェックは yaya.dll とシステム辞書のそれぞれの後で行い、失敗した部分だけを戻す。どちらが原因かを分けるため。
