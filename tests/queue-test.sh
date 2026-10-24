#!/bin/bash
# Integration tests for whisper-toggle's queue, language argument and server
# lifecycle. Uses stubs for rec, whisper-server, clipboard and paste, so it
# needs no microphone, model or desktop session. Run: tests/queue-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${WHISPER_TOGGLE_UNDER_TEST:-$HERE/../bin/whisper-toggle}"
T="$(mktemp -d)"
PORT=$((20000 + RANDOM % 20000))
FAILS=0
trap 'pkill -f "$T/bin/whisper-server" 2>/dev/null; pkill -P $$ 2>/dev/null; rm -rf "$T"' EXIT

mkdir -p "$T/bin" "$T/config/whisper-toggle" "$T/state" "$T/shm" "$T/box"

# --- stubs -------------------------------------------------------------
cat > "$T/bin/rec" <<'S'
#!/bin/bash
# "records" until TERM; the file content identifies the recording
n=$(( $(cat "$STUB_DIR/rec-count" 2>/dev/null || echo 0) + 1 )); echo $n > "$STUB_DIR/rec-count"
echo "$(date +%s.%N) rec-start id=$n" >> "$STUB_DIR/rec-events"
echo "REC-$n" > "$4"
trap 'echo "$(date +%s.%N) rec-stop id=$n" >> "$STUB_DIR/rec-events"; exit 0' TERM
for _ in $(seq 1 400); do sleep 0.05; done
S
cat > "$T/bin/notify-send" <<'S'
#!/bin/bash
echo "$*" >> "$STUB_DIR/notify.log"
S
cat > "$T/bin/wl-copy" <<'S'
#!/bin/bash
[[ "$1" == --primary ]] && exit 0
printf '%s' "$1" > "$STUB_DIR/clipboard"
S
cat > "$T/bin/ydotool" <<'S'
#!/bin/bash
echo "$(date +%s.%N) $(cat "$STUB_DIR/clipboard")" >> "$STUB_DIR/pastes"
S
cp "$HERE/stub-whisper-server.py" "$T/bin/whisper-server"
chmod +x "$T/bin/"*

cat > "$T/config/whisper-toggle/whisper-toggle.conf" <<C
BACKEND="server"
WHISPER_SERVER="$T/bin/whisper-server"
WHISPER_MODEL="$T/model.bin"
WHISPER_PORT=$PORT
WHISPER_LANGUAGE="auto"
WHISPER_SERVER_IDLE=3
AUTOPASTE=1
C

export STUB_DIR="$T/box" XDG_SESSION_TYPE=wayland XDG_CONFIG_HOME="$T/config" \
       WHISPER_TOGGLE_STATE_DIR="$T/state" WHISPER_TOGGLE_LOG="$T/log" \
       WHISPER_TOGGLE_AUDIO_DIR="$T/shm" PATH="$T/bin:$PATH"

