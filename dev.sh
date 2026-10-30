#!/bin/bash
# Background-first, matching the runner in synesthetic.systems.
# Sutra contract: https://github.com/synestheticsystems/sutra/blob/main/docs/INTEGRATION.md
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
REGISTRY_DIR="${DEV_RUNNER_REGISTRY:-$HOME/.dev-runner}"
LOG_FILE="$SCRIPT_DIR/.dev-log"
PORTS_FILE="$SCRIPT_DIR/.dev-ports"
mkdir -p "$REGISTRY_DIR"
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }
REGISTRY_KEY="$(printf '%s' "$SCRIPT_DIR" | sha256 | cut -c1-16)"
if [ ${#REGISTRY_KEY} -lt 8 ] || [[ "$REGISTRY_KEY" == *[!0-9a-f]* ]]; then
    echo 'fatal: invalid registry key' >&2; exit 1
fi
REGISTRY_FILE="$REGISTRY_DIR/$REGISTRY_KEY"
STATUS_FILE="$REGISTRY_FILE.web.status"
LOCK_DIR="$SCRIPT_DIR/.dev-start-lock"
get_value() { awk -F= -v key="$2" '$1 == key { print substr($0, length(key) + 2); exit }' "$1" 2>/dev/null || true; }
update_status() {
    printf '%s\n' "$1" > "$STATUS_FILE.tmp.$$"
    mv -f "$STATUS_FILE.tmp.$$" "$STATUS_FILE"
}
clear_status() {
    [ ${#REGISTRY_KEY} -ge 8 ] || return 1
    rm -f "$REGISTRY_FILE" "$STATUS_FILE" "$STATUS_FILE".tmp.*
}
check_running() {
    local pid pgid command
    pid="$(get_value "$REGISTRY_FILE" PID)"
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    [ "$(get_value "$REGISTRY_FILE" DIR)" = "$SCRIPT_DIR" ] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    [ "$pgid" = "$pid" ] || return 1
    command="$(ps -o command= -p "$pid" 2>/dev/null || true)"
    case "$command" in *"$SCRIPT_DIR/dev.sh --supervise "*) return 0 ;; *) return 1 ;; esac
}
reap_stale_instance() {
    # Like the existing runners, recover children after a supervisor was killed.
    # Only signal the recorded group when one of this checkout's units is in it.
    local pid member command owned=false
    [ "$(get_value "$REGISTRY_FILE" DIR)" = "$SCRIPT_DIR" ] || return 0
    pid="$(get_value "$REGISTRY_FILE" PID)"
    case "$pid" in ''|*[!0-9]*) return 0 ;; esac
    [ "$pid" -gt 1 ] || return 0
    for member in $(ps -A -o pgid=,pid= | awk -v group="$pid" '$1 == group {print $2}'); do
        command="$(ps -o command= -p "$member" 2>/dev/null || true)"
        case "$command" in *" -m http.server "*" --directory $SCRIPT_DIR/dist") owned=true ;; esac
    done
    if [ "$owned" = true ]; then
        echo "Recovering the previous runner's process group $pid"
        kill -TERM -- -"$pid" 2>/dev/null || true
        for _ in $(seq 1 50); do
            kill -0 -- -"$pid" 2>/dev/null || return 0
            sleep 0.1
        done
        echo "Old process group $pid did not stop; inspect it before restarting." >&2
        return 1
    fi
}
port_available() {
    ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}
select_port() {
    WEB_PORT="${PORT:-$(get_value "$PORTS_FILE" WEB_PORT)}"
    case "$WEB_PORT" in ''|*[!0-9]*) WEB_PORT='' ;; esac
    if [ -n "$WEB_PORT" ]; then
        if [ "$WEB_PORT" -lt 1024 ] || [ "$WEB_PORT" -gt 65535 ]; then
            echo 'PORT must be between 1024 and 65535' >&2; exit 1
        fi
        if ! port_available "$WEB_PORT"; then
            if [ -n "${PORT:-}" ]; then echo "Port $PORT is occupied" >&2; exit 1; fi
            WEB_PORT=''
        fi
    fi
    if [ -n "${PORT:-}" ] && [ -z "$WEB_PORT" ]; then echo 'Invalid PORT' >&2; exit 1; fi
    for _ in $(seq 1 50); do
        [ -n "$WEB_PORT" ] && break
        candidate=$((10000 + RANDOM % 10000))
        if port_available "$candidate"; then WEB_PORT="$candidate"; fi
    done
    [ -n "$WEB_PORT" ] || { echo 'No available port' >&2; exit 1; }
    printf 'WEB_PORT=%s\n' "$WEB_PORT" > "$PORTS_FILE"
}
show_status() {
    if check_running; then
        echo "$(cat "$STATUS_FILE" 2>/dev/null || echo starting) - http://127.0.0.1:$(get_value "$REGISTRY_FILE" WEB_PORT)/"
        echo "PID $(get_value "$REGISTRY_FILE" PID) - Log: $LOG_FILE"
    else echo 'Stopped'; return 1; fi
}
stop() {
    if check_running; then
        local pid
        pid="$(get_value "$REGISTRY_FILE" PID)"
        kill -TERM "$pid"
        for _ in $(seq 1 100); do
            check_running || break
            sleep 0.05
        done
        if check_running; then echo "Shutdown timed out; inspect $LOG_FILE" >&2; return 1; fi
    else
        reap_stale_instance
    fi
    clear_status
    echo 'Stopped'
}

