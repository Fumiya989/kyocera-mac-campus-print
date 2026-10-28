#!/bin/bash
# Kyocera ECOSYS P8060cdn を新しい macOS で使えるようにする設定スクリプト
#  - 京セラ独自フィルター（新しい macOS で落ちる）を使わない PPD に差し替える
#  - デフォルトを白黒にする
#  - 印刷のユーザー名を学籍番号にする（~/.cups/client.conf）
#  - 日本語のファイル名がパネルで文字化けしないよう、ジョブ名を Shift-JIS にする
# 使い方：「ターミナル」で  bash setup.sh
PRN_DEFAULT="Kyocera_P8060cdn"
MODEL_DEFAULT="8060cdn"
W="$HOME/kyocera-p8060cdn-fix"
FILTER_DIR=/Library/Printers/kyocera-p8060cdn-fix
FILTER="$FILTER_DIR/sjis-jobname"
HERE=$(cd "$(dirname "$0")" && pwd)
if [ ! -f "$HERE/sjis-jobname" ]; then echo "!! sjis-jobname が見つかりません。リポジトリごとダウンロードしてください。"; exit 1; fi

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
echo "*cupsFilter: \"application/vnd.cups-postscript 0 $FILTER\"" >> p8060cdn.ppd
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
sudo mkdir -p "$FILTER_DIR" || exit 1
sudo install -o root -g wheel -m 755 "$HERE/sjis-jobname" "$FILTER" || exit 1
sudo chmod 755 "$FILTER_DIR"
sudo lpadmin -p "$PRN" -P "$W/p8060cdn.ppd" -v "$URI" -E || exit 1
cupsfilter -e -p p8060cdn.ppd -m printer/foo -U "$SID" -t "テスト.txt" test.txt 2>/dev/null > test-sjis.prn
if head -n 3 test-sjis.prn | iconv -f SHIFT_JIS -t UTF-8 2>/dev/null | grep -q 'JOB NAME = "テスト.txt"'; then
  echo "ジョブ名の Shift-JIS 変換: OK"
else
  echo "!! ジョブ名の Shift-JIS 変換を確認できませんでした（印刷はできますが、日本語のファイル名が文字化けする場合があります）。"
fi
cupsenable "$PRN"
lpstat -p "$PRN"

echo
echo "完了しました。開いているアプリ（プレビュー、Chrome など）は一度 ⌘Q で終了してから印刷してください。"
echo "カラー印刷：印刷画面 →「プリンタオプション」→「プリンタの機能」→「グラフィックス」→「カラーモード」→「フルカラー」"
