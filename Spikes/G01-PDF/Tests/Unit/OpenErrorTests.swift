import PDFAnchorKit
import PDFKit
import XCTest

/// Records every unlock attempt. Sylvia must never make one (plan 9.2: no password prompt, no bypass).
final class UnlockSpyDocument: OverlayPDFDocument {
    nonisolated(unsafe) static var unlockAttempts = 0

    override func unlock(withPassword password: String) -> Bool {
        UnlockSpyDocument.unlockAttempts += 1
        return super.unlock(withPassword: password)
    }
}

/// T12 (PDF half): truncated and protected PDFs produce specific errors, no unlock attempt and no crash.
@MainActor
final class OpenErrorTests: XCTestCase {
    var log: [String] = []

    override func setUp() {
        super.setUp()
        UnlockSpyDocument.unlockAttempts = 0
    }

    func openError(_ url: URL, spy: Bool = false) -> PDFOpenError? {
        do {
            _ = try PDFSourceDocument.open(url: url, makeDocument: { spy ? UnlockSpyDocument(url: $0) : OverlayPDFDocument(url: $0) })
            return nil
        } catch {
            return error
        }
    }

    func testPasswordProtectedPDFIsRejectedWithoutUnlockAttempt() {
        XCTAssertEqual(openError(Fixture.url("encrypted-user-password.pdf"), spy: true), .passwordProtected)
        XCTAssertEqual(UnlockSpyDocument.unlockAttempts, 0, "Sylvia must not call unlock(withPassword:)")
        // The spy really observes unlock calls (control): calling it directly is counted.
        let control = UnlockSpyDocument(url: Fixture.url("encrypted-user-password.pdf"))!
        XCTAssertTrue(control.isLocked)
        XCTAssertFalse(control.unlock(withPassword: "wrong"))
        XCTAssertEqual(UnlockSpyDocument.unlockAttempts, 1)
        XCTAssertTrue(control.isLocked)
    }

    func testOwnerPasswordOnlyPDFOpensButTextIsRestricted() throws {
        let source = try PDFSourceDocument.open(url: Fixture.url("encrypted-owner-only-nocopy.pdf"), makeDocument: { UnlockSpyDocument(url: $0) })
        XCTAssertEqual(UnlockSpyDocument.unlockAttempts, 0)
        XCTAssertTrue(source.permissions.isEncrypted)
        XCTAssertFalse(source.permissions.allowsCopying)
        let extraction = PageTextExtractor.extract(source)
        XCTAssertEqual(extraction.pages.map(\.status), [.restrictedByPermissions])
        XCTAssertNil(extraction.pages[0].text)
        XCTAssertNil(extraction.pages[0].textForAIContext)
        // PDFKit itself does not enforce the copy restriction: it still returns the page text and selections.
        let page = try XCTUnwrap(source.page(at: 0))
        XCTAssertNotNil(page.string, "observation: PDFKit returns text even when copying is not permitted")
        let selection = try XCTUnwrap(page.selection(for: NSRange(location: 10, length: 20)))
        XCTAssertThrowsError(try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction)) { error in
            XCTAssertEqual(error as? AnchorCaptureError, .textRestricted)
        }
    }

    func testTruncatedPDFIsASpecificParseError() {
        XCTAssertEqual(openError(Fixture.url("truncated.pdf")), .truncated)
        // Observation: PDFKit alone also refuses this file (returns nil), but without saying why.
        XCTAssertNil(PDFDocument(url: Fixture.url("truncated.pdf")))
    }

    func testEveryTruncationPointGivesASpecificErrorAndNoCrash() throws {
        let full = try Data(contentsOf: Fixture.url("labels-multipage.pdf"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g01-trunc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var rows = ["percent bytes sylvia_error pdfkit_alone"]
        var errors: Set<String> = []
        for percent in stride(from: 0, through: 99, by: 3) {
            let cut = full.prefix(full.count * percent / 100)
            let url = dir.appendingPathComponent("cut-\(percent).pdf")
            try cut.write(to: url)
            let error = openError(url)
            XCTAssertNotNil(error, "a file cut at \(percent) % must not open")
            XCTAssertTrue(error == .truncated || error == .notAPDF, "cut at \(percent) %: \(String(describing: error))")
            errors.insert(String(describing: error))
            let pdfkit = PDFDocument(url: url).map { "opened, \($0.pageCount) pages" } ?? "nil"
            rows.append("\(percent) \(cut.count) \(error.map { String(describing: $0) } ?? "opened") \(pdfkit)")
        }
        // The complete file still opens.
        XCTAssertNil(openError(Fixture.url("labels-multipage.pdf")))
        log.append(contentsOf: rows)
        Evidence.write("t12-truncation-sweep.txt", "T12 truncation sweep, \(Evidence.environmentLabel)\n" + rows.joined(separator: "\n") + "\n")
    }

    func testRepeatedOpenOfBadFilesDoesNotCrashOrLoop() {
        for _ in 0..<25 {
            XCTAssertEqual(openError(Fixture.url("truncated.pdf")), .truncated)
            XCTAssertEqual(openError(Fixture.url("encrypted-user-password.pdf")), .passwordProtected)
        }
    }

    func testNotAPDFEmptyMissingAndUnparseable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g01-bad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = dir.appendingPathComponent("notes.pdf")
        try Data("These are not PDF bytes.\n".utf8).write(to: text)
        XCTAssertEqual(openError(text), .notAPDF)
        let empty = dir.appendingPathComponent("empty.pdf")
        try Data().write(to: empty)
        XCTAssertEqual(openError(empty), .notAPDF)
        XCTAssertEqual(openError(dir.appendingPathComponent("missing.pdf")), .fileUnreadable)
        let garbage = dir.appendingPathComponent("garbage.pdf")
        try Data("%PDF-1.7\n1 0 obj\n<< /Type /Nonsense >>\nendobj\nthis is not a cross-reference table\n%%EOF\n".utf8).write(to: garbage)
        XCTAssertEqual(openError(garbage), .unparseable)
    }

    func testErrorSummaryEvidence() {
        var lines = ["T12 error mapping, \(Evidence.environmentLabel)"]
        for name in ["encrypted-user-password.pdf", "encrypted-owner-only-nocopy.pdf", "truncated.pdf", "labels-multipage.pdf"] {
            UnlockSpyDocument.unlockAttempts = 0
            let error = openError(Fixture.url(name), spy: true)
            lines.append("\(name): \(error.map { "error \($0)" } ?? "opened"); unlock attempts \(UnlockSpyDocument.unlockAttempts)")
            XCTAssertEqual(UnlockSpyDocument.unlockAttempts, 0)
        }
        Evidence.write("t12-open-errors.txt", lines.joined(separator: "\n") + "\n")
    }
}
