#!/bin/sh
# Entrypoint wrapper for the Render deployment.
#
# Render Web Services require a process bound to $PORT, so we start the small
# health listener alongside the OtoHits client.
#
# IMPORTANT: this script replaces the upstream image's ENTRYPOINT (see the
# Dockerfile). Only the upstream CMD survives as "$@". The official image is
# normally started as `docker run -e APPLICATION_KEY=... otohits/app:latest`
# with no command, i.e. its launcher lives in ENTRYPOINT and CMD is empty.
# Therefore "exec $@" alone would exec NOTHING and the container would exit
# immediately ("Application exited early" on Render). When no command is
# inherited, we locate and launch the client binary ourselves.
set -u

log() {
  printf '[docker-entrypoint-web] %s\n' "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

# --- 1. Start the HTTP listener required by Render -------------------------
log "starting health listener on port ${PORT:-10000}"
/usr/local/bin/otohit-health &
health_pid=$!

shutdown() {
  kill "$health_pid" 2>/dev/null || true
  wait "$health_pid" 2>/dev/null || true
}
trap shutdown INT TERM EXIT

# --- 2. Sanity-check the environment ----------------------------------------
if [ -z "${APPLICATION_KEY:-}" ]; then
  log "WARNING: APPLICATION_KEY is not set. The OtoHits client will exit"
  log "immediately without it. In the Render dashboard go to your service ->"
  log "Environment, add APPLICATION_KEY, then redeploy."
fi

# --- 3. Launch the client ----------------------------------------------------
if [ "$#" -gt 0 ]; then
  # A command was inherited (upstream CMD or a Docker Command override on
  # Render). Preserve it exactly; exec keeps the client as PID 1.
  log "launching inherited command: $*"
  exec "$@"
fi

log "no command was inherited from the base image (its ENTRYPOINT was replaced);"
log "locating the OtoHits client binary in the image..."

# Known install locations of the client (the Linux app ships as 'otohits-app').
app=""
for candidate in \
  /otohits-app \
  /app/otohits-app \
  /opt/otohits/otohits-app \
  /usr/local/bin/otohits-app \
  /OtohitsApp/OtohitsApp
do
  if [ -f "$candidate" ]; then
    app="$candidate"
    break
  fi
done

# Fallback: search the image for an executable-looking client binary.
if [ -z "$app" ]; then
  app=$(find / -xdev \
      \( -path /proc -o -path /sys -o -path /dev -o -path /usr/local/bin \) -prune \
      -o -type f \( -name 'otohits-app' -o -name 'OtohitsApp' \) -print \
      2>/dev/null | head -n 1)
fi
if [ -z "$app" ]; then
  app=$(find / -xdev \
      \( -path /proc -o -path /sys -o -path /dev -o -path /usr/local/bin \) -prune \
      -o -type f -name '*otohit*' -print \
      2>/dev/null | grep -v -e 'otohit-health' -e 'docker-entrypoint' | head -n 1)
fi

[ -n "$app" ] || die "could not find the OtoHits client binary inside the image. Set a Docker Command override in Render or inspect the base image: docker image inspect otohits/app:latest --format '{{json .Config}}'"

chmod +x "$app" 2>/dev/null || true
app_dir=$(dirname "$app")
log "launching OtoHits client: $app (working directory: $app_dir)"
cd "$app_dir" || die "cannot enter $app_dir"
exec "$app"
