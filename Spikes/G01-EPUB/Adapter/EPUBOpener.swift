import CryptoKit
import Foundation
import G01EPUBCore
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer

/// What the adapter adds on top of Readium when opening a file. `.readiumDefaults` turns every Sylvia control off so
/// the tests can record what Readium 3.11.0 does on its own.
public struct EPUBOpenOptions: Sendable {
    public var preflight = true
    public var sanitizeHTML = true
    public var rejectUnsupportedEncryption = true
    public var policy = ZIPPreflightPolicy()

    public init() {}

    public static let sylvia = EPUBOpenOptions()
    public static var readiumDefaults: EPUBOpenOptions {
        var o = EPUBOpenOptions()
        o.preflight = false
        o.sanitizeHTML = false
        o.rejectUnsupportedEncryption = false
        return o
    }
}

/// Counts what the HTML sanitizer did, across Readium's resource reads (which happen off the main actor).
public final class SanitizerStats: @unchecked Sendable {
    private let lock = NSLock()
    private var _documents = 0, _scripts = 0, _refreshes = 0, _handlers = 0, _scriptURLs = 0, _other = 0, _comments = 0
    private var _missingCSP = 0, _maxDepth = 0, _maxElements = 0, _slowest = 0.0
    private var _withheld: [String: PublicationHTMLSafety.Withheld] = [:]
    private var _details: [String: String] = [:]
    private var _nonHTMLChecked = 0

    func record(_ r: PublicationHTMLSafety.Result, href: String) {
        lock.lock(); defer { lock.unlock() }
        _documents += 1
        _scripts += r.removedScripts
        _refreshes += r.removedRefreshes
        _handlers += r.removedEventHandlers
        _scriptURLs += r.removedScriptURLs
        _other += r.removedOther
        _comments += r.droppedComments
        _maxDepth = max(_maxDepth, r.elementDepth)
        _maxElements = max(_maxElements, r.elementCount)
        _slowest = max(_slowest, r.seconds)
        if let reason = r.withheld { _withheld[href] = reason; _details[href] = r.detail }
        if !r.cspInjected { _missingCSP += 1 }
    }

    func recordNonHTML(_ r: PublicationHTMLSafety.NonHTMLResult, href: String) {
        lock.lock(); defer { lock.unlock() }
        _nonHTMLChecked += 1
        if let reason = r.withheld { _withheld[href] = reason; _details[href] = r.detail }
    }

    private var _treatments: [String: PublicationResourcePolicy.Treatment] = [:]
    private var _undeclared: Set<String> = []

    func recordTreatments(_ t: [String: PublicationResourcePolicy.Treatment]) {
        lock.lock(); defer { lock.unlock() }
        _treatments = t
    }

    func recordUndeclared(_ href: String) {
        lock.lock(); defer { lock.unlock() }
        _undeclared.insert(href)
    }

    func recordWithheldType(href: String) {
        lock.lock(); defer { lock.unlock() }
        _withheld[href] = .unsupportedType
        _details[href] = "served empty: its declared media type is missing, inconsistent or not one the reader serves"
    }

    /// How each declared href is served (`DeclaredResourceContainer`); empty when the adapter's container is off.
    public var treatments: [String: PublicationResourcePolicy.Treatment] { lock.lock(); defer { lock.unlock() }; return _treatments }
    /// Hrefs that were asked for (by the web view or by Readium) but that the manifest does not declare; none was served.
    public var undeclaredRequests: Set<String> { lock.lock(); defer { lock.unlock() }; return _undeclared }

