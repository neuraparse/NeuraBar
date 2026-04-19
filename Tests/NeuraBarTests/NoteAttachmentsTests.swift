import XCTest
import AppKit
@testable import NeuraBar

/// Covers the image-attachment pipeline: content-addressed storage, dedup
/// via SHA-256, resolver, and the body parser that splits text + image
/// blocks for the preview renderer.
final class NoteAttachmentsTests: NBTestCase {

    // MARK: - Store + dedupe

    func testStoreCreatesFileAndReturnsMarkdownRef() throws {
        let png = Self.makePNG(size: NSSize(width: 4, height: 4))
        let ref = NoteAttachments.store(data: png, preferredExtension: "png")
        XCTAssertNotNil(ref)
        XCTAssertTrue(ref!.hasPrefix("![image]("))
        XCTAssertTrue(ref!.hasSuffix(".png)"))

        // File should exist on disk in the content-addressed location.
        let tokens = NoteAttachments.extractTokens(from: ref!)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertNotNil(NoteAttachments.resolve(token: tokens[0]))
    }

    func testStoreDeduplicatesIdenticalBytes() throws {
        let png = Self.makePNG(size: NSSize(width: 4, height: 4))
        let ref1 = NoteAttachments.store(data: png)
        let ref2 = NoteAttachments.store(data: png)
        XCTAssertEqual(ref1, ref2,
                       "Same bytes should resolve to the same content-hash filename")

        let tokens = NoteAttachments.extractTokens(from: ref1!)
        XCTAssertEqual(tokens.count, 1)
        // Only one file on disk — dedup worked.
        let contents = try FileManager.default.contentsOfDirectory(
            at: NoteAttachments.baseDir, includingPropertiesForKeys: nil
        )
        XCTAssertEqual(contents.count, 1)
    }

    func testNormalizeExtensionFiltersUnsupportedTypes() {
        let png = Self.makePNG(size: NSSize(width: 2, height: 2))
        let ref = NoteAttachments.store(data: png, preferredExtension: "exe")
        // Unsupported extensions collapse to "png" so the file is still
        // loadable as an image.
        XCTAssertTrue(ref?.hasSuffix(".png)") ?? false)
    }

    // MARK: - Resolve

    func testResolveBareFilenameHitsBaseDir() throws {
        let png = Self.makePNG(size: NSSize(width: 2, height: 2))
        let ref = NoteAttachments.store(data: png)!
        let token = NoteAttachments.extractTokens(from: ref).first!
        let url = NoteAttachments.resolve(token: token)
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.lastPathComponent, token)
    }

    func testResolveAbsolutePath() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-abs-\(UUID()).png")
        try? Data([0, 0]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = NoteAttachments.resolve(token: tmp.path)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.path, tmp.path)
    }

    func testResolveReturnsNilForMissing() {
        let url = NoteAttachments.resolve(token: "does-not-exist-\(UUID()).png")
        XCTAssertNil(url)
    }

    // MARK: - Extraction

    func testExtractTokensFromMixedBody() {
        let body = """
        Some text
        ![first](abc.png)
        more text
        ![](def.jpg) and ![alt](ghi.png) end
        """
        let tokens = NoteAttachments.extractTokens(from: body)
        XCTAssertEqual(tokens, ["abc.png", "def.jpg", "ghi.png"])
    }

    func testExtractTokensEmptyOnNoImages() {
        XCTAssertTrue(NoteAttachments.extractTokens(from: "Just text, no images").isEmpty)
    }

    // MARK: - Orphan pruning

    func testPruneOrphansRemovesUnreferencedFiles() throws {
        _ = NoteAttachments.store(data: Self.makePNG(size: NSSize(width: 2, height: 2)))
        let png2 = Self.makePNG(size: NSSize(width: 3, height: 3))
        let ref2 = NoteAttachments.store(data: png2)!
        let referenced = Set(NoteAttachments.extractTokens(from: ref2))

        let removed = NoteAttachments.pruneOrphans(referencedTokens: referenced)
        XCTAssertEqual(removed, 1)

        let contents = try FileManager.default.contentsOfDirectory(
            at: NoteAttachments.baseDir, includingPropertiesForKeys: nil
        )
        XCTAssertEqual(contents.count, 1)
    }

    // MARK: - Body parser

    func testBodyParserSplitsIntoTextAndImageBlocks() {
        let body = "Hello\n![alt](pic.png)\nWorld"
        let blocks = NoteBodyParser.parse(body)
        XCTAssertEqual(blocks.count, 3)
        guard case .text = blocks[0] else { return XCTFail("expected text") }
        guard case .image(let token, let alt) = blocks[1] else { return XCTFail("expected image") }
        XCTAssertEqual(token, "pic.png")
        XCTAssertEqual(alt, "alt")
        guard case .text = blocks[2] else { return XCTFail("expected text") }
    }

    func testBodyParserHandlesPureText() {
        let blocks = NoteBodyParser.parse("no images here")
        XCTAssertEqual(blocks, [.text("no images here")])
    }

    func testBodyParserHandlesPureImage() {
        let blocks = NoteBodyParser.parse("![cap](a.png)")
        XCTAssertEqual(blocks, [.image(token: "a.png", alt: "cap")])
    }

    func testBodyParserConsecutiveImages() {
        let body = "![a](x.png)\n![b](y.png)"
        let blocks = NoteBodyParser.parse(body)
        XCTAssertEqual(blocks.count, 3,
                       "Images separated by newline should produce image, newline-text, image")
        guard case .image = blocks[0] else { return XCTFail("expected image first") }
        guard case .image = blocks[2] else { return XCTFail("expected image last") }
    }

    // MARK: - Helpers

    private static func makePNG(size: NSSize) -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
    }
}
