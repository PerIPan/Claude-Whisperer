import Foundation
import SwiftUI
import Combine
import OpenWhispererKit

/// Borderless window that accepts keyboard input (enables Cmd+C for text selection).
private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Custom hosting view that forwards the very first mouse click to active elements even when the window is inactive.
private class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class TranscriptionOverlay: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = TranscriptionOverlay()

    private var window: NSWindow?
    /// The faceplate tint layer, kept so a theme change can repaint it. `.cgColor` resolves a
    /// dynamic NSColor immediately, so it cannot update itself.
    private var tintView: NSView?
    private var effectView: NSVisualEffectView?

    /// The page colour the faceplate should take. Cream keeps its historic smoked-dark
    /// instrument face in both appearances; every other theme shows its own page colour.
    private static func faceplatePage() -> (color: NSColor, isLight: Bool) {
        let theme = ThemeManager.shared.theme
        if theme == .cream {
            let dark = OWTheme.creamDarkPage
            return (NSColor.ow(dark, dark), false)
        }
        let page = theme.palettes.light.page
        return (NSColor.ow(page, page), luminance(page) > 0.55)
    }

    /// Faceplate colour for the active theme.
    ///
    /// A light page needs to sit almost opaquely: `.hudWindow` is a dark material in both
    /// appearances, so at the original 0.75 the blur dominated and every light theme came out
    /// the same muddy grey rather than its own colour.
    private static func faceplateColor() -> NSColor {
        let page = faceplatePage()
        return page.color.withAlphaComponent(page.isLight ? 0.94 : 0.75)
    }

    /// Dark themes keep the HUD material; light ones would be dragged grey by it.
    private static func faceplateMaterial() -> NSVisualEffectView.Material {
        faceplatePage().isLight ? .windowBackground : .hudWindow
    }

    /// Relative luminance of a 0xRRGGBB colour, 0…1.
    private static func luminance(_ hex: UInt32) -> Double {
        func channel(_ raw: UInt32) -> Double {
            let c = Double(raw) / 255.0
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
            + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    /// Repaint the overlay after the user picks a different theme.
    ///
    /// Two separate things need poking: the faceplate is a `CALayer` colour, which nothing
    /// re-evaluates on its own, and the SwiftUI content above it (waveform gradients, status
    /// text, the wave-style background) only re-reads `OWColor` when something it observes
    /// changes — so publish as well, or the bars keep their old palette until the next redraw.
    func refreshTheme() {
        tintView?.layer?.backgroundColor = Self.faceplateColor().cgColor
        effectView?.material = Self.faceplateMaterial()
        window?.appearance = ThemeManager.shared.windowAppearance
        objectWillChange.send()
    }

    @Published var isVisible: Bool = false {
        didSet { SpectrumGate.update(visible: isVisible, style: analyzerStyle) }
    }
    /// Mirrors `TTSPlaybackState.shared.isPlaying`, subscribed once in `show()`. Was a
    /// 0.3 s `tts_playing.lock` poll until 2026-09-06 — the writer is in this process.
    @Published var isTTSPlaying: Bool = false
    private var ttsStateCancellable: AnyCancellable?

    /// The current PTT key label shown in the overlay (e.g. "Ctrl", "fn").
    @Published var pttKeyLabel: String = "Ctrl"

    /// Active analyzer style (wave / LED bars / graph / curtain). Read from the pref
    /// file on show(); Settings writes the file and updates this directly.
    @Published var analyzerStyle: OverlayStyle = .defaultStyle {
        didSet {
            SpectrumGate.update(visible: isVisible, style: analyzerStyle)
            guard oldValue != analyzerStyle, window != nil else { return }
            if analyzerStyle == .wave { applyWaveHeight() } else { restoreSavedHeight() }
        }
    }

    /// Current interaction mode — determines hint text during recording.
    @Published var interactionMode: InteractionMode = .pressToTalk

    /// Reference to dictation manager for waveform display.
    ///
    /// FIX: Use a @Published wrapper so the SwiftUI root view can observe
    /// the recorder reference changing, instead of tearing down NSHostingView.
    /// Tearing down NSHostingView cancels the TimelineView render loop and
    /// creates a new @ObservedObject subscription to a potentially stale instance.
    var dictationManager: DictationManager? {
        didSet {
            // FIX: Rather than recreating the entire NSHostingView (which kills
            // the TimelineView animation loop and risks observing a stale recorder),
            // publish the new recorder reference through a @Published property on
            // the overlay so the live SwiftUI tree picks it up reactively.
            if let dm = dictationManager {
                currentRecorder = dm.recorder
            }
            wireStatus()
        }
    }

    /// Mirrors the speech-model / setup status into the standby overlay so it shows
    /// "Loading speech model…", a failure message, or a model-load failure
    /// instead of always claiming "Listening for transcriptions…".
    @Published var statusText: String?
    @Published var statusIsError: Bool = false

    /// Setup manager reference so the overlay can mirror setup failures.
    weak var setupManager: SetupManager? {
        didSet { wireStatus() }
    }

    private var statusCancellables = Set<AnyCancellable>()

    /// The live recorder reference. Published so the SwiftUI view tree reacts
    /// to recorder swaps without NSHostingView teardown.
    ///
    /// FIX: This is the critical fix. @ObservedObject inside NSHostingView works
    /// correctly, but ONLY if it holds the same instance that is actually recording.
    /// Previously, show() could capture a throwaway AudioRecorder() when
    /// dictationManager was nil, and that dead instance would be observed forever.
    @Published var currentRecorder: AudioRecorder = AudioRecorder(skipPermissionCheck: true)

    // MARK: - Transcript lines (Wave style only — the 1.6.0 resize-grip feature)

    struct Line: Identifiable {
        let id: Int
        let text: String
    }
    /// Recent transcriptions, oldest→newest (memory-bounded). Fed by `wireStatus()`.
    @Published var lines: [Line] = []
    private var nextLineId = 0

    /// The top of the range — the overlay never shows more than this many lines.
    static let maxTranscriptLines = 3
    static func clampLines(_ n: Int) -> Int { Swift.max(0, Swift.min(maxTranscriptLines, n)) }

    /// How many recent transcript lines the Wave overlay shows (0…max). Driven by the
    /// resize grip; persisted. Changing it resizes the Wave window to fit.
    @Published var transcriptLines: Int = TranscriptionOverlay.loadTranscriptLines() {
        didSet { if analyzerStyle == .wave { applyWaveHeight() } }
    }
    private static func loadTranscriptLines() -> Int {
        let raw = (try? String(contentsOf: Paths.overlayLines, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clampLines(Int(raw ?? "") ?? maxTranscriptLines)
    }
    func persistTranscriptLines() {
        try? String(transcriptLines).write(to: Paths.overlayLines, atomically: true, encoding: .utf8)
    }

    /// Suppress window-drag-to-move while the grip is being dragged (so the drag
    /// resizes instead of moving the window).
    func setWindowMovable(_ movable: Bool) {
        window?.isMovableByWindowBackground = movable
    }

    /// Resize the Wave window's height to fit the wave + N transcript lines, keeping
    /// the bottom-right anchor (origin.y fixed → grows upward). No-op for other styles.
    /// True while the resize grip is being dragged — suppresses per-step animation so
    /// the window tracks the cursor 1:1 instead of lagging behind overlapping animations.
    var isGripDragging = false

    func applyWaveHeight() {
        guard let w = window, analyzerStyle == .wave else { return }
        let base: CGFloat = 84                       // wave + status dot row
        let rowH: CGFloat = 26
        let extra: CGFloat = transcriptLines > 0 ? (8 + CGFloat(transcriptLines) * rowH) : 0
        var f = w.frame
        f.size.height = base + extra                 // origin.y unchanged → bottom stays put
        w.setFrame(f, display: true, animate: !isGripDragging)
    }

    /// Restore the user's saved free-resize height (used when leaving the Wave style).
    private func restoreSavedHeight() {
        guard let w = window else { return }
        let size = OverlaySize.parse(try? String(contentsOf: Paths.overlaySize, encoding: .utf8))
        var f = w.frame
        f.size.height = CGFloat(size.height)
        w.setFrame(f, display: true, animate: true)
    }

    func show() {
        try? FileManager.default.removeItem(at: Paths.overlayHidden)
        analyzerStyle = OverlayStyle.parse(try? String(contentsOf: Paths.overlayStyle, encoding: .utf8))
        if let w = window {
            // FIX: Never recreate NSHostingView on an already-constructed window.
            // Recreating it tears down the entire SwiftUI render tree, cancels
            // TimelineView subscriptions, and forces a new @ObservedObject binding
            // cycle. Instead, update currentRecorder (above) and just re-front the window.
            if let dm = dictationManager {
                currentRecorder = dm.recorder
            }
            w.orderFront(nil)
            isVisible = true
            return
        }

        // Capture the real recorder now, or use the already-initialised placeholder.
        if let dm = dictationManager {
            currentRecorder = dm.recorder
        }

        // FIX: Pass `self` (the overlay) as the single source of truth. The SwiftUI
        // view will derive its recorder from overlay.currentRecorder. This way,
        // when the recorder changes, SwiftUI's normal @ObservedObject diffing handles
        // the update inside the existing live view tree — no NSHostingView rebuild needed.
        let hostingView = FirstMouseHostingView(rootView: OverlayView(overlay: self))

        // Window size is owned by us (restored pref + user drag-resize); the root
        // view has no fixed frame, so don't let intrinsic-size constraints fight
        // the resizable window.
        hostingView.sizingOptions = []

        let size = OverlaySize.parse(try? String(contentsOf: Paths.overlaySize, encoding: .utf8))
        let w = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .resizable],   // .resizable = invisible edge grips, no chrome
            backing: .buffered,
            defer: false
        )
        w.contentMinSize = NSSize(width: OverlaySize.minWidth, height: OverlaySize.minHeight)
        w.contentMaxSize = NSSize(width: OverlaySize.maxWidth, height: OverlaySize.maxHeight)
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.delegate = self
        // Smoked-glass dark instrument face: system HUD blur of whatever is behind
        // the window, tinted dark so the gold segments glow like a vintage analyzer.
        // Shaped via maskImage — mutating the effect view's own layer
        // (cornerRadius/masksToBounds) silently breaks the behind-window blur.
        let effect = NSVisualEffectView()
        effect.material = Self.faceplateMaterial()
        effectView = effect
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.faceplateMask()

        let tint = NSView()
        tint.wantsLayer = true
        // The faceplate follows the selected theme. It used to be a fixed smoked dark in both
        // appearances; since themes landed it takes the theme's page colour so the overlay
        // matches the rest of the app. Still translucent, so the blur behind it reads.
        tint.layer?.backgroundColor = Self.faceplateColor().cgColor
        tintView = tint

        tint.translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(tint)
        effect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: effect.topAnchor),
            tint.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        ])

        w.contentView = effect
        w.backgroundColor = .clear
        w.isOpaque = false
        // No system shadow: its rendering includes a faint light rim that reads as
        // a border around the dark faceplate in dark mode. The instrument sits flat.
        w.hasShadow = false

        // Position bottom-right of screen (margin holds regardless of restored width)
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - size.width - 20
            let y = screen.visibleFrame.minY + 20
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }

        w.orderFront(nil)
        self.window = w
        isVisible = true
        if analyzerStyle == .wave { applyWaveHeight() }
        mirrorTTSPlaybackState()
    }

    func hide() {
        try? "on".write(to: Paths.overlayHidden, atomically: true, encoding: .utf8)
        window?.close()
        window = nil
        isVisible = false
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        isVisible = false
    }

    /// Persist the user's drag-resize (borderless window: frame == content size).
    /// Free corner/edge resize is allowed on every style, including Wave — the grip
    /// only controls how many transcript lines show; the corners size the window.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        let size = OverlaySize(width: w.frame.width, height: w.frame.height)
        try? size.fileValue.write(to: Paths.overlaySize, atomically: true, encoding: .utf8)
    }

    /// Stretchable rounded-rect mask for the effect view — the sanctioned way to shape
    /// an NSVisualEffectView (touching its layer breaks the material). Cap insets on
    /// all four edges so the 10pt corners stay crisp at any drag-resized size.
    private static func faceplateMask() -> NSImage {
        let radius: CGFloat = 10
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Mirror the in-process playback state. Set up once and kept for the app's lifetime:
    /// an idle Combine subscription costs nothing, where the timer it replaced woke the
    /// main thread 3.3x/second from launch for the life of the process.
    private func mirrorTTSPlaybackState() {
        guard ttsStateCancellable == nil else { return }
        ttsStateCancellable = TTSPlaybackState.shared.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self, self.isTTSPlaying != playing else { return }
                self.isTTSPlaying = playing
            }
    }

    // MARK: - Status mirroring

    /// Subscribe to the managers' published state so the overlay headline stays in sync.
    private func wireStatus() {
        statusCancellables.removeAll()
        // Recompute on the next main-loop tick so the @Published value has settled
        // (sinks fire on willSet, i.e. before the new value is stored).
        let recompute: () -> Void = { [weak self] in
            DispatchQueue.main.async { self?.recomputeStatus() }
        }
        if let dm = dictationManager {
            dm.$sttModelReady.sink { _ in recompute() }.store(in: &statusCancellables)
            dm.$sttFailed.sink { _ in recompute() }.store(in: &statusCancellables)
            dm.$sttStatus.sink { _ in recompute() }.store(in: &statusCancellables)
            // Feed the Wave-style transcript rows (the 1.6.0 pane). Memory-bounded.
            dm.$lastTranscription
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] text in
                    guard let self, !text.isEmpty else { return }
                    self.nextLineId += 1
                    self.lines.append(Line(id: self.nextLineId, text: text))
                    if self.lines.count > 50 { self.lines = Array(self.lines.suffix(50)) }
                }
                .store(in: &statusCancellables)
        }
        if let sm = setupManager {
            sm.$state.sink { _ in recompute() }.store(in: &statusCancellables)
        }
        recomputeStatus()
    }

    /// Priority: STT failure (dictation-blocking) > STT still loading > setup failure > ready.
    private func recomputeStatus() {
        if let dm = dictationManager {
            if dm.sttFailed {
                statusText = dm.sttStatus ?? "Speech model failed to load."
                statusIsError = true
                return
            }
            if !dm.sttModelReady {
                statusText = dm.sttStatus ?? "Loading speech model…"
                statusIsError = false
                return
            }
        }
        if let sm = setupManager, case .failed(let reason) = sm.state {
            statusText = reason
            statusIsError = true
            return
        }
        statusText = nil
        statusIsError = false
    }
}

