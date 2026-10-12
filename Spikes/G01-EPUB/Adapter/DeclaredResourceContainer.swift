import Foundation
import G01EPUBCore
@preconcurrency import ReadiumShared

/// The publication container the adapter hands to Readium (ADR-0004 section 4 item 4; review R2-01).
///
/// Readium 3.11.0's navigator serves any archive entry a web view asks for (`EPUBNavigatorViewModel.serve(href:)` calls
/// `publication.get(href)`), and for an entry the manifest does not declare it picks the media type from the file
/// extension, so `evil.html` left out of the manifest is served as `text/html`. Its spread view cancels link activations
/// only, so a form submission (or any other navigation that is not a link activation) can load such an entry. This
/// container is default-deny:
///
/// - an entry that no manifest link declares (reading order, resources, links, and their alternates and children) is
///   answered with "no such entry", so Readium returns 404 to the web view and its services never read it;
/// - a declared entry is served according to `PublicationResourcePolicy.treatment(forMediaType:)` for the media type
///   Readium will serve it with (the manifest's): HTML through the HTML sanitizer (canonical form, CSP), any other
///   document type a web view renders (SVG, XML, `+xml`) through the non-HTML sanitizer (withheld when anything active
///   or any XHTML element is in it), known passive types unchanged, and anything else as an empty resource;
/// - an href declared more than once with different media types is served empty (Readium would pick the first
///   declaration; the adapter does not guess which one the web view will be given).
final class DeclaredResourceContainer: Container {
    typealias Treatment = PublicationResourcePolicy.Treatment

    private let inner: Container
    private let treatments: [String: Treatment]
    private let serve: (_ key: String, _ treatment: Treatment, _ resource: Resource) -> Resource
    private let onUndeclared: (_ key: String) -> Void

    init(inner: Container, treatments: [String: Treatment],
         onUndeclared: @escaping (_ key: String) -> Void,
         serve: @escaping (_ key: String, _ treatment: Treatment, _ resource: Resource) -> Resource) {
        self.inner = inner
        self.treatments = treatments
        self.onUndeclared = onUndeclared
        self.serve = serve
    }

    let sourceURL: AbsoluteURL? = nil

    var entries: Set<AnyURL> { inner.entries.filter { treatments[$0.normalized.string] != nil } }

    subscript(url: any URLConvertible) -> Resource? {
        // `Publication.get` asks again without the query and fragment; the same fallback is applied here so a request
        // with a query is not counted as undeclared.
        let exact = url.anyURL.normalized
        let stripped = exact.removingQuery().removingFragment()
        let target: AnyURL
        if treatments[exact.string] != nil {
            target = exact
        } else if treatments[stripped.string] != nil {
            target = stripped
        } else {
            onUndeclared(stripped.string)
            return nil
        }
        guard let treatment = treatments[target.string], let resource = inner[target] else { return nil }
        return serve(target.string, treatment, resource)
    }

    /// The treatment of every href the manifest declares, keyed by Readium's normalized href.
    static func treatments(for manifest: Manifest) -> [String: Treatment] {
        var mediaTypes: [String: Set<String>] = [:]
        func visit(_ links: [ReadiumShared.Link]) {
            for link in links {
                if !link.templated {
                    mediaTypes[link.url().normalized.string, default: []].insert(link.mediaType?.string ?? "")
                }
                visit(link.alternates)
                visit(link.children)
            }
        }
        visit(manifest.readingOrder)
        visit(manifest.resources)
        visit(manifest.links)
        return mediaTypes.mapValues { types in
            guard types.count == 1, let only = types.first, !only.isEmpty else { return .withheld }
            return PublicationResourcePolicy.treatment(forMediaType: only)
        }
    }
}
