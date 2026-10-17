#!/bin/bash
# End-to-end loop: build, self-test, run the binary from this (Accessibility-trusted) terminal,
# type into TextEdit, expect a ghost suggestion, press Tab, expect the document to grow.
set -e
cd "$(dirname "$0")/.."
./build.sh | tail -1
BIN="$HOME/Applications/Omnikeys.app/Contents/MacOS/Omnikeys"
"$BIN" --selftest | tail -1
pkill -x Omnikeys 2>/dev/null || true; sleep 0.5
: > ~/Library/Logs/Omnikeys.log
"$BIN" >/dev/null 2>&1 &
sleep 3
grep -q "tap started" ~/Library/Logs/Omnikeys.log && echo "PASS tap started" || { echo "FAIL tap not started (Accessibility?)"; grep launch ~/Library/Logs/Omnikeys.log; exit 1; }
osascript <<'AS'
tell application "TextEdit"
  activate
  make new document
end tell
delay 1
tell application "System Events"
  keystroke "Dear Taylor, thanks for sending the drawings over. I had a look at the"
end tell
AS
sleep 3
if grep -q "SHOW completion" ~/Library/Logs/Omnikeys.log; then echo "PASS suggestion shown: $(grep "SHOW completion" ~/Library/Logs/Omnikeys.log | tail -1 | cut -c25-)"; else echo "FAIL no suggestion"; tail -5 ~/Library/Logs/Omnikeys.log; fi
BEFORE=$(osascript -e 'tell application "TextEdit" to get text of front document')
osascript -e 'tell application "System Events" to key code 48'   # Tab = next word
sleep 1
osascript -e 'tell application "System Events" to key code 50'   # ` = accept all
sleep 1.5
AFTER=$(osascript -e 'tell application "TextEdit" to get text of front document')
echo "before: $BEFORE"; echo "after:  $AFTER"
[ ${#AFTER} -gt ${#BEFORE} ] && echo "PASS text inserted via Tab/backtick" || echo "FAIL nothing inserted"
osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1 || true
