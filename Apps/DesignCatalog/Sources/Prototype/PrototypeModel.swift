import Foundation
import Observation
import SwiftUI
import SylviaDesign

/// Every screen and state of the interaction prototype that can be opened directly
/// (`-SylviaScreen <rawValue>`, or the catalog's screen list). The UI tests visit each one.
enum PrototypeScreen: String, CaseIterable, Identifiable, Sendable {
    case onboarding
    case library
    case workOnDevice = "work.onDevice"
    case workRecordOnly = "work.recordOnly"
    case workNotOnDevice = "work.notOnDevice"
    case inbox
    case inboxResolve = "inbox.resolve"
    case inboxReview = "inbox.review"
    case reader
    case readerSelection = "reader.selection"
    case captureDraft = "capture.draft"
    case captureSaving = "capture.saving"
    case captureSaved = "capture.saved"
    case captureFailed = "capture.failed"
    case lookUp
    case thoughts
    case player
    case playerPreserving = "player.preserving"
    case playerSaved = "player.saved"
    case playerFailed = "player.failed"
    case audioCapture
    case askDraft = "ask.draft"
    case askSending = "ask.sending"
    case askGenerated = "ask.generated"
    case askInterrupted = "ask.interrupted"
    case storage
    case storageImpact = "storage.impact"
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onboarding: "Onboarding"
        case .library: "Library with the mini-player"
        case .workOnDevice: "Work detail, files here"
        case .workRecordOnly: "Work detail, a record with no file"
        case .workNotOnDevice: "Work detail, file on the Mac"
        case .inbox: "Inbox, layout B"
        case .inboxResolve: "Inbox, Resolve detail"
        case .inboxReview: "Inbox, review a duplicate"
        case .reader: "Reader"
        case .readerSelection: "Reader with the selection menu"
        case .captureDraft: "Capture sheet, draft"
        case .captureSaving: "Capture sheet, write in progress"
        case .captureSaved: "Capture sheet, after the durable write"
        case .captureFailed: "Capture sheet, failed write"
        case .lookUp: "Look up a word"
        case .thoughts: "Thoughts"
        case .player: "Player"
        case .playerPreserving: "Player, excerpt being preserved"
        case .playerSaved: "Player, excerpt preserved"
        case .playerFailed: "Player, excerpt not preserved"
        case .audioCapture: "Audio capture detail"
        case .askDraft: "Ask, draft"
        case .askSending: "Ask, sending"
        case .askGenerated: "Ask, answer with citations"
        case .askInterrupted: "Ask, interrupted"
        case .storage: "Storage"
        case .storageImpact: "Storage, remove-download impact report"
        case .settings: "Settings and prototype controls"
        }
    }
}

/// Where the reader, player and sheets stand. One instance per prototype session.
@MainActor
@Observable
final class PrototypeModel {
    enum Route: Hashable {
        case work(WorkID)
        case inboxItem(Fixtures.InboxItemID)
        case storage(WorkID)
        case settings
        case ask
        case audioCapture
    }

    enum CaptureKind: Hashable { case quote, word, audioNote }

    enum AskPhase: Equatable {
        case draft
        case sending
        /// Segments received so far; `finished` once the whole answer arrived.
        case answering(received: Int, finished: Bool)
        case interrupted(received: Int)
    }

    enum ExcerptPhase: Equatable {
        case none
        /// The moment is written; the excerpt is being preserved ("Moment saved · preserving audio").
        case preserving
        /// The excerpt record is written too ("Audio excerpt saved").
        case saved
        /// The moment is written but the excerpt failed ("Excerpt not preserved · Retry": the
        /// bookmark survives, Section 10.2).
        case failed
        /// The moment itself could not be written: nothing was saved, so neither "Moment saved"
        /// nor "Excerpt not preserved" (which says the bookmark survived) may show (review R1-07).
        case momentNotSaved
    }

    // Navigation
    var showsOnboarding = false
    var area: SylviaArea = .library
    var libraryPath: [Route] = []
    var thoughtsPath: [Route] = []
    var inboxPath: [Route] = []
    var readerPath: [Route] = []
    var playerPath: [Route] = []
    var readerOpen = false
    var playerOpen = false
    /// The reader's Thoughts pane on iPad in regular width.
    var readerPaneVisible = true
    var bookmarked = true
    /// The prototype was opened directly at the reader or player (UI tests, `-SylviaScreen`).
    var startedInReader = false
    var startedInPlayer = false

    // Data
    var works: [Work] = Fixtures.works
    var inbox: [Fixtures.InboxItem] = Fixtures.inbox
    var savedThoughts: [Fixtures.Thought] = []
    var deletedWorks: Set<WorkID> = []
    var isPlaying = true
    var playbackRate = 1.25