// MARK: - Overlay View

struct OverlayView: View {
    /// FIX: Observe the overlay as the single source of truth. The overlay's
    /// @Published currentRecorder is how we get the live recorder reference.
    /// We do NOT take recorder as a direct init parameter anymore — doing so
    /// would freeze the reference at the moment NSHostingView was constructed.
    @ObservedObject var overlay: TranscriptionOverlay
    @State private var copiedLineId: Int? = nil
    @State private var overlayHovered = false
    @State private var dragStartLines: Int? = nil

    /// Vertical drag distance (pts) that steps the overlay by one transcript line.
    private static let lineStep: CGFloat = 27

    var body: some View {
        let recorder = overlay.currentRecorder
        Group {
            if overlay.analyzerStyle == .wave {
                waveLayout(recorder: recorder)
            } else {
                analyzerLayout(recorder: recorder)
            }
        }
        // Wave (the 1.6.0 default) sits on a solid cream panel like the original;
        // LED Bars / Graph / Curtain stay transparent so the dark HUD blur shows through.
        .background(overlay.analyzerStyle == .wave ? OWColor.page.opacity(0.98) : Color.clear)
    }

    // LED Bars / Graph / Curtain — edge-to-edge, marquee/bands driven.
    private func analyzerLayout(recorder: AudioRecorder) -> some View {
        ZStack(alignment: .bottom) {
            WaveformBar(recorder: recorder, isTTSPlaying: overlay.isTTSPlaying, statusIsError: overlay.statusIsError, statusText: overlay.statusText, style: overlay.analyzerStyle, pttKeyLabel: overlay.pttKeyLabel, interactionMode: overlay.interactionMode)
            if overlay.interactionMode == .handsFree {
                SilenceProgressBar(recorder: recorder)
                    .frame(height: 1.5)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 3)
            }
        }
    }

    // The 1.6.0 Wave layout: wave + status dot, optional transcript lines, resize grip.
    private func waveLayout(recorder: AudioRecorder) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WaveformBar(recorder: recorder, isTTSPlaying: overlay.isTTSPlaying, statusIsError: overlay.statusIsError, statusText: overlay.statusText, style: .wave, pttKeyLabel: overlay.pttKeyLabel, interactionMode: overlay.interactionMode)
                .frame(height: 44)

            if overlay.interactionMode == .handsFree {
                SilenceProgressBar(recorder: recorder).frame(height: 1.5).padding(.horizontal, 4)
            }

            if overlay.transcriptLines > 0, !overlay.lines.isEmpty {
                dottedDivider
                VStack(alignment: .leading, spacing: 3) {
                    let visible = Array(overlay.lines.reversed().prefix(overlay.transcriptLines))
                    ForEach(visible) { line in
                        OverlayLineRow(line: line, isCopied: copiedLineId == line.id) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(line.text, forType: .string)
                            withAnimation(.easeIn(duration: 0.1)) { copiedLineId = line.id }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if copiedLineId == line.id { copiedLineId = nil }
                                }
                            }
                        }
                    }
                }
            }

            // Hover-revealed resize grip — drag to step 0…3 transcript lines.
            if overlayHovered || dragStartLines != nil {
                HStack {
                    Spacer()
                    Capsule().fill(OWColor.inkFaint).frame(width: 26, height: 4)
                    Spacer()
                }
                .frame(height: 9)
                .contentShape(Rectangle())
                .gesture(gripDrag)
                .onHover { inside in
                    // NSCursor.set() is idempotent (no push/pop stack to leak if the
                    // grip fades out mid-hover without a final onHover(false)).
                    if inside { overlay.setWindowMovable(false); NSCursor.resizeUpDown.set() }
                    else { if dragStartLines == nil { overlay.setWindowMovable(true); NSCursor.arrow.set() } }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.12)) { overlayHovered = hovering } }
    }

    private var dottedDivider: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [1.5, 3]))
            .foregroundColor(OWColor.line)
        }
        .frame(height: 1)
        .padding(.vertical, 2)
    }

    private var gripDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStartLines ?? overlay.transcriptLines
                if dragStartLines == nil { dragStartLines = start; overlay.isGripDragging = true }
                let delta = Int((value.translation.height / Self.lineStep).rounded())
                let next = TranscriptionOverlay.clampLines(start + delta)
                if next != overlay.transcriptLines { overlay.transcriptLines = next }
            }
            .onEnded { _ in
                dragStartLines = nil
                overlay.isGripDragging = false
                overlay.persistTranscriptLines()
                overlay.setWindowMovable(true)
            }
    }
}