    /// Non-HTML documents (SVG, XML and `+xml` resources) checked for active content.
    public var nonHTMLDocumentsChecked: Int { lock.lock(); defer { lock.unlock() }; return _nonHTMLChecked }
    /// Every resource served as a placeholder, with the reason (HTML and non-HTML).
    public var withheldReasons: [String: PublicationHTMLSafety.Withheld] { lock.lock(); defer { lock.unlock() }; return _withheld }
    /// Why each withheld resource failed (parser message or limit), for evidence.
    public var withheldDetails: [String: String] { lock.lock(); defer { lock.unlock() }; return _details }
    /// Non-HTML documents replaced because they contain active content.
    public var activeContentHrefs: Set<String> { Set(withheldReasons.filter { $0.value == .activeContent }.keys) }
    /// Resources replaced by a "cannot be shown" placeholder for any other reason (nesting, markup that is not XHTML
    /// Sylvia can read safely, time budget, failed verification).
    public var unavailableHrefs: Set<String> { Set(withheldReasons.filter { $0.value != .activeContent }.keys) }
    /// Deepest element nesting seen in the documents read so far (for a withheld document, where parsing stopped).
    public var maxElementDepth: Int { lock.lock(); defer { lock.unlock() }; return _maxDepth }
    public var maxElements: Int { lock.lock(); defer { lock.unlock() }; return _maxElements }
    /// Longest time spent sanitizing one document.
    public var slowestSeconds: Double { lock.lock(); defer { lock.unlock() }; return _slowest }

    public var documents: Int { lock.lock(); defer { lock.unlock() }; return _documents }
    public var removedScripts: Int { lock.lock(); defer { lock.unlock() }; return _scripts }
    public var removedRefreshes: Int { lock.lock(); defer { lock.unlock() }; return _refreshes }
    public var removedEventHandlers: Int { lock.lock(); defer { lock.unlock() }; return _handlers }
    public var removedScriptURLs: Int { lock.lock(); defer { lock.unlock() }; return _scriptURLs }
    public var removedOther: Int { lock.lock(); defer { lock.unlock() }; return _other }
    public var droppedComments: Int { lock.lock(); defer { lock.unlock() }; return _comments }
    /// Served HTML documents (including placeholders) in which a parser did not find the CSP first in head. Must be 0.
    public var documentsWithoutCSP: Int { lock.lock(); defer { lock.unlock() }; return _missingCSP }
}

public final class OpenedEPUB {
    public let publication: Publication
    public let fileURL: URL
    public let sha256: String
    public let preflight: ZIPPreflightReport?
    public let sanitizer: SanitizerStats
    public let options: EPUBOpenOptions
    public let openSeconds: Double

    init(publication: Publication, fileURL: URL, sha256: String, preflight: ZIPPreflightReport?, sanitizer: SanitizerStats, options: EPUBOpenOptions, openSeconds: Double) {
        self.publication = publication
        self.fileURL = fileURL
        self.sha256 = sha256
        self.preflight = preflight
        self.sanitizer = sanitizer
        self.options = options
        self.openSeconds = openSeconds
    }
}

public enum EPUBOpener {
    /// Font obfuscation algorithms (EPUB OCF): not DRM; Readium de-obfuscates these.
    public static let obfuscationAlgorithms: Set<String> = [
        "http://www.idpf.org/2008/embedding",
        "http://ns.adobe.com/pdf/enc#RC",
    ]