    // Reader and capture
    var selectionActive = false
    var captureSheet: CaptureKind?
    var draft = CaptureDraft()
    var captureSubject: CaptureSubject = .quote(text: Fixtures.selected)
    var audioRange = AudioRange(start: 672_000, end: 702_000, sourceDuration: 3_600_000)
    /// The range of the excerpt last preserved; a changed range needs a new excerpt.
    var savedAudioRange = AudioRange(start: 672_000, end: 702_000, sourceDuration: 3_600_000)
    /// The note on the audio capture, once durably saved.
    var audioNote: String?

    // Ask
    var askScope: Status = .scopeSelectedPassage
    var askQuestion = Fixtures.question
    var askPhase: AskPhase = .draft

    // Player capture
    var excerptPhase: ExcerptPhase = .none

    // Storage
    var impactReport: ImpactKind?

    enum ImpactKind: String, Identifiable {
        case audiobook, epub, excerpts, record
        var id: String { rawValue }
    }

    // Prototype controls (Settings)
    var nextSaveFails = false
    var nextExcerptFails = false
    /// Makes the next audio moment write itself fail (nothing is saved; review R1-07).
    var nextMomentFails = false
    var nextAnswerInterrupted = false
    /// Simulated durable write duration; a very long value holds the "Saving…" state.
    var writeDuration: Duration

    let store: CaptureStore
    /// Leaves the prototype (back to the catalog); nil when the prototype was opened at launch.
    @ObservationIgnored var onLeave: (() -> Void)?
    private var askTask: Task<Void, Never>?
    private var excerptTask: Task<Void, Never>?

    init(writeSeconds: Double?, store: CaptureStore = CaptureStore()) {
        self.writeDuration = .milliseconds(Int((writeSeconds ?? 1.5) * 1000))
        self.store = store
    }

    var inboxNeedsAttention: Bool {
        inbox.contains { $0.state.presentation()?.requiresReasonAndNextStep == true || $0.state == .needsReview }
    }

    func work(_ id: WorkID) -> Work? { works.first { $0.id == id } }

    var visibleWorks: [Work] { works.filter { !deletedWorks.contains($0.id) } }

    // MARK: Capture (Section 11.1): "Saved" only after the durable write returns.

    func openCapture(_ kind: CaptureKind) {
        draft = CaptureDraft()
        switch kind {
        case .quote: captureSubject = .quote(text: Fixtures.selected)
        case .audioNote: captureSubject = .audio(audioRange)
        case .word: break
        }
        captureSheet = kind
    }

    func save() {
        guard draft.saveState != .saving else { return }
        draft.beginSave()
        let note = draft.note
        let fails = nextSaveFails
        nextSaveFails = false
        let kind = captureSheet
        let record = CaptureStore.Record(kind: kindName(kind), text: captureText(kind), note: note)
        let duration = writeDuration
        Task {
            do {
                let date = try await store.commit(record, duration: duration, fail: fails)
                // The commit callback: only now may the sheet say "Saved".
                draft.commitSucceeded(at: date, savedNote: note)
                if kind == .audioNote { audioNote = note.isEmpty ? nil : note }
                addSavedThought(kind: kind, note: note, date: date)
            } catch {
                draft.commitFailed()
            }
        }
    }

    func closeCapture() {
        guard draft.canDismiss else { return }
        captureSheet = nil
        selectionActive = false
    }

    /// A binding that presents the capture sheet of `kind`. Setting it false closes the sheet only
    /// when the draft may be dismissed (no unsaved text).
    func captureSheetBinding(_ kind: CaptureKind) -> Binding<Bool> {
        Binding { [weak self] in self?.captureSheet == kind } set: { [weak self] shown in
            guard let self else { return }
            if shown { captureSheet = kind } else if captureSheet == kind { closeCapture() }
        }
    }

    /// The selection menu (Section 4.4.7): Highlight and Note open the capture sheet, Look Up the
    /// word sheet, Ask the Ask screen.
    func selectionAction(_ action: SelectionAction) {
        switch action {
        case .highlight, .note: openCapture(.quote)
        case .lookUp: openCapture(.word)
        case .ask: readerPath.append(.ask)
        }
    }

    /// Look up from the capture sheet: only when nothing unsaved would be lost.
    func switchCapture(to kind: CaptureKind) {
        guard draft.canDismiss else { return }
        openCapture(kind)
    }

    /// Ask from the capture sheet: closes it (only without unsaved text) and opens Ask.
    func askFromCapture() {
        guard draft.canDismiss else { return }
        captureSheet = nil
        readerPath.append(.ask)
    }

    private func kindName(_ kind: CaptureKind?) -> String {
        switch kind {
        case .quote: "text_quote"
        case .word: "word"
        case .audioNote: "audio_capture"
        case nil: "note"
        }
    }

