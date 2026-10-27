#!/bin/bash
# Kyocera ECOSYS P8060cdn を新しい macOS で使えるようにする設定スクリプト
#  - 京セラ独自フィルター（新しい macOS で落ちる）を使わない PPD に差し替える
#  - デフォルトを白黒にする
#  - 印刷のユーザー名を学籍番号にする（~/.cups/client.conf）
# 使い方：「ターミナル」で  bash setup.sh
PRN_DEFAULT="Kyocera_P8060cdn"
MODEL_DEFAULT="8060cdn"
W="$HOME/kyocera-p8060cdn-fix"

read -r -p "学籍番号 / Student ID / 学号: " SID
SID=$(echo "$SID" | tr -d '[:space:]')
if [ -z "$SID" ]; then echo "!! 学籍番号が空です。"; exit 1; fi

read -r -p "プリンターの URI / Printer URI / 打印机地址（例: lpd://<server>/<queue>）: " URI
URI=$(echo "$URI" | tr -d '[:space:]')
if [ -z "$URI" ]; then echo "!! URI が空です。"; exit 1; fi

read -r -p "プリンター名 / Printer name [$PRN_DEFAULT]: " PRN
PRN=${PRN:-$PRN_DEFAULT}
read -r -p "機種 / Model [$MODEL_DEFAULT]: " MODEL
MODEL=${MODEL:-$MODEL_DEFAULT}

DIR=/Library/Printers/PPDs/Contents/Resources
NAME=$(ls "$DIR" 2>/dev/null | grep -i "$MODEL" | head -1)
if [ -z "$NAME" ]; then
  echo "!! $MODEL の PPD が見つかりません。京セラの macOS 用ドライバーをインストールしてから再実行してください。"
  exit 1
fi
SRC="$DIR/$NAME"
mkdir -p "$W"; cd "$W" || exit 1

echo "== [1/4] PPD を作成: $SRC"
case "$SRC" in *.gz) gunzip -c "$SRC" > orig.ppd;; *) cp "$SRC" orig.ppd;; esac
grep -vE '^\*cups(Pre)?Filter2?:' orig.ppd \
  | sed 's/^\*DefaultColorModel: .*/*DefaultColorModel: Gray/' > p8060cdn.ppd
echo "削除した行:"; grep -E '^\*cups(Pre)?Filter2?:' orig.ppd

echo "== [2/4] 変換テスト"
echo "test page" > test.txt
cupsfilter -p p8060cdn.ppd -m printer/foo -U "$SID" test.txt > test.prn 2> test.log
if [ $? -ne 0 ] || [ ! -s test.prn ]; then
  echo "!! 変換に失敗しました。test.log:"; tail -20 test.log; exit 1
fi
if ! strings test.prn | grep -aq "USERNAME = \"$SID\""; then
  echo "!! USERNAME が入っていません。ここで停止します。"; exit 1
fi
echo "OK"

echo "== [3/4] 印刷ユーザー名を $SID に設定（~/.cups/client.conf）"
mkdir -p "$HOME/.cups"
touch "$HOME/.cups/client.conf"
if grep -q '^User ' "$HOME/.cups/client.conf"; then
  sed -i '' "s/^User .*/User $SID/" "$HOME/.cups/client.conf"
else
  echo "User $SID" >> "$HOME/.cups/client.conf"
fi

echo "== [4/4] プリンターに適用（Mac のログインパスワードを入力）"
sudo lpadmin -p "$PRN" -P "$W/p8060cdn.ppd" -v "$URI" -E || exit 1
cupsenable "$PRN"
lpstat -p "$PRN"

echo
echo "完了しました。開いているアプリ（プレビュー、Chrome など）は一度 ⌘Q で終了してから印刷してください。"
echo "カラー印刷：印刷画面 →「プリンタオプション」→「プリンタの機能」→「グラフィックス」→「カラーモード」→「フルカラー」"