press() { "$SCRIPT" "$@" & }
now() { date +%s.%N; }
check() { # description, condition command...
    local d="$1"; shift
    if "$@"; then echo "  ok   $d"; else echo "  FAIL $d"; FAILS=$((FAILS+1)); fi
}
reset() {
    pkill -f "$T/bin/whisper-server" 2>/dev/null
    for _ in $(seq 1 20); do pgrep -f "$T/bin/whisper-server" >/dev/null || break; sleep 0.1; done
    rm -rf "$T/box"/* "$T/state"/* "$T/shm"/*; : > "$T/log"
}
pastes() { awk '{print $2}' "$T/box/pastes" 2>/dev/null | paste -sd' '; }
server_pid() { sed -n 1p "$T/state/server.pid" 2>/dev/null | cut -d' ' -f1; }

# =====================================================================
echo "== 1. three overlapping recordings, later ones finish first =="
reset
export STUB_DELAYS="1:6,2:3,3:0.2" STUB_SERVER_START=2
t0=$(now)
press de;  sleep 0.8     # recording 1 (de)
press en;  sleep 0.8     # stop 1 -- argument of the stop press must be ignored
press en;  sleep 0.8     # recording 2 (en) starts while 1 is transcribing
press;     sleep 0.8     # stop 2
press fr;  sleep 0.8     # recording 3 (fr) starts while 1 and 2 are transcribing
press;                   # stop 3
sleep 1; echo "  tickets while queue is backed up: $(ls "$T/state/tickets" | wc -l)"
wait_start=$(now)
for _ in $(seq 1 200); do [[ $(cat "$T/box/pastes" 2>/dev/null | wc -l) -ge 3 ]] && break; sleep 0.1; done
echo "  transcription finished (server-done):"; sed 's/^/    /' "$T/box/server-done"
echo "  pastes in order:";                      sed 's/^/    /' "$T/box/pastes"
check "paste order is recording order"      [ "$(pastes)" = "Text-1-de Text-2-en Text-3-fr" ]
check "stop press argument was ignored (rec 1 stays de)" grep -q 'id=1 lang=de' "$T/box/server-requests"
check "recording 3 finished transcribing before recording 1" \
      bash -c "[[ \$(grep -n 'id=3' '$T/box/server-done' | cut -d: -f1) -lt \$(grep -n 'id=1' '$T/box/server-done' | cut -d: -f1) ]]"
check "exactly one whisper-server was started" [ "$(wc -l < "$T/box/server-starts")" = 1 ]
check "recording 2 started while 1 was still transcribing" \
      bash -c "[[ \$(grep 'rec-start id=2' '$T/box/rec-events' | cut -d' ' -f1) < \$(grep 'id=1' '$T/box/server-done' | cut -d' ' -f1) ]]"
sleep 1.5
check "tickets and audio files cleaned up" bash -c "[ -z \"\$(ls '$T/state/tickets')\" ] && [ -z \"\$(ls '$T/shm')\" ]"
check "server still running right after the last run" kill -0 "$(server_pid)"
spid="$(server_pid)"
sleep 5
check "server stopped after WHISPER_SERVER_IDLE (3s)" bash -c "! kill -0 $spid 2>/dev/null && [ ! -f '$T/state/server.pid' ]"
check "server was not stopped while a run (6s > idle 3s) was in flight" [ "$(pastes | wc -w)" = 3 ]
wait

# =====================================================================
echo "== 2. recording is not delayed by a still-starting server =="
reset
export STUB_DELAYS="1:0.1" STUB_SERVER_START=3
tp=$(now); press de; sleep 1; press; 
for _ in $(seq 1 100); do [[ -s "$T/box/pastes" ]] && break; sleep 0.1; done
rs=$(grep rec-start "$T/box/rec-events" | cut -d' ' -f1)
echo "  press -> rec started after $(echo "$rs - $tp" | bc) s; server needs 3s to load"
check "recorder started < 0.5s after the key press" bash -c "(( \$(echo \"($rs - $tp) < 0.5\" | bc) ))"
check "transcription waited for the server instead of failing" [ "$(pastes)" = "Text-1-de" ]
wait

# =====================================================================
echo "== 3. killed run (SIGKILL) does not block the queue =="
reset
export STUB_DELAYS="1:30,2:0.2" STUB_SERVER_START=0
press de; sleep 0.8; press; sleep 0.8        # run 1: now transcribing (30s)
press en; sleep 0.8; press; sleep 1          # run 2 recorded, transcribed, waiting for ticket 1
check "run 2 is held back by ticket 1" [ ! -s "$T/box/pastes" ]
victim=$(cut -d' ' -f1 "$T/state/tickets/$(ls "$T/state/tickets" | head -1)")
kill -9 "$victim"
for _ in $(seq 1 50); do [[ -s "$T/box/pastes" ]] && break; sleep 0.1; done
echo "  pastes: $(pastes)"
check "after SIGKILL of run 1, run 2 pastes" [ "$(pastes)" = "Text-2-en" ]
check "dead ticket logged and removed" bash -c "grep -q 'Dropped dead ticket #1' '$T/log'"
wait 2>/dev/null

# =====================================================================
echo "== 4. orphaned recorder of a killed run is not mistaken for 'stop' =="
reset
export STUB_DELAYS="" STUB_SERVER_START=0
press de; sleep 1
victim=$(cut -d' ' -f1 "$T/state/tickets/$(ls "$T/state/tickets" | head -1)")
kill -9 "$victim"; sleep 0.7
press en; sleep 1; press
for _ in $(seq 1 50); do [[ -s "$T/box/pastes" ]] && break; sleep 0.1; done
check "new recording started instead of stopping the orphan, and was transcribed" [ "$(pastes)" = "Text-2-en" ]
wait 2>/dev/null

# =====================================================================
echo "== 5. no pkill / kill by name or port in the script =="
check "script contains no pkill/killall" bash -c "! grep -nE '(^|[^a-z_])(pkill|killall|fuser)' '$SCRIPT'"

echo
if (( FAILS )); then echo "$FAILS check(s) FAILED"; exit 1; fi
echo "all checks passed"
