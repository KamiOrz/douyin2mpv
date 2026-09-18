#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x Douyin2MPV >/dev/null 2>&1 || true
./scripts/build-app.sh
case "${1:-run}" in
 run) open -n dist/Douyin2MPV.app ;;
 --verify) open -n dist/Douyin2MPV.app; sleep 1; pgrep -x Douyin2MPV ;;
 --debug) open -n dist/Douyin2MPV.app; sleep 1; lldb -n Douyin2MPV ;;
 --logs|--telemetry) open -n dist/Douyin2MPV.app; /usr/bin/log stream --info --style compact --predicate 'process == "Douyin2MPV"' ;;
 *) echo 'usage: build_and_run.sh [--verify|--debug|--logs|--telemetry]' >&2; exit 2 ;;
esac
