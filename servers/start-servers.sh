#!/bin/bash
# Start STT + TTS servers for Claude Voice Mode
# Usage: ./start-servers.sh [venv_path]
#
# Voice input is separate: ./scripts/start-input-voice-whisper.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VENV_PATH="${1:-$HOME/mlx-openai-whisper}"

if [ ! -f "$VENV_PATH/bin/activate" ]; then
  echo "Error: Virtual environment not found at $VENV_PATH"
  echo "Usage: $0 [path/to/venv]"
  exit 1
fi

source "$VENV_PATH/bin/activate"

export SERVER_PORT="${SERVER_PORT:-8000}"

echo "Starting unified server (STT+TTS) on http://localhost:$SERVER_PORT"
python "$SCRIPT_DIR/unified_server.py" &
STT_PID=$!
TTS_PID=$STT_PID

# Wait for server to be ready
echo "Waiting for server..."
READY=false
for i in $(seq 1 60); do
  curl -s "http://localhost:$SERVER_PORT/v1/models" > /dev/null 2>&1 && { READY=true; break; }
  sleep 1
done
$READY && echo "Server ready." || echo "WARNING: Server did not start within 60s"
echo ""
echo "Press Ctrl+C to stop servers."

cleanup() {
  echo "Shutting down..."
  kill "$STT_PID" "$TTS_PID" 2>/dev/null
  rm -f "$HOME/Library/Application Support/ClaudeWhisperer/tts_playing.lock" "$HOME/Library/Application Support/ClaudeWhisperer/tts_hook.pid"
  wait 2>/dev/null
  echo "Done."
  exit 0
}
trap cleanup INT TERM
wait