// MARK: - Overlay Line Row (Wave transcript pane)

struct OverlayLineRow: View {
    let line: TranscriptionOverlay.Line
    let isCopied: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 4) {
                Text(line.text)
                    .font(.custom("Outfit", size: 11))
                    .foregroundColor(isCopied ? OWColor.accent : OWColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(OWColor.accent)
                } else if isHovered {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 8))
                        .foregroundColor(OWColor.inkSoft)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isHovered ? OWColor.pillFill.opacity(0.5) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
            // Idempotent set() (not push/pop) — rows are evicted from the visible
            // window as new transcriptions arrive, which can drop the hover-exit.
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

// MARK: - Waveform Bar

struct WaveformBar: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject private var playbackMeter = PlaybackLevelMeter.shared
    var isTTSPlaying: Bool = false
    /// Paints the dot danger-red while model status is failed (the words live in the menu).
    var statusIsError: Bool = false
    /// Non-nil while a status word ("Loading…"/error) should take over the grid as a marquee.
    var statusText: String? = nil
    /// Active analyzer style — which renderer fills the display area.
    var style: OverlayStyle = .defaultStyle
    var pttKeyLabel: String = "Ctrl"
    var interactionMode: InteractionMode = .pressToTalk

    var body: some View {
        // Analyzer display — one of the selectable styles (SpectrumStyles.swift).
        // A status word takes over the area as a scrolling LED marquee when present.
        // (The REC lamp retired 2026-07-17: the live mic spectrum itself is the
        // recording indication.)
        Group {
            if style == .wave {
                // The 1.6.0 look (default): mirrored-line waveform + status dot. It owns
                // its own status/idle presentation, so it bypasses the LED marquee path.
                WaveStyleView(recorder: recorder, isTTSPlaying: isTTSPlaying,
                              statusText: statusText, statusIsError: statusIsError,
                              pttKeyLabel: pttKeyLabel, interactionMode: interactionMode)
            } else if statusText != nil {
                marquee(word: statusIsError ? "ERROR" : "LOADING", color: statusIsError ? OWColor.danger : OWColor.accent)
            } else {
                let live = (isTTSPlaying && recorder.state == .idle)
                    ? playbackMeter.spectrumBands : recorder.spectrumBands
                // Idle (all-zero bands) renders a blank, paused canvas — the
                // overlay stays quiet when nothing is happening (Hakan's call,
                // 2026-07-20, reversing 90cc1ac's STANDBY marquee).
                let bands = live.isEmpty
                    ? [Float](repeating: 0, count: SpectrumBands.bandCount) : live
                switch style {
                case .wave: EmptyView()   // handled above
                case .ledBars: LEDBarsStyleView(bands: bands)
                case .graph: GraphStyleView(bands: bands)
                case .curtain: CurtainStyleView(bands: bands)
                }
            }
        }
    }

    // MARK: - Status Marquee

    /// Marquee window width in dot-matrix cell columns — its own constant now
    /// (the old code borrowed the vintage spectrum's band count).
    private static let marqueeColumns = 24

    /// LED marquee: scrolls the status word across the cell grid, right to left,
    /// with a full blank grid-width lead-in/out. ~8 columns/second.
    @ViewBuilder
    private func marquee(word: String, color: Color) -> some View {
        let columns = DotMatrix.columns(for: word)
        TimelineView(.periodic(from: .now, by: 0.12)) { timeline in
            let gridWidth = Self.marqueeColumns
            let cycle = columns.count + gridWidth
            let step = Int(timeline.date.timeIntervalSinceReferenceDate / 0.12) % cycle
            let window: [[Bool]] = (0..<gridWidth).map { cell in
                let index = step - gridWidth + cell
                return (index >= 0 && index < columns.count)
                    ? columns[index]
                    : Array(repeating: false, count: DotMatrix.rows)
            }
            matrix(window: window, color: color)
        }
    }

    /// Renders a cell-column window of 7-row dot-matrix cells: lit dots bloom,
    /// unlit cells stay transparent (the vintage ghost sockets retired with the
    /// gold grid, keeping the marquee style-agnostic).
    private func matrix(window: [[Bool]], color: Color) -> some View {
        GeometryReader { geo in
            let columnWidth = geo.size.width / CGFloat(window.count)
            let segmentHeight = (geo.size.height - CGFloat(DotMatrix.rows - 1) * 2) / CGFloat(DotMatrix.rows)
            HStack(spacing: 0) {
                ForEach(0..<window.count, id: \.self) { columnIndex in
                    VStack(spacing: 2) {
                        ForEach(0..<DotMatrix.rows, id: \.self) { row in
                            let isLit = window[columnIndex][row]
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(isLit ? color : Color.clear)
                                .shadow(color: isLit ? color.opacity(0.7) : .clear, radius: 2.5)
                                .frame(height: segmentHeight)
                        }
                    }
                    .frame(width: max(columnWidth - 4, 1))
                    .padding(.horizontal, 2)
                }
            }
        }
        .clipped()
    }

}

