"""Lightweight OpenAI-compatible Whisper STT server using MLX."""

import asyncio
import re
import subprocess
import threading
import mlx_whisper
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import tempfile, os, uvicorn

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8000", "http://localhost:8100", "http://127.0.0.1:8000", "http://127.0.0.1:8100"],
    allow_methods=["POST", "GET"],
    allow_headers=["Content-Type"],
)

MODEL = os.getenv("WHISPER_MODEL", "mlx-community/whisper-large-v3-turbo")

# Auto-submit: flag file toggled by the menubar app
AUTO_SUBMIT_FLAG = os.path.expanduser(
    "~/Library/Application Support/ClaudeWhisperer/auto_submit"
)
AUTO_FOCUS_APP = os.path.expanduser(
    "~/Library/Application Support/ClaudeWhisperer/auto_focus_app"
)
SUBMIT_TRIGGERS = ["submit", "send it", "go ahead", "send", "enter"]

_transcribe_lock = threading.Lock()

models_response = {
    "object": "list",
    "data": [{"id": "whisper-1", "object": "model", "owned_by": "local"}]
}

@app.get("/v1/models")
@app.get("/models")
async def list_models():
    return models_response

def _serialize_transcribe(tmp_path, language):
    """Run transcription with mutex to prevent concurrent MLX access."""
    with _transcribe_lock:
        return mlx_whisper.transcribe(tmp_path, path_or_hf_repo=MODEL, language=language)


def check_submit_trigger(text):
    """Check if text ends with a submit trigger. Returns (cleaned_text, should_submit)."""
    lower = text.lower().rstrip(" .,!?")
    for trigger in SUBMIT_TRIGGERS:
        if lower.endswith(trigger):
            pattern = r'\s*\b' + re.escape(trigger) + r'[.!?,]?$'
            cleaned = re.sub(pattern, '', text.strip(), flags=re.IGNORECASE)
            return cleaned, True
    return text, False


def focus_target_app():
    """Bring the target app to front if auto-focus is configured."""
    try:
        if not os.path.exists(AUTO_FOCUS_APP):
            return
        app_name = open(AUTO_FOCUS_APP).read().strip()
        if not app_name:
            return
        subprocess.Popen(
            ["osascript", "-e", f'tell application "{app_name}" to activate'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def press_cmd_enter():
    """Press Cmd+Enter in the frontmost app via AppleScript."""
    try:
        subprocess.Popen(
            ["osascript", "-e", 'tell application "System Events" to key code 36 using command down'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


async def do_transcribe(file, model, language, response_format):
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
            tmp.write(await file.read())
            tmp_path = tmp.name
        loop = asyncio.get_running_loop()
        result = await loop.run_in_executor(None, lambda: _serialize_transcribe(tmp_path, language or None))
        text = result["text"]
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # Auto-focus: bring target app to front before Voquill types
    focus_target_app()

    # Auto-submit: check trigger words if enabled
    should_submit = False
    if os.path.exists(AUTO_SUBMIT_FLAG):
        text, should_submit = check_submit_trigger(text)

    # Schedule Enter keypress after response is sent
    if should_submit:
        async def delayed_enter():
            await asyncio.sleep(0.3)  # wait for Voquill to finish typing
            press_cmd_enter()
        asyncio.ensure_future(delayed_enter())

    if response_format == "text":
        return text
    return JSONResponse({"text": text})

@app.post("/v1/audio/transcriptions")
@app.post("/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    model: str = Form(default="whisper-1"),
    language: str = Form(default=None),
    response_format: str = Form(default="json"),
):
    return await do_transcribe(file, model, language, response_format)

if __name__ == "__main__":
    port = int(os.getenv("STT_PORT", "8000"))
    uvicorn.run(app, host="127.0.0.1", port=port)
