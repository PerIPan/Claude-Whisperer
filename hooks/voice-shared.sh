#!/bin/bash
# Shared logic for OpenWhisperer's voice-turn hooks: response-mode resolution, voice_turn
# hash-match-and-claim, style/voice/persona resolution, and nudge-sentence construction.
# Sourced by hooks/voice-context.sh (Claude Code + Codex UserPromptSubmit) and
# hooks/agy-previnvocation.sh (Antigravity CLI PreInvocation) — the two hooks differ in
# stdin/stdout shape but share this decision.

APP_SUPPORT="$HOME/Library/Application Support/OpenWhisperer"
VOICE_TURN="$APP_SUPPORT/voice_turn"
# voice_turn time-to-live (seconds) — kept uniform across the hooks.
FRESHNESS=900

# Response mode. Precedence: per-project OW_TTS_RESPONSE env → global file → "voice".
#   voice  (default) — speak only voice-dictated turns
#   always           — speak every turn
#   needed           — every turn is a candidate, but the model speaks only when the turn
#                      ends on the user (question / blocked / approval / failure). The gate
#                      lives in the nudge because this hook cannot see the turn's outcome.
resolve_mode() {
  local mode="$OW_TTS_RESPONSE"
  [ -z "$mode" ] && mode=$(cat "$APP_SUPPORT/tts_response_mode" 2>/dev/null | tr -d '[:space:]')
  [ -z "$mode" ] && mode="voice"
  printf '%s' "$mode"
}

# Determine whether THIS turn was voice-dictated: a fresh voice_turn whose hash matches the
# given prompt text. On a match, atomically claim (consume) the signal so a later typed turn
# isn't also matched. A stale signal is swept. Echoes "1" (matched+claimed) or "0" (no match).
# (Hashing MUST match VoiceSignal.canonicalHash.)
match_and_claim_voice_turn() {
  local prompt="$1"
  [ -f "$VOICE_TURN" ] || { echo 0; return; }
  local stored_hash stored_ts
  stored_hash=$(sed -n '1p' "$VOICE_TURN" 2>/dev/null)
  stored_ts=$(sed -n '2p' "$VOICE_TURN" 2>/dev/null)
  [ -z "$stored_hash" ] && { echo 0; return; }
  # Bash re-evaluates variable contents inside $(( )), so an array subscript in this field
  # would run command substitution: a voice_turn holding `x[$(...)]` executes it. The file
  # sits in a 0700 dir and is app-written, so nothing crosses a privilege boundary — but it
  # is the documented cross-process IPC bus, which makes this an easy sink to forget.
  case "$stored_ts" in ''|*[!0-9]*) stored_ts=0 ;; esac
  local now
  now=$(date +%s)
  if [ "$stored_ts" -gt 0 ] && [ "$((now - stored_ts))" -gt "$FRESHNESS" ]; then
    rm -f "$VOICE_TURN"
    echo 0
    return
  fi
  trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
  local trimmed prompt_hash
  trimmed=$(trim "$prompt")
  if command -v shasum >/dev/null 2>&1; then
    prompt_hash=$(printf '%s' "$trimmed" | shasum -a 256 | awk '{print $1}')
  else
    prompt_hash=$(printf '%s' "$trimmed" | openssl dgst -sha256 | awk '{print $NF}')
  fi
  if [ "$prompt_hash" = "$stored_hash" ]; then
    local claim="$APP_SUPPORT/.voice_turn.claimed.$$"
    if mv "$VOICE_TURN" "$claim" 2>/dev/null; then
      rm -f "$claim"
      echo 1
      return
    fi
  fi
  echo 0
}

# Spoken-summary length hint. Precedence: OW_TTS_STYLE env → tts_style file → legacy voice_detail.
resolve_length_phrase() {
  local style="$OW_TTS_STYLE"
  [ -z "$style" ] && style=$(cat "$APP_SUPPORT/tts_style" 2>/dev/null | tr -d '[:space:]')
  [ -z "$style" ] && style=$(cat "$APP_SUPPORT/voice_detail" 2>/dev/null | tr -d '[:space:]')
  case "$style" in
    terse) echo "one short, plain spoken sentence" ;;
    rich)  echo "a sentence or two of plain spoken summary" ;;
    # `full` used to fold into `rich`; since 2.0.0 it is its own, longest tier. Anyone
    # carrying the legacy value asked for maximum detail, so promoting them is a
    # restoration of that intent rather than a surprise.
    full)  echo "a spoken paragraph of four or five sentences" ;;
    *)     echo "one plain spoken sentence" ;;
  esac
}