    public static func open(fileURL: URL, options: EPUBOpenOptions = .sylvia) async -> Result<OpenedEPUB, ReaderOpenError> {
        let clock = ContinuousClock()
        let start = clock.now

        // 1. A regular file that Sylvia owns (no directory assets, no symlinked file).
        guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true
        else { return .failure(.notARegularFile) }

        // 2. Archive preflight before anything is decompressed.
        var report: ZIPPreflightReport?
        if options.preflight {
            let r = ZIPPreflight.inspect(fileAt: fileURL, policy: options.policy)
            guard r.isAcceptable else { return .failure(.unsafeArchive(r.violations.map(\.code))) }
            report = r
        }

        // 3. Readium asset retrieval, file scheme only (no HTTP client is given to Readium).
        guard let file = FileURL(url: fileURL) else { return .failure(.notARegularFile) }
        let retriever = AssetRetriever(
            formatSniffer: DefaultFormatSniffer(),
            resourceFactory: LocalFileResourceFactory(),
            archiveOpener: ZIPArchiveOpener()
        )
        let asset: Asset
        switch await retriever.retrieve(url: file) {
        case let .success(a): asset = a
        case let .failure(error):
            switch error {
            case .formatNotSupported: return .failure(.notAnEPUB)
            case let .schemeNotSupported(s): return .failure(.unreadable("scheme \(s)"))
            case let .reading(e): return .failure(.unreadable(String(describing: e)))
            }
        }
        guard asset.format.conformsTo(.epub) else { return .failure(.notAnEPUB) }

        // 4. EPUB parser only, with the declared-resource container and the sanitizers wrapped around the publication
        //    container (`DeclaredResourceContainer`): undeclared entries are not served at all, and every declared
        //    entry is served by the treatment of its declared media type.
        let stats = SanitizerStats()
        let overBudget = PublicationHTMLSafety.OverBudgetDocuments()
        let limiter = PublicationHTMLSafety.WorkerLimiter()
        let sanitize = options.sanitizeHTML
        let opener = PublicationOpener(parser: EPUBParser())
        let result = await opener.open(asset: asset, allowUserInteraction: false, onCreatePublication: { manifest, container, _ in
            guard sanitize else { return }
            let treatments = DeclaredResourceContainer.treatments(for: manifest)
            stats.recordTreatments(treatments)
            container = DeclaredResourceContainer(inner: container, treatments: treatments, onUndeclared: { key in
                stats.recordUndeclared(key)
            }, serve: { key, treatment, resource in
                switch treatment {
                case .htmlDocument:
                    return resource.mapAsString { html in
                        let r = await PublicationHTMLSafety.sanitize(html: html, key: key, overBudget: overBudget, limiter: limiter)
                        stats.record(r, href: key)
                        return r.html
                    }
                case .otherDocument:
                    return resource.mapAsString { document in
                        let r = await PublicationHTMLSafety.sanitize(nonHTMLDocument: document, key: key, overBudget: overBudget, limiter: limiter)
                        stats.recordNonHTML(r, href: key)
                        return r.document
                    }
                case .passive:
                    return resource
                case .withheld:
                    stats.recordWithheldType(href: key)
                    return DataResource(string: "")
                }
            })
        })
        let publication: Publication
        switch result {
        case let .success(p): publication = p
        case let .failure(error):
            switch error {
            case .formatNotSupported: return .failure(.notAnEPUB)
            case let .reading(e): return .failure(.unreadable(String(describing: e)))
            }
        }

        // 5. Content protection: LCP and Adobe ADEPT are flagged restricted by Readium's fallback; any other
        //    non-obfuscation encryption declared in encryption.xml is unsupported too (never decrypted, plan 8.3).
        if options.rejectUnsupportedEncryption {
            let algorithms = (publication.readingOrder + publication.resources)
                .compactMap { $0.properties.encryption?.algorithm }
                .filter { !obfuscationAlgorithms.contains($0) }
            if publication.isRestricted {
                return .failure(.unsupportedProtection(scheme: publication.protectionScheme?.rawValue.string ?? "restricted", algorithms: Array(Set(algorithms)).sorted()))
            }
            if !algorithms.isEmpty {
                return .failure(.unsupportedProtection(scheme: "unknown", algorithms: Array(Set(algorithms)).sorted()))
            }
        }
        if publication.metadata.layout == .fixed {
            return .failure(.unsupportedLayout("fixed"))
        }

        let digest = (try? Data(contentsOf: fileURL, options: .mappedIfSafe)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
        let seconds = (clock.now - start).seconds
        return .success(OpenedEPUB(publication: publication, fileURL: fileURL, sha256: digest, preflight: report, sanitizer: stats, options: options, openSeconds: seconds))
    }
}

/// `file:` URLs only. (Readium 3.11.0's `FileResourceFactory` has no public initializer, and
/// `DefaultResourceFactory` also accepts HTTP, which the EPUB adapter never needs.)
final class LocalFileResourceFactory: ResourceFactory {
    func make(url: any AbsoluteURL) async -> Result<any Resource, ResourceMakeError> {
        guard let file = url.fileURL else { return .failure(.schemeNotSupported(url.scheme)) }
        return .success(FileResource(file: file))
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
