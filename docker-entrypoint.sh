#!/bin/sh
# Entrypoint wrapper for the Render deployment.
#
# Render Web Services require a process bound to $PORT, so this wrapper starts
# the small health listener alongside the OtoHits client. OtoHits also needs a
# virtual X display: otohits-app controls otohits-viewer, a CEF/Chromium process
# that cannot start without one even though no window is shown.
set -u

log() {
  printf '[docker-entrypoint-web] %s\n' "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

health_pid=""
xvfb_pid=""
client_pid=""
xvfb_log="/tmp/otohits-xvfb.log"

pid_is_running() {
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

stop_process() {
  process_name=$1
  process_pid=$2

  if pid_is_running "$process_pid"; then
    log "stopping $process_name (pid $process_pid)"
    kill "$process_pid" 2>/dev/null || true
    wait "$process_pid" 2>/dev/null || true
  fi
}

cleanup() {
  # Do not recursively run this handler when the shell exits after cleanup.
  trap - EXIT
  stop_process "OtoHits client" "$client_pid"
  stop_process "virtual display" "$xvfb_pid"
  stop_process "health listener" "$health_pid"
}

forward_signal() {
  signal=$1
  log "received $signal; forwarding it to the OtoHits client"
  if pid_is_running "$client_pid"; then
    kill -"$signal" "$client_pid" 2>/dev/null || true
  fi
}

trap cleanup EXIT
trap 'forward_signal TERM' TERM
trap 'forward_signal INT' INT

# --- 1. Start the HTTP listener required by Render -------------------------
log "starting health listener on port ${PORT:-10000}"
/usr/local/bin/otohit-health &
health_pid=$!

# --- 2. Prepare the client environment -------------------------------------
if [ -z "${APPLICATION_KEY:-}" ]; then
  log "WARNING: APPLICATION_KEY is not set. The OtoHits client will exit"
  log "immediately without it. In the Render dashboard go to your service ->"
  log "Environment, add APPLICATION_KEY, then redeploy."
fi

# The client looks for its settings in $HOME/.local/share; the upstream image
# does not ship the directory, which produces a startup warning.
mkdir -p "${HOME:-/root}/.local/share" 2>/dev/null || true

# Write the same essential options used by the official Docker launcher.
# /nosandbox is required because the Chromium viewer runs inside a container.
# Without it the app starts, but the viewer repeatedly fails to answer and the
# app prints "Unable to receive response from the viewer in time".
write_ini() {
  ini_dir=$1
  ini_file="$ini_dir/otohits.ini"
  ini_tmp="$ini_dir/.otohits.ini.$$"

  if [ ! -d "$ini_dir" ]; then
    log "WARNING: cannot write OtoHits settings: $ini_dir is not a directory"
    return 0
  fi

  old_umask=$(umask)
  umask 077
  if ! {
    if [ -n "${APPLICATION_KEY:-}" ]; then
      printf '/login:%s\n' "$APPLICATION_KEY"
    fi
    printf '/nosandbox\n'
    # Recommended for servers/VPS: pick up new versions while running.
    printf '/autoupdate\n'
  } > "$ini_tmp" 2>/dev/null; then
    umask "$old_umask"
    rm -f "$ini_tmp" 2>/dev/null || true
    log "WARNING: could not write $ini_file"
    return 0
  fi

  if ! mv -f "$ini_tmp" "$ini_file" 2>/dev/null; then
    umask "$old_umask"
    rm -f "$ini_tmp" 2>/dev/null || true
    log "WARNING: could not install $ini_file"
    return 0
  fi
  umask "$old_umask"
  log "wrote otohits.ini (login if configured + nosandbox + autoupdate) to $ini_dir"
}

# Start the virtual X server required by the CEF-based otohits-viewer. The
# upstream image includes Xvfb, and its original launcher used display :51.
start_virtual_display() {
  DISPLAY=${DISPLAY:-:51}
  export DISPLAY

  # A non-local DISPLAY was intentionally supplied by the operator. Leave it
  # alone instead of trying to derive a local X11 socket path from it.
  case "$DISPLAY" in
    :*) ;;
    *)
      log "using externally configured X display $DISPLAY"
      return 0
      ;;
  esac

  display_number=${DISPLAY#:}
  display_number=${display_number%%.*}
  case "$display_number" in
    ''|*[!0-9]*) die "DISPLAY must look like :51 or :51.0 (received: $DISPLAY)" ;;
  esac

  display_socket="/tmp/.X11-unix/X$display_number"
  if [ -S "$display_socket" ]; then
    log "using existing virtual display $DISPLAY"
    return 0
  fi

  command -v Xvfb >/dev/null 2>&1 || die "Xvfb is not installed in the upstream image; otohits-viewer cannot run without a virtual X display"

  rm -f "$xvfb_log"
  log "starting virtual display $DISPLAY"
  Xvfb "$DISPLAY" \
    -screen 0 "${OTOHITS_SCREEN:-1280x720x24}" \
    -nolisten tcp \
    >"$xvfb_log" 2>&1 &
  xvfb_pid=$!

  # Do not race Chromium against Xvfb startup. Allow up to ten seconds on a
  # cold/CPU-constrained Render instance.
  attempt=0
  while [ ! -S "$display_socket" ]; do
    if ! pid_is_running "$xvfb_pid"; then
      log "Xvfb exited before display $DISPLAY became ready"
      if [ -s "$xvfb_log" ]; then
        sed 's/^/[xvfb] /' "$xvfb_log"
      fi
      die "could not start the virtual display required by otohits-viewer"
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 10 ]; then
      die "timed out waiting for virtual display $DISPLAY"
    fi
    sleep 1
  done
  log "virtual display $DISPLAY is ready"
}

# --- 3. Resolve and launch the client ---------------------------------------
if [ "$#" -gt 0 ]; then
  # A command was inherited (upstream CMD or a Docker Command override on
  # Render). Preserve it exactly. Keep this shell as PID 1 so it can supervise
  # and clean up the health listener and Xvfb.
  write_ini "$(pwd)"
  start_virtual_display
  log "launching inherited command: $*"
  "$@" &
  client_pid=$!
else
  log "no command was inherited from the base image (its ENTRYPOINT was replaced);"
  log "locating the OtoHits client binary in the image..."

  # Known install locations of the client (the Linux app ships as
  # 'otohits-app'). /otohits/otohits-app is used by otohits/app:latest today.
  app=""
  for candidate in \
    /otohits/otohits-app \
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
  write_ini "$app_dir"
  start_virtual_display
  log "launching OtoHits client: $app (working directory: $app_dir)"
  cd "$app_dir" || die "cannot enter $app_dir"
  "$app" &
  client_pid=$!
fi

# wait can be interrupted by a trapped signal before the child has actually
# exited. Keep waiting in that case so cleanup never leaves the client behind.
client_status=1
while :; do
  wait "$client_pid"
  client_status=$?
  if ! pid_is_running "$client_pid"; then
    break
  fi
done
client_pid=""
log "OtoHits client exited with status $client_status"
exit "$client_status"
