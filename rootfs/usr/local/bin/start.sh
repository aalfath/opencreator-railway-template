#!/bin/sh
# Start script for OpenCreator (KrillinAI Server) on Railway.
# - writes ./config/config.toml on the volume from Railway variables
# - runs the KrillinAI server on 127.0.0.1:8888 (it has no login of its own)
# - runs Caddy on $PORT with HTTP basic auth and an open /healthz
# - exits non-zero as soon as either process stops, so Railway restarts it
set -eu

DATA_DIR="${DATA_DIR:-/data}"
PORT="${PORT:-8080}"
ADMIN_USER="${ADMIN_USER:-admin}"

log() { echo "[start] $*"; }
die() { echo "[start] ERROR: $*" >&2; exit 1; }

[ -n "${ADMIN_PASSWORD:-}" ] || die "ADMIN_PASSWORD is empty. Set it in the service variables."
[ "${#ADMIN_PASSWORD}" -ge 12 ] || die "ADMIN_PASSWORD must be at least 12 characters."
[ -n "${OPENAI_API_KEY:-}" ] || die "OPENAI_API_KEY is empty. Add your OpenAI (or OpenAI-compatible) API key in the service variables."

LLM_BASE_URL="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
LLM_MODEL="${LLM_MODEL:-gpt-4o-mini}"
TRANSCRIBE_BASE_URL="${TRANSCRIBE_BASE_URL:-$LLM_BASE_URL}"
TRANSCRIBE_API_KEY="${TRANSCRIBE_API_KEY:-$OPENAI_API_KEY}"
TRANSCRIBE_MODEL="${TRANSCRIBE_MODEL:-whisper-1}"
TTS_BASE_URL="${TTS_BASE_URL:-$LLM_BASE_URL}"
TTS_API_KEY="${TTS_API_KEY:-$OPENAI_API_KEY}"
TTS_MODEL="${TTS_MODEL:-gpt-4o-mini-tts}"

mkdir -p "$DATA_DIR/config" "$DATA_DIR/tasks" "$DATA_DIR/uploads" "$DATA_DIR/bin" "$DATA_DIR/.config" "$DATA_DIR/.local/share"
cd "$DATA_DIR"

# A Railway volume can be mounted over files from the image, so copy the
# default subtitle style in on every boot if it's missing.
[ -f config/subtitle-style-default.json ] || cp /opt/krillinai/config/subtitle-style-default.json config/

# The upstream log file only ever grows; keep the last 5 MB across restarts.
if [ -f app.log ] && [ "$(wc -c < app.log)" -gt 20971520 ]; then
  tail -c 5242880 app.log > app.log.tmp && mv app.log.tmp app.log
fi

toml_str() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }

CONF=config/config.toml
if [ ! -s "$CONF" ]; then
  log "first boot: writing $DATA_DIR/$CONF"
  cat > "$CONF.tmp" <<TOML
[app]
  segment_duration = 5
  transcribe_parallel_num = 1
  translate_parallel_num = ${TRANSLATE_PARALLEL_NUM:-2}
  transcribe_max_attempts = 3
  translate_max_attempts = 5
  max_sentence_length = 60
  target_language_first = true
  short_subtitle_max_chars = 20
  proxy = ""

[server]
  host = "127.0.0.1"
  port = 8888

[llm]
  base_url = ""
  api_key = ""
  model = ""
  json = false

[transcribe]
  provider = "openai"
  enable_gpu_acceleration = false
  [transcribe.openai]
    base_url = ""
    api_key = ""
    model = ""

[tts]
  provider = "openai"
  [tts.openai]
    base_url = ""
    api_key = ""
    model = ""
TOML
  mv "$CONF.tmp" "$CONF"
fi

# Railway variables always win for the server address and the OpenAI-compatible
# keys, so a key changed in Railway takes effect on the next restart. Everything
# else (providers, languages, parallelism) keeps what you saved in the web UI.
set_key() { # section key toml-value
  awk -v sec="$1" -v key="$2" -v val="$3" '
    function flush() { if (cur == sec && !done) { print "  " key " = " val; done = 1 } }
    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      flush()
      s = $0; gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", s); cur = s
      if (cur == sec) seen = 1
      print; next
    }
    cur == sec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { if (!done) { print "  " key " = " val; done = 1 }; next }
    { print }
    END { flush(); if (!seen) { print ""; print "[" sec "]"; print "  " key " = " val } }
  ' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
}
set_key server host '"127.0.0.1"'
set_key server port 8888
set_key llm base_url "$(toml_str "$LLM_BASE_URL")"
set_key llm api_key "$(toml_str "$OPENAI_API_KEY")"
set_key llm model "$(toml_str "$LLM_MODEL")"
set_key transcribe.openai base_url "$(toml_str "$TRANSCRIBE_BASE_URL")"
set_key transcribe.openai api_key "$(toml_str "$TRANSCRIBE_API_KEY")"
set_key transcribe.openai model "$(toml_str "$TRANSCRIBE_MODEL")"
set_key tts.openai base_url "$(toml_str "$TTS_BASE_URL")"
set_key tts.openai api_key "$(toml_str "$TTS_API_KEY")"
set_key tts.openai model "$(toml_str "$TTS_MODEL")"
chmod 600 "$CONF"

ADMIN_PASSWORD_HASH="$(caddy hash-password --plaintext "$ADMIN_PASSWORD")"
export ADMIN_USER ADMIN_PASSWORD_HASH PORT
unset ADMIN_PASSWORD

log "starting KrillinAI server $(cat /opt/krillinai/VERSION 2>/dev/null || echo) on 127.0.0.1:8888"
/opt/krillinai/krillinai-server &
APP_PID=$!

# Wait for the app before opening the public port, so /healthz only passes
# once the UI answers. The server exits (with code 0) on a bad config.
i=0
until curl -fsS -o /dev/null http://127.0.0.1:8888/static/; do
  kill -0 "$APP_PID" 2>/dev/null || die "KrillinAI server stopped during startup (see the log lines above)."
  i=$((i + 1)); [ "$i" -lt 240 ] || die "KrillinAI server did not answer within 120 s."
  sleep 0.5
done

log "starting Caddy on :$PORT (basic auth user: $ADMIN_USER)"
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY_PID=$!

trap 'kill -TERM "$APP_PID" "$CADDY_PID" 2>/dev/null; exit 0' TERM INT

# BusyBox/dash "wait -n" isn't reliable, so poll both processes.
while :; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    wait "$APP_PID" 2>/dev/null || true
    kill -TERM "$CADDY_PID" 2>/dev/null || true
    die "KrillinAI server stopped unexpectedly; exiting so Railway restarts the service."
  fi
  if ! kill -0 "$CADDY_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    die "Caddy stopped unexpectedly; exiting so Railway restarts the service."
  fi
  sleep 2
done
