import Foundation

/// Size-capping for the append-only `paste_debug.log` diagnostic file.
///
/// The log records a couple of lines per dictation and was never rotated, so it grew for the
/// life of an install (210 KB observed). This is the pure half — deciding *what bytes to keep*
/// — so it can be tested under Command Line Tools; `DictationManager` owns the file I/O.
public enum DiagLogTrim {
    /// Bytes to rewrite the log with once it exceeds `maxBytes`, or `nil` while it still fits.
    ///
    /// Keeps the most recent `maxBytes / 2` bytes and resumes just after the first newline in
    /// that tail, so the oldest kept entry is a whole line. Best effort by design: a tail with
    /// no newline, or whose only newline is its final byte, is kept whole rather than emptied
    /// — a leading partial line is a better outcome for a debug log than truncating it to zero.
    public static func trimmed(_ data: Data, maxBytes: Int) -> Data? {
        guard maxBytes > 0, data.count > maxBytes else { return nil }
        let tail = data.suffix(maxBytes / 2)
        guard let newline = tail.firstIndex(of: UInt8(ascii: "\n")) else { return Data(tail) }
        let start = tail.index(after: newline)
        guard start < tail.endIndex else { return Data(tail) }
        return Data(tail[start...])
    }
}
