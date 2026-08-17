#!/bin/sh
set -eu

# A Render Web Service needs an HTTP listener. Keep it separate from the
# upstream client command so we do not alter how APPLICATION_KEY is consumed.
/usr/local/bin/otohit-health &
health_pid=$!

shutdown() {
  kill "$health_pid" 2>/dev/null || true
  wait "$health_pid" 2>/dev/null || true
}
trap shutdown INT TERM EXIT

# "$@" is the original CMD inherited from otohits/app:latest.
# exec keeps the client as PID 1 and gives it normal stop/restart semantics.
exec "$@"
