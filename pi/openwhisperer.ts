/**
 * OpenWhisperer voice extension for Pi.
 *
 * Brings OpenWhisperer's voice mode to the Pi coding agent, which has no MCP:
 *   1. Registers a `speak` tool that plays text via OpenWhisperer's local TTS server (:8000).
 *   2. On a voice-dictated turn (prompt hash matches the app's `voice_turn` signal), injects a
 *      hidden per-turn nudge so the model calls `speak` first with a standalone spoken summary.
 *
 * Mirrors hooks/voice-context.sh (gating + nudge) and the speak MCP tool (in-app playback).
 * Single self-contained file — no MCP server, no bash hook.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { Text } from "@earendil-works/pi-tui";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, readFileSync, rmSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const APP_SUPPORT = join(homedir(), "Library", "Application Support", "OpenWhisperer");
const VOICE_TURN = join(APP_SUPPORT, "voice_turn");
const TTS_PLAY_URL = "http://localhost:8000/v1/audio/play";
const FRESHNESS_S = 900; // voice_turn TTL — matches voice-context.sh

function readPref(envVar: string, file: string, fallback: string): string {
  const env = process.env[envVar]?.trim();
  if (env) return env;
  try {
    return readFileSync(join(APP_SUPPORT, file), "utf8").trim() || fallback;
  } catch {
    return fallback;
  }
}

function nudgeLen(style: string): string {
  switch (style) {
    case "terse":
      return "one short, plain spoken sentence";
    case "rich":
      return "a sentence or two of plain spoken summary";
    case "full":
      return "a spoken paragraph of four or five sentences";
    default:
      return "one plain spoken sentence";
  }
}

/// Extra instruction for the longest tier only — mirrors `resolve_depth_line` in
/// hooks/voice-shared.sh. Without it, "full" reads as just a longer summary.
function nudgeDepth(style: string): string {
  if (style !== "full") return "";
  return (
    " Use that paragraph to explain your reasoning and any trade-offs, not just the conclusion" +
    " — but keep it spoken prose, with no lists, headings, code, or file paths."
  );
}

function debug(msg: string): void {
  if (!process.env.OW_PI_DEBUG) return;
  try {
    appendFileSync(join(APP_SUPPORT, "pi-voice.log"), `${new Date().toISOString()} ${msg}\n`);
  } catch {
    /* ignore */
  }
}

/**
 * True if `prompt` matches a fresh `voice_turn` signal — i.e. this turn was dictated.
 * Claims (deletes) the signal on a match so a later typed turn isn't also matched.
 * The hash must match VoiceSignal.canonicalHash: sha256 of the whitespace-trimmed text.
 */
function claimVoiceTurn(prompt: string): boolean {
  if (!existsSync(VOICE_TURN)) return false;
  let raw: string;
  try {
    raw = readFileSync(VOICE_TURN, "utf8");
  } catch {
    return false;
  }
  const lines = raw.split("\n");
  const storedHash = (lines[0] ?? "").trim();
  const storedTs = Number.parseInt((lines[1] ?? "").trim(), 10);
  if (!storedHash) return false;

  const now = Math.floor(Date.now() / 1000);
  if (Number.isFinite(storedTs) && now - storedTs > FRESHNESS_S) {
    try {
      rmSync(VOICE_TURN);
    } catch {
      /* ignore */
    }
    return false;
  }

  const promptHash = createHash("sha256").update(prompt.trim()).digest("hex");
  if (promptHash !== storedHash) return false;

  try {
    rmSync(VOICE_TURN); // atomic-enough claim for a single local user
  } catch {
    /* ignore */
  }
  return true;
}

