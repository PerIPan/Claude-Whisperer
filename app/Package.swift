// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenWhisperer",
    platforms: [.macOS(.v14)],
    dependencies: [
        // STT: WhisperKit (CoreML / ANE). Restored 2026-07-30 at the owner's request,
        // reversing the 2026-07-13 migration to Parakeet.
        //
        // Un-forked 2026-09-02: argmaxinc shipped the fix, which was the one condition the
        // fork pin was waiting on.
        //
        // The bug: with `promptTokens` set, the decode loop force-feeds the prompt and the
        // completion check still honored an EOT sampled mid-prefill. large-v3 turbo predicts
        // <|endoftext|> there deterministically, so ANY non-empty stt_vocabulary made every
        // dictation return an EMPTY transcript — recording ran, nothing was typed. That is
        // why this was pinned to a fork of v1.0.0 carrying a one-line `!isPrefill` gate.
        //
        // Upstream PR #514 ("Fix empty transcription when promptTokens are set", co-authored
        // by the same person who wrote the fork patch) fixes it more thoroughly — a logits
        // filter plus a prefill rework, with ~200 lines of new unit tests — and shipped in
        // v1.1.0 (2026-08-06). Verified #514 is an ancestor of that tag before switching.
        //
        // Do NOT go back to hakanensari/WhisperKit's `main`: it is *diverged*, missing both
        // v1.0.0 and the EOT fix, so it is a downgrade, not an upgrade. The fork itself stays
        // reachable, but nothing here needs it any more.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.0"),
        // TTS: native in-process Kokoro (CoreML / ANE). Apache-2.0. macOS 14+. No metallib.
        // Release 0.15.5+ contains the #730 fix ("Fix KokoroAne strided MLMultiArray handling")
        // which resolves issue #727 where 0.15.4 mis-read a *strided* MLMultiArray the Kokoro
        // chain returned on some Apple Silicon (e.g. M3/macOS 15), yielding fluent-but-WRONG words.
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            from: "0.15.5"),
    ],
    targets: [
        // Pure, dependency-free logic that is unit-tested in isolation
        // (no AppKit / AVFoundation / FluidAudio), so it builds and runs fast.
        .target(
            name: "OpenWhispererKit",
            path: "Sources/OpenWhispererKit"
        ),
        .executableTarget(
            name: "OpenWhisperer",
            dependencies: [
                "OpenWhispererKit",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/OpenWhisperer"
        ),
        // Test harness as a plain executable: this machine has Command Line Tools
        // only (no XCTest / swift-testing module). Run with: `swift run OpenWhispererKitTests`
        // (exits non-zero on any failure). Swap for an XCTest target once full Xcode is installed.
        .executableTarget(
            name: "OpenWhispererKitTests",
            dependencies: ["OpenWhispererKit"],
            path: "Tests/OpenWhispererKitTests"
        ),
        // Integration tests for the bash hooks (UserPromptSubmit for Claude/Codex,
        // PreInvocation for Antigravity CLI). Shells out to ../../hooks/*.sh in an isolated
        // temp HOME with a stubbed curl — the Swift port of the deleted pytest suite.
        // Run with: `swift run HookTests`.
        .executableTarget(
            name: "HookTests",
            dependencies: ["OpenWhispererKit"],
            path: "Tests/HookTests"
        ),
    ]
)