if [ "${1:-}" = '--supervise' ]; then
    WEB_PORT="$2"
    cd "$SCRIPT_DIR"
    pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
    [ "$pgid" = "$$" ] || { echo 'Supervisor must lead its process group' >&2; exit 1; }
    cleanup() {
        trap - EXIT INT HUP
        trap '' TERM
        # Reap the readiness probe and static server in this owned group.
        kill -TERM -- -"$$" 2>/dev/null || true
        wait 2>/dev/null || true
        clear_status
        exit "${1:-0}"
    }
    trap 'cleanup 0' INT TERM HUP
    trap 'cleanup $?' EXIT
    clear_status
    cat > "$REGISTRY_FILE.tmp.$$" <<META
DIR=$SCRIPT_DIR
PID=$$
STARTED=$(date +%s)
WEB_PORT=$WEB_PORT
META
    mv -f "$REGISTRY_FILE.tmp.$$" "$REGISTRY_FILE"
    update_status starting
    python3 -u -m http.server "$WEB_PORT" --bind 127.0.0.1 --directory "$SCRIPT_DIR/dist" &
    web_pid=$!
    (
        for _ in $(seq 1 60); do
            kill -0 "$web_pid" 2>/dev/null || exit 0
            if curl -fsS --max-time 1 "http://127.0.0.1:$WEB_PORT/" >/dev/null 2>&1; then
                update_status ready; exit 0
            fi
            sleep 0.25
        done
        update_status 'failed: readiness timeout'
    ) &
    ready_pid=$!
    web_rc=0
    wait "$web_pid" || web_rc=$?
    kill "$ready_pid" 2>/dev/null || true
    wait "$ready_pid" 2>/dev/null || true
    update_status "failed: web exited with status $web_rc"
    # Preserve a visible failure for Sutra until stopped or restarted.
    while :; do sleep 30 & wait $! || true; done
fi

case "${1:-}" in
    --stop) stop; exit ;;
    --restart) stop ;;
    --status) show_status; exit ;;
    --logs) touch "$LOG_FILE"; exec tail -n 60 -f "$LOG_FILE" ;;
    --help) echo 'Usage: ./dev.sh [--start|--stop|--restart|--status|--logs|--help]'; echo 'Local static server; Python 3 and curl required. Ports are random and sticky; PORT=12345 overrides.'; exit ;;
    ''|--start) ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
esac
if check_running; then show_status; exit; fi
command -v python3 >/dev/null || { echo 'Python 3 is required.' >&2; exit 1; }
command -v curl >/dev/null || { echo 'curl is required.' >&2; exit 1; }
[ -f "$SCRIPT_DIR/dist/index.html" ] || { echo 'Missing dist/index.html.' >&2; exit 1; }
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Another launch is in progress. If interrupted, remove $LOCK_DIR." >&2; exit 1
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
reap_stale_instance
select_port
clear_status
# A fresh bash (not a subshell) gives the supervisor a correct $$ on macOS bash 3.2.
set -m
nohup /bin/bash "$SCRIPT_DIR/dev.sh" --supervise "$WEB_PORT" > "$LOG_FILE" 2>&1 < /dev/null &
launched_pid=$!
disown "$launched_pid"
set +m
for _ in $(seq 1 100); do
    if ! kill -0 "$launched_pid" 2>/dev/null; then echo "Startup failed: $LOG_FILE" >&2; exit 1; fi
    state="$(cat "$STATUS_FILE" 2>/dev/null || true)"
    case "$state" in
        ready) show_status; exit 0 ;;
        failed*) echo "$state; see $LOG_FILE" >&2; exit 1 ;;
    esac
    sleep 0.15
done
echo "Startup timed out; see $LOG_FILE" >&2
exit 1
