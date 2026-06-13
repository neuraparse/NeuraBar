import Foundation
import AppKit
import CryptoKit
import UniformTypeIdentifiers
import ImageIO
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
        // Only persist real, decodable images. A dropped .txt/.zip/.pdf must
        // not land in notes-images/ mislabeled as .png. Detecting the type
        // from the bytes also gives the *true* extension so a GIF/JPEG isn't
        // silently relabeled .png (preferredExtension is kept only for source
        // compatibility — detection is authoritative).
        guard let ext = imageExtension(for: data) else { return nil }
        let hash = SHA256.hash(data: data).hex
        let name = "\(hash).\(ext)"
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
    /// return the markdown reference. Memory-maps the source so hashing a
    /// large file doesn't pull the whole thing into RAM.
    @discardableResult
    static func store(sourceURL: URL) -> String? {
        guard let data = try? Data(contentsOf: sourceURL, options: .mappedIfSafe) else { return nil }
        return store(data: data)
    }

    /// Detect the on-disk image type from raw bytes. Returns nil for
    /// non-images so callers can reject junk. Validates decodability via
    /// ImageIO rather than trusting a filename.
    static func imageExtension(for data: Data) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(src),
              let ext = UTType(uti as String)?.preferredFilenameExtension else { return nil }
        return normalizedExtension(ext)
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

        // Tokens in note bodies can be bare filenames, absolute paths, or
        // file:// URLs — normalize every referenced token down to its
        // filename before comparing, or a still-referenced image stored via an
        // absolute-path token would be deleted as a false orphan.
        let referencedNames = Set(referencedTokens.map { token -> String in
            if token.hasPrefix("file://"), let u = URL(string: token) { return u.lastPathComponent }
            return URL(fileURLWithPath: token).lastPathComponent
        })
        var removed = 0
        for url in contents {
            let name = url.lastPathComponent
            if !referencedNames.contains(name) {
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

// MARK: - Downsampled thumbnail cache

/// Decodes downsampled thumbnails (never the full bitmap) off the main thread
/// and memoizes them by token. A 6000×4000 PNG used to be decoded to its full
/// ~96MB pixel buffer on the main thread on *every* preview render; this caps
/// the longest edge and caches the result (content-addressed names make the
/// token a safe cache key).
enum NoteImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 80
        return c
    }()

    static func cached(_ token: String) -> NSImage? {
        cache.object(forKey: token as NSString)
    }

    static func makeThumbnail(url: URL, maxPixel: Int = 1400) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: url.lastPathComponent as NSString)
        return img
    }

    static func store(_ image: NSImage, for token: String) {
        cache.setObject(image, forKey: token as NSString)
    }
}

// MARK: - Rendered image view

struct NoteImageView: View {
    let token: String
    let alt: String

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                VStack(alignment: .leading, spacing: 2) {
                    Image(nsImage: image)
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
            } else if failed {
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
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: 80)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: token) { await load() }
    }

    private func load() async {
        if let cached = NoteImageCache.cached(token) {
            image = cached
            return
        }
        guard let url = NoteAttachments.resolve(token: token) else {
            failed = true
            return
        }
        let decoded = await Task.detached(priority: .userInitiated) {
            NoteImageCache.makeThumbnail(url: url)
        }.value
        if let decoded {
            NoteImageCache.store(decoded, for: token)
            image = decoded
        } else {
            failed = true
        }
    }
}
