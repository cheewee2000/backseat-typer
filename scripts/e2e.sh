#!/bin/bash
# End-to-end loop: build, self-test, run the binary from this (Accessibility-trusted) terminal,
# type into TextEdit, expect a ghost suggestion, press Tab, expect the document to grow.
set -e
cd "$(dirname "$0")/.."
./build.sh | tail -1
BIN="$HOME/Applications/BackseatTyper.app/Contents/MacOS/BackseatTyper"
"$BIN" --selftest | tail -1
pkill -x BackseatTyper 2>/dev/null || true; sleep 0.5
: > ~/Library/Logs/BackseatTyper.log
# open, not exec: TCC attributes a shell-exec to the untrusted shell host. --e2e enables the backseattyper:// driver,
# because System Events keystrokes from this shell are refused for the same reason.
open "$HOME/Applications/BackseatTyper.app" --args --e2e
sleep 3
grep -q "tap started" ~/Library/Logs/BackseatTyper.log && echo "PASS tap started" || { echo "FAIL tap not started (Accessibility?)"; grep launch ~/Library/Logs/BackseatTyper.log; exit 1; }
osascript <<'AS'
tell application "TextEdit"
  activate
  make new document
end tell
AS
sleep 1
open -g "backseattyper://type?text=Dear%20Taylor%2C%20thanks%20for%20sending%20the%20drawings%20over.%20I%20had%20a%20look%20at%20the"
sleep 5
if grep -q "SHOW completion" ~/Library/Logs/BackseatTyper.log; then echo "PASS suggestion shown: $(grep "SHOW completion" ~/Library/Logs/BackseatTyper.log | tail -1 | cut -c25-)"; else echo "FAIL no suggestion"; tail -5 ~/Library/Logs/BackseatTyper.log; fi
BEFORE=$(osascript -e 'tell application "TextEdit" to get text of front document')
open -g "backseattyper://key?code=48"   # Tab = next word
sleep 1
open -g "backseattyper://key?code=50"   # ` = accept all
sleep 1.5
AFTER=$(osascript -e 'tell application "TextEdit" to get text of front document')
echo "before: $BEFORE"; echo "after:  $AFTER"
[ ${#AFTER} -gt ${#BEFORE} ] && echo "PASS text inserted via Tab/backtick" || echo "FAIL nothing inserted"
osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1 || true

# loop 2: typo autocorrect (Tab on "teh" -> "the") and emoji shortcode (Tab on ":smile" -> emoji)
osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document' >/dev/null
sleep 1
open -g "backseattyper://type?text=I%20think%20teh%20"; sleep 2   # typo check waits for a word boundary
open -g "backseattyper://key?code=48"; sleep 1
T=$(osascript -e 'tell application "TextEdit" to get text of front document')
[[ "$T" == *"I think the "* ]] && echo "PASS typo fixed: $T" || echo "FAIL typo: $T"
open -g "backseattyper://type?text=%20%3Asmile"; sleep 2
open -g "backseattyper://key?code=48"; sleep 1
T=$(osascript -e 'tell application "TextEdit" to get text of front document')
[[ "$T" == *"😄"* ]] && echo "PASS emoji inserted: $T" || echo "FAIL emoji: $T"
# loop 3: Esc dismisses the ghost text
open -g "backseattyper://type?text=%20and%20then%20we%20went%20to"; sleep 4
open -g "backseattyper://key?code=53"; sleep 0.5
B=$(osascript -e 'tell application "TextEdit" to get text of front document')
open -g "backseattyper://key?code=48"; sleep 1
A=$(osascript -e 'tell application "TextEdit" to get text of front document')
[ ${#A} -eq $((${#B}+1)) ] && echo "PASS esc dismissed, Tab passed through" || echo "FAIL esc: '$B' -> '$A'"
osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1 || true