# Depth nudge for the longest tier only. The base sentence asks for something that
# "summarizes your answer", which on its own would cap `full` at a longer summary —
# this tells the model to actually explain. Empty for every other tier.
resolve_depth_line() {
  local style="$OW_TTS_STYLE"
  [ -z "$style" ] && style=$(cat "$APP_SUPPORT/tts_style" 2>/dev/null | tr -d '[:space:]')
  [ -z "$style" ] && style=$(cat "$APP_SUPPORT/voice_detail" 2>/dev/null | tr -d '[:space:]')
  if [ "$style" = "full" ]; then
    echo " Use that paragraph to explain your reasoning and any trade-offs, not just the conclusion — but keep it spoken prose, with no lists, headings, code, or file paths."
  else
    echo ""
  fi
}

# Native-tongue flavor: for a personified voice, an ungated persona keyed off the voice id's
# first char: a light national character, set for English (a/b) too. The flavors stay subdued,
# so they don't detract from the message. Personality only, no vocabulary steering; whatever
# code-switching happens is the model's own.
# The map lives ONLY here (unknown/no voice → nothing); HookTests is its guard.
# Resolved voice: per-project OW_TTS_VOICE env → global tts_voice file.
resolve_flavor() {
  local voice="$OW_TTS_VOICE"
  [ -z "$voice" ] && voice=$(cat "$APP_SUPPORT/tts_voice" 2>/dev/null)
  voice=$(printf '%s' "$voice" | tr -d '[:space:]')
  local accent="" persona="" desc=""
  case "${voice:0:1}" in
    a) accent="American English";     persona="American";  desc="quietly self-assured, with a light touch of Silicon Valley hype" ;;
    b) accent="British English";      persona="British";   desc="dry and unflappable, with a streak of deadpan wit and gentle irony" ;;
    f) accent="French";               persona="French";    desc="dry and faintly unimpressed, given to the occasional philosophical shrug" ;;
    i) accent="Italian";              persona="Italian";   desc="warm and expressive; things are either wonderful or a small catastrophe, rarely in between" ;;
    e) accent="Spanish";              persona="Spanish";   desc="relaxed and direct; there's always time, and it'll all be fine" ;;
    p) accent="Brazilian Portuguese"; persona="Brazilian"; desc="sunny and easygoing, unbothered, always a friendly way around things" ;;
    h) accent="Hindi";                persona="Hindi";     desc="warm and irrepressibly helpful, the eternal problem-solver, assuring you it's no trouble at all" ;;
    j) accent="Japanese";             persona="Japanese";  desc="courteous and understated, meticulous, softening things, quietly prizing care and subtlety" ;;
    z) accent="Mandarin Chinese";     persona="Chinese";   desc="pragmatic and modest, understated, fond of a proverb, unfussed by small things" ;;
  esac
  if [ -n "$persona" ]; then
    echo " The voice speaking your reply has a ${accent} accent. Adopt a ${persona} persona: ${desc}."
  else
    echo ""
  fi
}