export default function (pi: ExtensionAPI) {
  // 1. The `speak` tool — plays text aloud via OpenWhisperer's local TTS (fire-and-forget).
  pi.registerTool({
    name: "openwhisperer_speak",
    label: "OpenWhisperer",
    description:
      "Speak the given text aloud through OpenWhisperer's local voice (text-to-speech). " +
      "Fire-and-forget: returns immediately while audio plays.",
    promptSnippet: "Speak a short spoken summary aloud via OpenWhisperer TTS",
    parameters: Type.Object({
      text: Type.String({ description: "The text to speak aloud." }),
    }),
    async execute(_toolCallId, params) {
      debug(`speak tool called: ${JSON.stringify(params.text).slice(0, 80)}`);
      // Per-project voice/speed: read here (the extension owns the call, so this is
      // deterministic — no dependency on the model echoing args). Precedence: env → file.
      const voice = readPref("OW_TTS_VOICE", "tts_voice", "");
      const speed = Number.parseFloat(readPref("OW_TTS_SPEED", "tts_speed", ""));
      const body: Record<string, unknown> = { input: params.text };
      if (voice) body.voice = voice;
      if (Number.isFinite(speed)) body.speed = speed;
      try {
        await fetch(TTS_PLAY_URL, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
      } catch (e) {
        return {
          content: [{ type: "text", text: `speak failed: ${(e as Error).message}` }],
          isError: true,
        };
      }
      return { content: [{ type: "text", text: "Speaking." }] };
    },
    // Pretty TUI header: show the brand, not the snake_case wire name (openwhisperer_speak).
    renderCall(_args, theme) {
      return new Text(theme.fg("toolTitle", theme.bold("OpenWhisperer")), 0, 0);
    },
  });

  // 2. The gated nudge — on a turn the response mode means to speak, inject a hidden directive
  //    telling the model to call `speak` first. Per-turn, invisible to the on-screen reply.
  pi.on("before_agent_start", async (event) => {
    const prompt = typeof event.prompt === "string" ? event.prompt : "";
    if (!prompt) return;

    const mode = readPref("OW_TTS_RESPONSE", "tts_response_mode", "voice");
    const isVoice = claimVoiceTurn(prompt);

    // Response mode: "always" speaks every turn; "needed" makes every turn a candidate but
    // hands the decision to the model; "voice" (default, and any stale "text") speaks only
    // dictated turns. Mirrors the mode table in hooks/voice-shared.sh.
    const speak = mode === "always" || mode === "needed" ? true : isVoice;

    debug(`before_agent_start mode=${mode} isVoice=${isVoice} speak=${speak}`);
    if (!speak) return;

    const style = readPref("OW_TTS_STYLE", "tts_style", "normal");
    const len = nudgeLen(style);
    const depth = nudgeDepth(style);
    const tail =
      ` Then write your full reply on screen as usual. Do not mention the tool in your written reply.`;

    // "Only when I'm needed" cannot be decided here — this runs before the turn exists — so
    // the gate is delegated to the model, exactly as the bash hooks do for the other agents.
    const nudge =
      mode === "needed"
        ? `Speak this reply ONLY if it needs something from me. First decide whether this turn ends on me: ` +
          `you are asking a question, you are blocked, you need my approval for something risky or ` +
          `destructive, or something failed and I have to choose what happens next. If so, your FIRST ` +
          `action must be to call the \`openwhisperer_speak\` tool exactly once, passing ${len} that says ` +
          `plainly what you need from me and stands alone when heard.${depth} If instead the work simply ` +
          `succeeded and needs nothing from me, do NOT call the tool at all — staying silent is the ` +
          `correct outcome.${tail}`
        : `${isVoice ? "This turn was dictated by voice. " : ""}Before writing your on-screen reply, your ` +
          `FIRST action must be to call the \`openwhisperer_speak\` tool exactly once, passing ${len} that ` +
          `summarizes your answer and stands alone when heard.${depth} Do not skip the speak call.${tail}`;

    return {
      message: {
        customType: "openwhisperer-voice-nudge",
        content: nudge,
        display: false,
      },
    };
  });
}