// MARK: - Wave Style (the 1.6.0 default)

/// The pre-1.10 overlay renderer: a status dot + label over a mirrored-line waveform
/// driven by `recorder.levelHistory` (recording) or a synthesized sine (TTS playback).
/// Ported verbatim from the 1.6.0 `WaveformBar` so the beloved original look is a
/// selectable style again — and the default.
struct WaveStyleView: View {
    @ObservedObject var recorder: AudioRecorder
    var isTTSPlaying: Bool = false
    /// Model-loading/error status from the overlay; takes over the label when present.
    var statusText: String? = nil
    var statusIsError: Bool = false
    var pttKeyLabel: String = "Ctrl"
    var interactionMode: InteractionMode = .pressToTalk

    // Computed, NOT `static let`. Swift evaluates a `static let` once per process and caches it
    // forever, which was correct while `OWColor`'s tokens were themselves constants. Now that
    // they follow the selected theme, a cached gradient would freeze the palette at whichever
    // theme happened to be active when the overlay first drew — the bars would stay gold after
    // switching to Dark or Sky, until relaunch.
    // Colour stops, not `LinearGradient`s: the bars are drawn in a `Canvas` now, which takes
    // a `Shading`. Still computed `var`s — a `static let` caches once per process and would
    // freeze the palette at launch, the trap these three gradients fell into before.
    private static var waveColors: [Color] {
        [OWColor.accent.opacity(0.55), OWColor.accent, OWColor.accentDeep]
    }
    private static var idleColors: [Color] {
        [OWColor.inkFaint, OWColor.inkSoft, OWColor.inkFaint]
    }
    private static var listeningColors: [Color] {
        [OWColor.accent, OWColor.accentDeep, OWColor.accent]
    }