# Reply language for the multilingual (Supertonic) voices. A Dutch voice reading English text is
# pointless, so when one of those voices is active we tell the model to write the spoken summary
# in that language. The language rides inside the voice id (`supertonic:<lang>:<style>`), so this
# is a plain code→name lookup rather than the first-char scheme resolve_flavor uses for Kokoro.
#
# Like the persona map, this lives ONLY here — no Swift parity pair — and HookTests is its guard.
# Kokoro voices are unaffected (their language is implied by the voice and the model already
# replies in the user's language); `en` gets no line since English is the default.
resolve_language_line() {
  local voice="$OW_TTS_VOICE"
  [ -z "$voice" ] && voice=$(cat "$APP_SUPPORT/tts_voice" 2>/dev/null)
  voice=$(printf '%s' "$voice" | tr -d '[:space:]')
  case "$voice" in
    supertonic:*|SUPERTONIC:*) ;;
    *) echo ""; return ;;
  esac
  local code language
  code=$(printf '%s' "$voice" | cut -d: -f2 | tr '[:upper:]' '[:lower:]')
  case "$code" in
    nl) language="Dutch" ;;      de) language="German" ;;      pl) language="Polish" ;;
    ru) language="Russian" ;;    uk) language="Ukrainian" ;;   fr) language="French" ;;
    it) language="Italian" ;;    es) language="Spanish" ;;     pt) language="Portuguese" ;;
    hi) language="Hindi" ;;      ja) language="Japanese" ;;    ko) language="Korean" ;;
    ar) language="Arabic" ;;     bg) language="Bulgarian" ;;   cs) language="Czech" ;;
    da) language="Danish" ;;     el) language="Greek" ;;       et) language="Estonian" ;;
    fi) language="Finnish" ;;    hr) language="Croatian" ;;    hu) language="Hungarian" ;;
    id) language="Indonesian" ;; lt) language="Lithuanian" ;;  lv) language="Latvian" ;;
    ro) language="Romanian" ;;   sk) language="Slovak" ;;      sl) language="Slovenian" ;;
    sv) language="Swedish" ;;    tr) language="Turkish" ;;     vi) language="Vietnamese" ;;
    *) echo ""; return ;;
  esac
  # Sentinel phrase kept distinct from resolve_flavor's "voice speaking your reply" so the two
  # layers stay independently assertable in HookTests.
  echo " Write the text you pass to \`speak\` in ${language}, not English — that is the language the selected voice speaks. Your on-screen reply stays in the language of the conversation."
}

# Speak tool args → tell the model the exact voice/speed to pass to `speak` to prevent guesswork.
# We always explicitly instruct the model to pass the active voice (global or overridden).
resolve_speak_args() {
  local voice="$OW_TTS_VOICE"
  [ -z "$voice" ] && voice=$(cat "$APP_SUPPORT/tts_voice" 2>/dev/null)
  voice=$(printf '%s' "$voice" | tr -d '[:space:]')
  [ -z "$voice" ] && voice="af_heart"

  local ovr=" voice=\"$voice\""
  if [ -n "$OW_TTS_SPEED" ] && printf '%s' "$OW_TTS_SPEED" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
    ovr="${ovr} speed=$OW_TTS_SPEED"
  fi
  # Conditional wording in "needed" mode: an unconditional "Call it with…" directly after
  # "do NOT call the tool at all" reads as a contradictory imperative.
  if [ "$(resolve_mode)" = "needed" ]; then
    echo " If you do speak, call it with${ovr}."
  else
    echo " Call it with${ovr}."
  fi
}

# Build the full nudge sentence. $1 = IS_VOICE (0/1).
build_nudge() {
  local is_voice="$1"
  local mode len flavor speak_args lang_line depth_line prefix core
  mode=$(resolve_mode)
  len=$(resolve_length_phrase)
  flavor=$(resolve_flavor)
  speak_args=$(resolve_speak_args)
  lang_line=$(resolve_language_line)
  depth_line=$(resolve_depth_line)

  if [ "$mode" = "needed" ]; then
    # "Only when I'm needed" cannot be decided here: this hook runs at prompt-submit,
    # before the turn exists, and there is deliberately no Stop hook. So the gate is
    # delegated to the model, which knows while composing whether the turn ends on the
    # user. Same accepted trade as the rest of the handshake — no fallback either way.
    prefix="Speak this reply ONLY if it needs something from me."
    core=$(printf 'First decide whether this turn ends on me: you are asking a question, you are blocked, you need my approval for something risky or destructive, or something failed and I have to choose what happens next. If so, your FIRST action must be to call the `speak` tool exactly once, passing %s that says plainly what you need from me and stands alone when heard.%s If instead the work simply succeeded and needs nothing from me, do NOT call the tool at all — staying silent is the correct outcome, and a spoken "all done" is exactly what this mode exists to avoid.' \
      "$len" "$depth_line")
  else
    if [ "$is_voice" -eq 1 ]; then
      prefix="This turn was dictated by voice."
    else
      prefix="This reply should be spoken aloud."
    fi
    core=$(printf 'Before writing your on-screen reply, your FIRST action must be to call the `speak` tool exactly once, passing %s that summarizes your answer and stands alone when heard.%s Do not skip the speak call.' \
      "$len" "$depth_line")
  fi

  printf '%s %s%s Then write your full reply on screen as usual. Do not mention the tool in your written reply.%s%s' \
    "$prefix" "$core" "$speak_args" "$flavor" "$lang_line"
}