    private func captureText(_ kind: CaptureKind?) -> String {
        switch kind {
        case .quote: Fixtures.selected
        case .word: "incongruities"
        case .audioNote, nil: ""
        }
    }

    private func addSavedThought(kind: CaptureKind?, note: String, date: Date) {
        let time = TimestampText.time(date, locale: .current, timeZone: .current)
        let content: CaptureCardContent
        switch kind {
        case .quote: content = .quote(text: Fixtures.selected, yourNote: note.isEmpty ? nil : note)
        case .word: content = .word(headword: "incongruities", sentence: Fixtures.readerParagraphs[0], yourNote: note.isEmpty ? nil : note)
        case .audioNote, nil:
            content = .audio(durationSeconds: Int(audioRange.lengthMilliseconds / 1000), waveformSeed: "middlemarch-14-1112",
                             transcript: nil, yourNote: note.isEmpty ? nil : note)
        }
        let details = kind == .audioNote ? ["Middlemarch", "Part 14"] : ["Middlemarch", "Bk II, ch. 20"]
        savedThoughts.removeAll { $0.id == "saved-\(kindName(kind))" }
        savedThoughts.insert(Fixtures.Thought(id: "saved-\(kindName(kind))", content: content, details: details, time: time,
                                              day: .today, work: .middlemarch), at: 0)
    }

    // MARK: Ask (Section 14.4): draft, sending, generated, complete or interrupted.

