import Foundation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
import UIKit
import WebKit

/// Test-only probes into the rendered resource, used by the hosted tests and the UI-test scenarios.
/// They create DOM selections and read back the DOM; they never change what Readium does.
@MainActor enum ReaderProbe {
    struct JSFailure: Error, CustomStringConvertible { let description: String }

    static func evaluate(_ session: ReadiumReaderSession, _ script: String) async throws -> String {
        switch await session.testHookEvaluate(script) {
        case let .success(value):
            if let s = value as? String { return s }
            if let n = value as? NSNumber { return n.stringValue }
            return String(describing: value)
        case let .failure(error):
            throw JSFailure(description: "\(error)")
        }
    }

    static func json(_ session: ReadiumReaderSession, _ script: String) async throws -> [String: Any] {
        let s = try await evaluate(session, script)
        guard let obj = try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else {
            throw JSFailure(description: "not a JSON object: \(s.prefix(200))")
        }
        return obj
    }

    static func jsString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [])
        let arr = String(decoding: data, as: UTF8.self)
        return String(arr.dropFirst().dropLast())
    }

    /// Shared JavaScript: maps a substring of the concatenated text nodes of <body> to a DOM Range.
    /// Offsets are JavaScript string (UTF-16) offsets.
    static let library = """
    window.__sylviaProbe = window.__sylviaProbe || (function () {
      function textIndex() {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        const nodes = []; let text = '';
        while (walker.nextNode()) { const n = walker.currentNode; nodes.push([n, text.length]); text += n.data; }
        return { nodes, text };
      }
      function point(idx, pos, isEnd) {
        for (let i = 0; i < idx.nodes.length; i++) {
          const [n, s] = idx.nodes[i]; const e = s + n.data.length;
          if (!isEnd && pos >= s && pos < e) return [n, pos - s];
          if (isEnd && pos > s && pos <= e) return [n, pos - s];
        }
        return null;
      }
      function rangeFor(start, end) {
        const idx = textIndex();
        const a = point(idx, start, false), b = point(idx, end, true);
        if (!a || !b) return null;
        const r = document.createRange(); r.setStart(a[0], a[1]); r.setEnd(b[0], b[1]); return r;
      }
      function find(exact, prefixTail, from) {
        const idx = textIndex(); let i = idx.text.indexOf(exact, from || 0);
        while (i >= 0 && prefixTail && idx.text.slice(Math.max(0, i - prefixTail.length), i) !== prefixTail) {
          i = idx.text.indexOf(exact, i + 1);
        }
        return i;
      }
      function rectsOf(range) {
        return Array.from(range.getClientRects()).filter(r => r.width > 0.5 && r.height > 0.5)
          .map(r => ({ x: r.left, y: r.top, w: r.width, h: r.height }));
      }
      function union(rects) {
        if (!rects.length) return null;
        const l = Math.min(...rects.map(r => r.x)), t = Math.min(...rects.map(r => r.y));
        const rr = Math.max(...rects.map(r => r.x + r.w)), b = Math.max(...rects.map(r => r.y + r.h));
        return { x: l, y: t, w: rr - l, h: b - t };
      }
      return {
        select(start, end) {
          const r = rangeFor(start, end); if (!r) return JSON.stringify({ ok: false });
          const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r);
          return JSON.stringify({ ok: true, start, end, rangeText: r.toString(), selectionText: sel.toString() });
        },
        selectText(exact, prefixTail) {
          const i = find(exact, prefixTail); if (i < 0) return JSON.stringify({ ok: false, reason: 'not found' });
          return this.select(i, i + exact.length);
        },
        // Selects `phrase` matched with any run of whitespace in the DOM text standing for one space (source files
        // such as Project Gutenberg's wrap lines inside paragraphs).
        selectNormalized(phrase) {
          const idx = textIndex(); const raw = idx.text; let norm = ''; const map = []; let inSpace = false;
          for (let k = 0; k < raw.length; k++) {
            const ws = /\\s/.test(raw[k]);
            if (ws) { if (!inSpace) { norm += ' '; map.push(k); } inSpace = true; }
            else { norm += raw[k]; map.push(k); inSpace = false; }
          }
          const i = norm.indexOf(phrase); if (i < 0) return JSON.stringify({ ok: false, reason: 'not found' });
          const start = map[i], end = map[i + phrase.length - 1] + 1;
          return this.select(start, end);
        },
        selectBetween(startText, endText) {
          const i = find(startText); if (i < 0) return JSON.stringify({ ok: false, reason: 'start not found' });
          const j = find(endText, null, i); if (j < 0) return JSON.stringify({ ok: false, reason: 'end not found' });
          return this.select(i, j + endText.length);
        },
        selectAll() {
          const r = document.createRange(); r.selectNodeContents(document.body);
          const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r);
          return JSON.stringify({ ok: true, rangeText: r.toString(), selectionText: sel.toString() });
        },
        // Where the quote is now: its client rects, whether it starts on the visible page, and the decoration
        // boxes of `highlightId` with their computed colors.
        inspect(exact, prefixTail, highlightId) {
          const i = find(exact, prefixTail);
          const range = i >= 0 ? rangeFor(i, i + exact.length) : null;
          const quoteRects = range ? rectsOf(range) : [];
          const boxes = Array.from(document.querySelectorAll('.sylvia-highlight'))
            .filter(e => !highlightId || e.dataset.sylviaHighlightId === highlightId)
            .map(e => { const cs = getComputedStyle(e); const r = e.getBoundingClientRect();
              return { x: r.left, y: r.top, w: r.width, h: r.height, bg: cs.backgroundColor, ub: cs.borderBottomColor,
                       uw: cs.borderBottomWidth, us: cs.borderBottomStyle, z: cs.zIndex, pos: cs.position }; });
          const q = union(quoteRects), d = union(boxes);
          // Same text: every quote line is spanned horizontally by boxes on that line (vertical centres within the
          // line), and every box lies on the quote (centre inside the quote's union, 2 px tolerance).
          function onLine(b, r) { const cy = b.y + b.h / 2; return cy >= r.y - 2 && cy <= r.y + r.h + 2; }
          function spans(r) {
            const xs = boxes.filter(b => onLine(b, r)).map(b => [b.x, b.x + b.w]).sort((a, c) => a[0] - c[0]);
            let reach = r.x + 2;
            for (const [a, c] of xs) { if (a > reach + 2) break; reach = Math.max(reach, c); }
            return reach >= r.x + r.w - 2;
          }
          // How many times this highlight is drawn: distinct decoration item containers holding its boxes.
          const itemContainers = new Set(Array.from(document.querySelectorAll('.sylvia-highlight'))
            .filter(e => !highlightId || e.dataset.sylviaHighlightId === highlightId).map(e => e.parentElement)).size;
          const qu = union(quoteRects);
          const covered = quoteRects.length > 0 && boxes.length > 0 && quoteRects.every(spans) && boxes.every(b => {
            const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
            return cx >= qu.x - 2 && cx <= qu.x + qu.w + 2 && cy >= qu.y - 2 && cy <= qu.y + qu.h + 2; });
          const first = quoteRects[0];
          return JSON.stringify({ found: i >= 0, textOffsetUTF16: i, itemContainers, quoteRects: quoteRects.length, quoteRectList: quoteRects, boxes,
            quoteUnion: q, boxUnion: d, covered,
            visible: !!first && first.x >= -1 && first.x < window.innerWidth && first.y >= -1 && first.y < window.innerHeight,
            innerWidth: window.innerWidth, innerHeight: window.innerHeight });
        },
        style(selector) {
          const e = document.querySelector(selector || 'p'); if (!e) return JSON.stringify({ ok: false });
          const cs = getComputedStyle(e); const root = getComputedStyle(document.documentElement);
          return JSON.stringify({ ok: true, fontFamily: cs.fontFamily, fontSize: cs.fontSize, lineHeight: cs.lineHeight,
            color: cs.color, rootBackground: root.backgroundColor, bodyBackground: getComputedStyle(document.body).backgroundColor,
            userFontFamily: document.documentElement.style.getPropertyValue('--USER__fontFamily'),
            userFontSize: document.documentElement.style.getPropertyValue('--USER__fontSize'),
            userLineHeight: document.documentElement.style.getPropertyValue('--USER__lineHeight') });
        },
      };
    })(); true;
    """

    static func install(_ session: ReadiumReaderSession) async throws {
        _ = try await evaluate(session, library)
    }

    static func call(_ session: ReadiumReaderSession, _ expression: String) async throws -> [String: Any] {
        try await install(session)
        return try await json(session, "window.__sylviaProbe.\(expression)")
    }

    struct Inspection {
        var found: Bool
        var textOffsetUTF16: Int
        var quoteRectCount: Int
        var boxes: [[String: Any]]
        var covered: Bool
        var visible: Bool
        /// Number of times the highlight is drawn (1 when correct; 0 when not drawn).
        var renderings: Int
        var raw: [String: Any]
    }

    static func inspect(_ session: ReadiumReaderSession, exact: String, prefix: String, highlightID: String?) async throws -> Inspection {
        let tail = String(prefix.suffix(30))
        let raw = try await call(session, "inspect(\(jsString(exact)), \(jsString(tail)), \(highlightID.map(jsString) ?? "null"))")
        return Inspection(
            found: raw["found"] as? Bool ?? false,
            textOffsetUTF16: raw["textOffsetUTF16"] as? Int ?? -1,
            quoteRectCount: raw["quoteRects"] as? Int ?? 0,
            boxes: raw["boxes"] as? [[String: Any]] ?? [],
            covered: raw["covered"] as? Bool ?? false,
            visible: raw["visible"] as? Bool ?? false,
            renderings: raw["itemContainers"] as? Int ?? 0,
            raw: raw
        )
    }

    /// Waits until Readium reports a selection (selectionchange is debounced 50 ms), then returns it as the adapter
    /// captures it (`captureSelection()`, resource confirmed).
    static func waitForSelection(_ session: ReadiumReaderSession, timeout: Duration = .seconds(5)) async -> ReaderSelection? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if session.currentSelection != nil { return await session.captureSelection() }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// Polls `condition` until true or timeout.
    static func wait(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }

    /// Navigates so that `exact` (in `href`) is on screen, using Readium's own text-quote navigation.
    static func goToText(_ session: ReadiumReaderSession, href: String, exact: String) async -> Bool {
        guard let url = AnyURL(string: href), let link = session.publication.linkWithHREF(url) else { return false }
        let locator = Locator(href: link.url(), mediaType: link.mediaType ?? .xhtml, text: Locator.Text(highlight: exact))
        return await session.go(to: locator)
    }

    /// The visible spread's web view (the one with a window and the largest visible area).
    static func visibleWebView(in view: UIView) -> WKWebView? {
        var found: [WKWebView] = []
        func walk(_ v: UIView) {
            if let w = v as? WKWebView, w.window != nil, !w.isHidden { found.append(w) }
            v.subviews.forEach(walk)
        }
        walk(view)
        return found.max { a, b in
            let ra = a.convert(a.bounds, to: nil).intersection(a.window!.bounds)
            let rb = b.convert(b.bounds, to: nil).intersection(b.window!.bounds)
            return ra.width * ra.height < rb.width * rb.height
        }
    }

    static func snapshot(_ session: ReadiumReaderSession) async -> UIImage? {
        guard let web = visibleWebView(in: session.navigator.view) else { return nil }
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        return try? await web.takeSnapshot(configuration: config)
    }

    /// Writes evidence into `<app Documents>/evidence/` (copied out by the CI script) and, when
    /// SYLVIA_EVIDENCE_DIR is set and writable, there too.
    @discardableResult
    static func writeEvidence(_ name: String, data: Data) -> [URL] {
        var dirs = [FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("evidence")]
        if let extra = ProcessInfo.processInfo.environment["SYLVIA_EVIDENCE_DIR"], !extra.isEmpty {
            dirs.append(URL(fileURLWithPath: extra))
        }
        var written: [URL] = []
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            if (try? data.write(to: url, options: .atomic)) != nil { written.append(url) }
        }
        return written
    }

    /// Saves a screenshot at 1x (points = pixels) to keep evidence files small.
    static func writePNG(_ name: String, _ image: UIImage) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        if let data = small.pngData() { writeEvidence(name, data: data) }
    }

    static func writeEvidence(_ name: String, json: Any) {
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            writeEvidence(name, data: data)
        }
    }

    static func writeEvidence(_ name: String, text: String) {
        writeEvidence(name, data: Data(text.utf8))
    }
}
