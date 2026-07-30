// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenWhisperer",
    platforms: [.macOS(.v14)],
    dependencies: [
        // STT: WhisperKit (CoreML / ANE). Restored 2026-07-30 at the owner's request,
        // reversing the 2026-07-13 migration to Parakeet.
        //
        // DO NOT float this pin. Upstream 1.0.0 (and main) aborts the decode loop when
        // the model samples <|endoftext|> during the forced promptTokens prefill — with
        // large-v3 turbo that happens deterministically, so ANY non-empty stt_vocabulary
        // makes every dictation return an EMPTY transcript (recording runs, nothing is
        // typed). a1eb2f0 is v1.0.0 plus the one-line fix gating the completion check on
        // !isPrefill. Reported upstream; drop the pin only once argmaxinc ships the fix.
        // See 51abaec — and note 16a74d8 retracted the "revert to 0.18.0" story.
        .package(url: "https://github.com/hakanensari/WhisperKit.git",
                 revision: "a1eb2f0183bb87ef1582a4e1c9325d2d71578ed0"),
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