    func send() {
        guard askPhase == .draft, !askQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        askPhase = .sending
        let interrupt = nextAnswerInterrupted
        nextAnswerInterrupted = false
        askTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, askPhase == .sending else { return }
            let count = Fixtures.answer.count
            for received in 1...count {
                if interrupt && received == 3 {
                    askPhase = .interrupted(received: 2)
                    return
                }
                askPhase = .answering(received: received, finished: received == count)
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, case .answering = askPhase else { return }
            }
        }
    }

    /// Stops a request in flight: whatever arrived stays, marked "Interrupted · partial answer".
    func stopAsking() {
        askTask?.cancel()
        switch askPhase {
        case .sending: askPhase = .interrupted(received: 0)
        case .answering(let received, false): askPhase = .interrupted(received: received)
        default: break
        }
    }

    func resetAsk() {
        askTask?.cancel()
        askPhase = .draft
    }

    // MARK: Audio capture (Section 10.2): the moment first, then the preserved excerpt.

    /// The capture control: the moment (time range) is written durably first, and only then does
    /// the player say "Moment saved · preserving audio"; the excerpt export follows (simulated).
    func captureMoment() {
        guard excerptPhase != .preserving else { return }
        excerptTask?.cancel()
        let fails = nextExcerptFails
        nextExcerptFails = false
        let failsMoment = nextMomentFails
        nextMomentFails = false
        let duration = writeDuration
        let range = audioRange
        let moment = CaptureStore.Record(kind: "audio_moment", text: Timecode.text(milliseconds: range.startMilliseconds)
                                         + "-" + Timecode.text(milliseconds: range.endMilliseconds), note: "")
        excerptTask = Task {
            do {
                _ = try await store.commit(moment, duration: .zero, fail: failsMoment)
            } catch {
                if !Task.isCancelled { excerptPhase = .momentNotSaved }
                return
            }
            guard !Task.isCancelled else { return }
            excerptPhase = .preserving
            // The excerpt export is simulated (there is no audio engine in the prototype); its
            // record is written durably before the player may say "Audio excerpt saved".
            let excerpt = CaptureStore.Record(kind: "audio_excerpt", text: moment.text, note: "")
            do {
                _ = try await store.commit(excerpt, duration: duration, fail: fails)
            } catch {
                if !Task.isCancelled { excerptPhase = .failed }
                return
            }
            guard !Task.isCancelled else { return }
            savedAudioRange = range
            excerptPhase = .saved
        }
    }

    /// Preserves the excerpt again after its range was edited on the audio capture detail.
    func preserveEditedRange() {
        captureMoment()
    }

    // MARK: Inbox

    func resolve(_ id: Fixtures.InboxItemID) {
        inbox.removeAll { $0.id == id }
        inboxPath.removeAll()
    }

    func togglePause(_ id: Fixtures.InboxItemID) {
        guard let index = inbox.firstIndex(where: { $0.id == id }) else { return }
        inbox[index].state = inbox[index].state == .acquiring ? .created : .acquiring
    }

    // MARK: Storage

    func removeDownload(_ kind: EditionKind, of id: WorkID) {
        guard let w = works.firstIndex(where: { $0.id == id }) else { return }
        for e in works[w].editions.indices where works[w].editions[e].kind == kind {
            works[w].editions[e].availability = .notOnThisDevice(source: Fixtures.source)
        }
    }

    func deleteRecord(_ id: WorkID) {
        deletedWorks.insert(id)
        libraryPath.removeAll()
    }

    // MARK: Opening a screen directly

    func open(_ screen: PrototypeScreen) {
        switch screen {
        case .onboarding: showsOnboarding = true
        case .library: area = .library
        case .workOnDevice: area = .library; libraryPath = [.work(.middlemarch)]
        case .workRecordOnly: area = .library; libraryPath = [.work(.meditations)]
        case .workNotOnDevice: area = .library; libraryPath = [.work(.mobyDick)]
        case .inbox: area = .inbox
        case .inboxResolve: area = .inbox; inboxPath = [.inboxItem(.frankenstein)]
        case .inboxReview: area = .inbox; inboxPath = [.inboxItem(.walden)]
        case .reader: readerOpen = true; startedInReader = true
        case .readerSelection: readerOpen = true; startedInReader = true; selectionActive = true
        case .captureDraft:
            readerOpen = true; startedInReader = true; selectionActive = true; openCapture(.quote)
            draft.note = "Eliot's case for partial sympathy: total perception would destroy us."
        case .captureSaving:
            readerOpen = true; startedInReader = true; selectionActive = true; openCapture(.quote)
            draft.note = "Eliot's case for partial sympathy: total perception would destroy us."
            writeDuration = .seconds(3600)
            save()
        case .captureSaved:
            readerOpen = true; startedInReader = true; selectionActive = true; openCapture(.quote)
            draft.note = "Eliot's case for partial sympathy: total perception would destroy us."
            writeDuration = .milliseconds(10)
            save()
        case .captureFailed:
            readerOpen = true; startedInReader = true; selectionActive = true; openCapture(.quote)
            draft.note = "Eliot's case for partial sympathy: total perception would destroy us."
            nextSaveFails = true
            writeDuration = .milliseconds(10)
            save()
        case .lookUp: readerOpen = true; startedInReader = true; selectionActive = true; openCapture(.word)
        case .thoughts: area = .thoughts
        case .player: playerOpen = true; startedInPlayer = true
        case .playerPreserving: playerOpen = true; startedInPlayer = true; writeDuration = .seconds(3600); captureMoment()
        case .playerSaved: playerOpen = true; startedInPlayer = true; writeDuration = .milliseconds(10); captureMoment()
        case .playerFailed: playerOpen = true; startedInPlayer = true; writeDuration = .milliseconds(10); nextExcerptFails = true; captureMoment()
        case .audioCapture:
            // Through the real capture path: "Audio excerpt saved" shows only after the moment and
            // the excerpt record are written (review R1-07; it was set directly before).
            playerOpen = true; startedInPlayer = true; writeDuration = .milliseconds(10); captureMoment()
            playerPath = [.audioCapture]
        case .askDraft: readerOpen = true; startedInReader = true; readerPath = [.ask]
        case .askSending: readerOpen = true; startedInReader = true; readerPath = [.ask]; askPhase = .sending
        case .askGenerated: readerOpen = true; startedInReader = true; readerPath = [.ask]; askPhase = .answering(received: Fixtures.answer.count, finished: true)
        case .askInterrupted: readerOpen = true; startedInReader = true; readerPath = [.ask]; askPhase = .interrupted(received: 2)
        case .storage: area = .library; libraryPath = [.work(.middlemarch), .storage(.middlemarch)]
        case .storageImpact: area = .library; libraryPath = [.work(.middlemarch), .storage(.middlemarch)]; impactReport = .audiobook
        case .settings: area = .library; libraryPath = [.settings]
        }
    }
}

/// The prototype's durable store: each capture is written atomically to a JSON file in Application
/// Support before `commit` returns, so the sheet's "Saved" follows a real durable write. The delay
/// makes "Saving…" visible; `fail` simulates a failed write (Settings > Prototype controls).
actor CaptureStore {
    struct Record: Codable, Sendable {
        let kind: String
        let text: String
        let note: String
    }

    struct WriteFailed: Error {}

    /// The JSON file every commit rewrites (read back by DesignCatalogTests).
    nonisolated let url: URL
    private var records: [Record] = []

    init(directory: URL? = nil) {
        let base = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
        url = base.appendingPathComponent("PrototypeCaptures.json")
    }

    /// Writes `record` durably and returns the commit time, or throws.
    func commit(_ record: Record, duration: Duration, fail: Bool) async throws -> Date {
        try await Task.sleep(for: duration)
        if fail { throw WriteFailed() }
        // The record joins the in-memory list only after the file holding it is written: a failed
        // write leaves nothing behind for a later commit to persist (review R1-07).
        let updated = records + [record]
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        records = updated
        return Date()
    }
}
