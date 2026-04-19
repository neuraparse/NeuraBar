import Foundation
import AppKit
import CryptoKit
import UniformTypeIdentifiers
import SwiftUI

/// On-disk image storage for notes. Images live in
/// `<supportDir>/notes-images/` with content-addressed filenames (SHA-256
/// of the bytes) so identical images shared between notes take no extra
/// space and the filename doubles as a dedupe key.
enum NoteAttachments {

    /// Base directory for all image attachments. Created on first use.
    static var baseDir: URL {
        let url = Persistence.supportDir.appendingPathComponent("notes-images", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Store raw image data, returning the markdown reference the editor
    /// should insert into the note body. Filenames are the SHA-256 hash so
    /// the same image dropped twice only takes space once.
    @discardableResult
    static func store(data: Data, preferredExtension: String = "png") -> String? {
        let hash = SHA256.hash(data: data).hex
        let name = "\(hash).\(normalizedExtension(preferredExtension))"
        let url = baseDir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                return nil
            }
        }
        return markdown(for: name)
    }

    /// Copy an image URL (e.g. dragged from Finder) into the store and
    /// return the markdown reference.
    @discardableResult
    static func store(sourceURL: URL) -> String? {
        guard let data = try? Data(contentsOf: sourceURL) else { return nil }
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        return store(data: data, preferredExtension: ext)
    }

    /// Resolve a markdown `![](path-or-name)` token to an actual file URL.
    /// Handles:
    ///   - Bare filenames (e.g. `abc123.png`) — relative to notes-images
    ///   - `file://` absolute URLs
    ///   - Absolute file paths
    static func resolve(token: String) -> URL? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("file://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        let candidate = baseDir.appendingPathComponent(trimmed)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Delete any attachment files that aren't referenced by any note body.
    /// Returns the number removed — exposed for tests.
    @discardableResult
    static func pruneOrphans(referencedTokens: Set<String>) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseDir.path) else { return 0 }
        guard let contents = try? fm.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: nil
        ) else { return 0 }

        var removed = 0
        for url in contents {
            let name = url.lastPathComponent
            if !referencedTokens.contains(name) {
                try? fm.removeItem(at: url)
                removed += 1
            }
        }
        return removed
    }

    /// Produce the markdown reference we embed in note bodies. Uses a bare
    /// filename so the reference survives moving the notes directory (iCloud
    /// → Google Drive etc.) — resolution is always relative to
    /// `NoteAttachments.baseDir`.
    static func markdown(for filename: String) -> String {
        "![image](\(filename))"
    }

    /// Strip the markdown reference form back to a filename / URL token.
    /// Pure — exposed for tests.
    static func extractTokens(from body: String) -> [String] {
        let pattern = #"!\[[^\]]*\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        var out: [String] = []
        regex.enumerateMatches(in: body, options: [], range: range) { match, _, _ in
            if let m = match, let r = Range(m.range(at: 1), in: body) {
                out.append(String(body[r]))
            }
        }
        return out
    }

    private static func normalizedExtension(_ raw: String) -> String {
        let lower = raw.lowercased()
        // Accept only formats AppKit/SwiftUI can cleanly decode.
        let allowed: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"]
        return allowed.contains(lower) ? lower : "png"
    }
}

private extension SHA256.Digest {
    /// Hex string representation of the SHA-256 digest.
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Body parsing for preview

/// Breaks a markdown body into alternating text and image nodes so the
/// preview pane can render images inline. Pure — exposed for tests.
enum NoteBlock: Equatable {
    case text(String)        // plain markdown (Text(AttributedString(markdown:)) handles inlines)
    case image(token: String, alt: String)
}

enum NoteBodyParser {
    /// Split a body string into ordered NoteBlock nodes.
    static func parse(_ body: String) -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        let pattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(body)]
        }
        let nsBody = body as NSString
        let full = NSRange(location: 0, length: nsBody.length)
        var cursor = 0
        regex.enumerateMatches(in: body, options: [], range: full) { match, _, _ in
            guard let m = match else { return }
            if m.range.location > cursor {
                let r = NSRange(location: cursor, length: m.range.location - cursor)
                let text = nsBody.substring(with: r)
                if !text.isEmpty { blocks.append(.text(text)) }
            }
            let alt = nsBody.substring(with: m.range(at: 1))
            let token = nsBody.substring(with: m.range(at: 2))
            blocks.append(.image(token: token, alt: alt))
            cursor = m.range.location + m.range.length
        }
        if cursor < nsBody.length {
            let r = NSRange(location: cursor, length: nsBody.length - cursor)
            let text = nsBody.substring(with: r)
            if !text.isEmpty { blocks.append(.text(text)) }
        }
        return blocks
    }
}

// MARK: - Rendered image view

struct NoteImageView: View {
    let token: String
    let alt: String

    var body: some View {
        if let url = NoteAttachments.resolve(token: token),
           let nsImage = NSImage(contentsOf: url) {
            VStack(alignment: .leading, spacing: 2) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                if !alt.isEmpty {
                    Text(alt)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text(alt.isEmpty ? token : alt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.orange.opacity(0.1))
            )
        }
    }
}
