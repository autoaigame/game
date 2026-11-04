#!/usr/bin/env bash
# Headless smoke test: server + clients over WebSocket.
# join, move, duplicate name refused, abrupt disconnect, reconnect at the saved position.
set -uo pipefail
GODOT="${GODOT:-godot}"
PORT="${SMOKE_PORT:-19000}"
URL="ws://127.0.0.1:$PORT"
TMP="$(mktemp -d)"
RUN=("$GODOT" --headless --path .)
pids=()
cleanup() { for p in "${pids[@]}"; do kill -9 "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
fail() { echo "SMOKE FAIL: $*"; for f in "$TMP"/*.log; do echo "--- $f"; tail -n 15 "$f"; done; exit 1; }
client() { "${RUN[@]}" -s res://tools/smoke_client.gd -- --url "$URL" "$@"; }
# Background variant: exec so that $! is Godot's own PID (kill -9 must hit the client).
bg_client() { exec "${RUN[@]}" -s res://tools/smoke_client.gd -- --url "$URL" "$@"; }

( exec "${RUN[@]}" -- --server --port "$PORT" --db "$TMP/game.db" ) >"$TMP/server.log" 2>&1 &
pids+=($!)
for _ in $(seq 1 50); do (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && break; sleep 0.2; done
(exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null || fail "server did not listen on $PORT"

bg_client --name ann --move 18,16 --hold 60 >"$TMP/a.log" 2>&1 &
apid=$!; pids+=($apid)
for _ in $(seq 1 75); do grep -q "^REACHED" "$TMP/a.log" && break; sleep 0.2; done
grep -q "^REACHED" "$TMP/a.log" || fail "ann did not reach 18,16"
echo "ok   ann joined and moved"

client --name ann --expect-rejected >"$TMP/b.log" 2>&1 || fail "second 'ann' was not rejected"
echo "ok   duplicate name rejected"

kill -9 "$apid"
client --name carl --expect-absent ann >"$TMP/c.log" 2>&1 || fail "ann still visible after disconnect"
echo "ok   abrupt disconnect removed ann"

client --name ann --expect-welcome 18,16 >"$TMP/d.log" 2>&1 || fail "ann did not come back at 18,16"
echo "ok   ann restored at saved position"
echo "SMOKE PASS"