    /// Left-to-right shading across `width`, matching the old `.leading`/`.trailing` gradients.
    private static func shading(_ colors: [Color], width: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors),
                        startPoint: .zero, endPoint: CGPoint(x: width, y: 0))
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                // Skipped entirely when empty (idle): an empty Text still occupies a layout
                // slot, so it would consume a second HStack gap for nothing.
                if !label.isEmpty {
                    Text(label)
                        .font(.custom("Outfit", size: 10))
                        .foregroundColor(dotColor)
                }
                Spacer()
                if statusText == nil, recorder.state == .recording {
                    Text(recordingHint)
                        .font(.custom("Outfit", size: 9))
                        .foregroundColor(.secondary)
                }
            }

            // `Canvas`, not `Shape.fill`. Both branches redraw constantly — the speaking
            // animation at 33 fps for the whole reply, the recording wave on every
            // `levelHistory` publish (~90/s) — and a Shape rebuilds a 50-bar `Path` *and* a
            // fresh view identity to diff on every one of those frames. Measured 2026-09-06:
            // while a reply played, the app used ~14.9% of a core with the overlay visible
            // and 4.1% with it hidden, so this view was ~11 points — roughly three quarters
            // of the total, and an order of magnitude more than the analyzer filterbank.
            // The spectrum styles in SpectrumStyles.swift already draw this way.
            if isTTSPlaying && recorder.state == .idle {
                TimelineView(.animation(minimumInterval: Self.speakingFrameInterval)) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let levels = Self.ttsLevels(count: 50, time: time)
                        context.fill(Self.mirroredLines(levels: levels, size: size),
                                     with: Self.shading(Self.waveColors, width: size.width))
                    }
                }
            } else {
                Canvas { context, size in
                    context.opacity = recorder.state == .uploading ? 0.5
                        : recorder.state == .idle ? 0.4 : 1.0
                    let colors: [Color]
                    switch recorder.state {
                    case .recording: colors = Self.waveColors
                    case .listening: colors = Self.listeningColors
                    default: colors = Self.idleColors
                    }
                    context.fill(
                        Self.mirroredLines(levels: recorder.levelHistory.map { CGFloat($0) }, size: size),
                        with: Self.shading(colors, width: size.width))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var recordingHint: String {
        switch interactionMode {
        case .holdToTalk: return "Release \(pttKeyLabel) to stop"
        case .handsFree: return "silence submits"
        case .pressToTalk: return "Press \(pttKeyLabel) to stop"
        }
    }

    private var dotColor: Color {
        if statusText != nil { return statusIsError ? OWColor.danger : OWColor.warn }
        if isTTSPlaying && recorder.state == .idle { return OWColor.accent }
        switch recorder.state {
        case .recording: return OWColor.recording
        case .uploading: return OWColor.warn
        case .listening: return OWColor.accentDeep
        case .idle: return OWColor.live
        }
    }

    private var label: String {
        if let statusText { return statusText }
        if isTTSPlaying && recorder.state == .idle { return "Speaking..." }
        switch recorder.state {
        case .recording: return "Recording..."
        case .uploading: return "Transcribing..."
        case .listening: return "Listening..."
        // Idle is the resting state — the dot alone carries it, so no word is shown.
        case .idle: return ""
        }
    }

    /// Vertical bars mirrored around the center line, tapered at the edges.
    private static func mirroredLines(levels: [CGFloat], size: CGSize) -> Path {
        guard !levels.isEmpty else { return Path() }
        let n = levels.count
        let barWidth: CGFloat = 2
        let gap: CGFloat = max(1, (size.width - barWidth * CGFloat(n)) / CGFloat(max(n - 1, 1)))
        let step = barWidth + gap
        let midY = size.height / 2
        let maxHalf = midY - 1
        var path = Path()
        for (i, level) in levels.enumerated() {
            let t = CGFloat(i) / CGFloat(max(n - 1, 1))
            let taper = min(t * 5, (1 - t) * 5, 1.0)
            let h = max(1, level * taper * maxHalf)
            let x = CGFloat(i) * step
            path.addRoundedRect(in: CGRect(x: x, y: midY - h, width: barWidth, height: h * 2),
                                cornerSize: CGSize(width: 1, height: 1))
        }
        return path
    }

    /// Redraw interval for the speaking animation. `TimelineView(.animation)` quantises to the
    /// display refresh, so on a 60 Hz panel this is every third frame — 20 fps. The wave is a
    /// decorative sine blend, not a reading of the audio, and the redraw rate is what this view
    /// costs: it is drawn over the overlay's blur material, so every frame recomposites the
    /// window. 0.03 (30 fps) measured ~10 points of a core while speaking; the difference at
    /// 20 fps is not visible on a smooth wave.
    private static let speakingFrameInterval: Double = 0.05

    /// Sine-blended levels for the TTS "speaking" animation.
    private static func ttsLevels(count: Int, time: Double) -> [CGFloat] {
        (0..<count).map { i in
            let t = Double(i) / Double(max(count - 1, 1))
            let w1 = sin(time * 3.0 + t * .pi * 4) * 0.35
            let w2 = sin(time * 1.8 + t * .pi * 2.5) * 0.25
            let w3 = sin(time * 5.0 + t * .pi * 7) * 0.1
            return CGFloat(max(0.05, (w1 + w2 + w3 + 0.5) * 0.8))
        }
    }
}

// MARK: - Silence Progress Bar

struct SilenceProgressBar: View {
    @ObservedObject var recorder: AudioRecorder

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            GeometryReader { geo in
                let progress = silenceProgress(at: timeline.date)
                ZStack(alignment: .leading) {
                    // Track (always visible)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OWColor.line)
                    // Fill — gold reads as "completing a valuable action" (auto-submit countdown)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OWColor.accent)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
        }
    }

    private func silenceProgress(at now: Date) -> CGFloat {
        // Only show fill during active recording (not listening/idle)
        guard recorder.state == .recording,
              let start = recorder.silenceStart,
              recorder.silenceThresholdSeconds > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return CGFloat(min(max(elapsed / recorder.silenceThresholdSeconds, 0), 1))
    }
}
