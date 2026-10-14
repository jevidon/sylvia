#!/usr/bin/env python3
"""Mutation checks for the G0.5 AI spike: proves key tests would catch the failure they guard against.

For each mutation: back up one source file, apply a single textual change that removes a safeguard, run the named
test with `swift test --filter`, record whether it failed (it must), then restore the file byte for byte. A safeguard
checked in several places in one file (M54), or one whose position matters (M63 moves a call back to where it was
before review round 7), is changed with a tuple of anchors and a tuple of replacements, applied together.
Run from anywhere with DEVELOPER_DIR set (source Scripts/lib/env.sh); pass mutation names (M18 M54) to run only those. Prints a table; exits non-zero if any
mutation survived (its test still passed) or a file could not be restored. Not part of CI (slow: one build each).
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

SPIKE = Path(__file__).resolve().parent.parent

MUTATIONS = [
    ("M1 second send of one record is not refused",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "guard !inFlight.contains(id) else { throw AskError.invalidState(.sending) }", "",
     "concurrentSendsOfOneRecordPutTheQuestionOnTheWireOnce"),
    ("M2 stop while the sending record is written is ignored",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "if let stop = stopReasons.removeValue(forKey: id) {\n                let host",
     "if false, let stop = stopReasons.removeValue(forKey: id) {\n                let host",
     "stopWhileTheSendingRecordIsBeingWrittenSendsNothing"),
    ("M3 uncertain generation retried automatically",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "if let error, error.isTransient, record.answerText.isEmpty,", "if let error, record.answerText.isEmpty,",
     "uncertainFailureWithoutOutputIsNotRetried"),
    ("M4 Anthropic thinking_delta emitted as answer text",
     "Sources/SylviaAI/Streaming/FirstPartyDecoders.swift",
     'guard deltaType == "text_delta" else { return [] }',
     'if deltaType == "thinking_delta", let t = delta["thinking"] as? String { return [.text(t)] }\n            guard deltaType == "text_delta" else { return [] }',
     "thinkingBlocksAreNeverAnswerText"),
    ("M5 cross-origin redirect followed",
     "Sources/SylviaAI/Network/HTTPTransport.swift",
     "let target = Origin(url), target == origin else {", "let target = Origin(url), target == target else {",
     "crossOriginRedirectIsBlockedAndTheKeyNeverReachesTheTarget"),
    ("M6 provider error bodies not scrubbed",
     "Sources/SylviaAI/Support/Redaction.swift",
     "        var out = text\n", "        var out = text\n        if !text.isEmpty { return text }\n",
     "authenticationFailureWithKeyEchoedByServerIsScrubbed"),
    ("M7 spoiler boundary not applied in the FTS5 query",
     "Sources/SylviaContext/PassageIndex.swift",
     "WHERE chunk_fts MATCH ? AND chunk.work_id = ? AND (? IS NULL OR chunk.last_ordinal <= ?)\n                ORDER BY",
     "WHERE chunk_fts MATCH ? AND chunk.work_id = ? AND (? IS NULL OR ? IS NOT NULL)\n                ORDER BY",
     "restrictedWorkSearchContainsNothingAfterThePosition"),
    ("M8 any citation ID resolves",
     "Sources/SylviaAI/Grounding/CitationResolver.swift",
     "if let evidenceID = evidence[id] {", "if let evidenceID = evidence[id] ?? UUID(uuid: UUID_NULL) as UUID? {",
     "citationsResolveOnlyAgainstThePackAllowlist"),
    ("M9 one-word ellipsis fragments accepted as exact",
     "Sources/SylviaAI/Grounding/QuoteVerifier.swift",
     "segment.filter(isWord).count >= minimumWords", "segment.filter(isWord).count >= 1",
     "fragmentsStitchedWithEllipsesAreNotExact"),
    # Added after review round 1: each guards a safeguard the first nine did not cover.
    ("M10 send-time consent check skipped for a draft",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "        if case .required(let disclosure) = consent.evaluate(pack: record.pack,",
     "        if false, case .required(let disclosure) = consent.evaluate(pack: record.pack,",
     "draftSentWithoutPrepareNeedsConsentAndSendsNothing"),
    ("M11 pack and configuration destinations not compared",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "guard pack.endpoint == (try destination(config)) else { throw AskError.endpointMismatch }",
     "_ = try destination(config)",
     "packWhoseEndpointDiffersFromTheConfigurationIsRefused"),
    ("M12 coordinator stores a pack that breaks its boundary",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "guard pack.spoilerBoundaryViolations.isEmpty else { throw AskError.packViolatesSpoilerBoundary }", "",
     "packWithTextAfterItsOwnSpoilerBoundaryIsNeverStored"),
    ("M13 selection after the confirmed position accepted",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "if let maxOrdinal, let selection = request.selection, selection.paragraphOrdinal > maxOrdinal {",
     "if false, let maxOrdinal, let selection = request.selection, selection.paragraphOrdinal > maxOrdinal {",
     "selectionAfterTheConfirmedPositionIsRefused"),
    ("M14 adjacent chunk not checked against the boundary",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "maxOrdinal.map({ adjacent.lastOrdinal <= $0 }) ?? true", "true",
     "adjacentChunkNeverCrossesAMidChapterBoundary"),
    ("M15 no statement when no position is set",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "if boundary.enabled && boundary.basis == .none {", "if false {",
     "noEnforceablePositionMeansNoRetrievalRatherThanAFalsePromise"),
    ("M16 time-based checkpoint removed",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "guard grown >= checkpoint.characters || clock.now().timeIntervalSince(lastTime) >= checkpoint.interval else { return }",
     "guard grown >= checkpoint.characters else { return }",
     "slowOutputIsCheckpointedByTimeNotOnlyByLength"),
    ("M17 output size cap ignored",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "if receivedCharacters > maxCharacters {", "if false {",
     "outputBeyondTheCapIsStoppedAndLabelledPartial"),
    ("M18 request wall-clock watchdog removed",
     "Sources/SylviaAI/Providers/TextGenerationProvider.swift",
     "                timedOut.withLock { $0 = true }\n                task.cancel()\n", "",
     "silentStreamIsEndedByTheWallClockLimit"),
    ("M19 tool call then [DONE] without finish_reason is complete",
     "Sources/SylviaAI/Streaming/StreamDecoders.swift",
     "var resolvedFinish: FinishReason { reportedTool ? .toolCallRejected : (finishReason ?? .complete) }",
     "var resolvedFinish: FinishReason { finishReason ?? .complete }",
     "toolCallWithoutAToolFinishReasonIsNeverComplete"),
    ("M20 EndpointPolicy skipped on the speech path",
     "Sources/SylviaAI/Transcription/Transcription.swift",
     "do { assessment = try EndpointPolicy.assess(config) } catch {\n"
     "            throw ProviderError(kind: .insecureEndpointRejected, acceptance: .notSent, host: config.baseURL.host() ?? \"\", detail: error.userMessage)\n"
     "        }",
     "assessment = EndpointAssessment(origin: Origin(config.baseURL)!, automaticClassification: .local, effectiveClassification: .local, usesCleartext: false)",
     "cleartextToANonLocalAddressIsRefusedOnTheSpeechPath"),
    ("M21 single curly quotations not checked",
     "Sources/SylviaAI/Grounding/QuoteVerifier.swift",
     '#"(?<![\\p{L}\\p{N}])\\u2018([^\\u2018]{1,4000}?)\\u2019(?![\\p{L}\\p{N}])"#,',
     '#"\\u2018\\u2018\\u2018\\u2018(x)"#,',
     "everyQuotationStyleIsChecked"),
    # Added after review round 2.
    ("M22 connection test passes any reply with a final event",
     "Sources/SylviaAI/Providers/ConnectionTester.swift",
     "report.outcome = Self.judge(", "report.outcome = report.finish != nil ? .passed : Self.judge(",
     "toolCallOnlyRouteFailsTheTest"),
    ("M23 no reply text at the output limit passes",
     "Sources/SylviaAI/Providers/ConnectionTester.swift",
     "            return .failedConformance(sawText ? .outputLimitTruncated(maxOutputTokens: maxOutputTokens)\n"
     "                                              : .outputLimitBeforeText(maxOutputTokens: maxOutputTokens))",
     "            return .passed",
     "reasoningOnlyReplyAtTheOutputLimitFailsTheTest"),
    ("M24 every 5xx treated as certainly not accepted",
     "Sources/SylviaAI/Network/ProviderError.swift",
     "        default: .uncertain\n", "        default: .rejected\n",
     "serverErrorsWhoseAcceptanceIsUncertainAreNeverReplayedAutomatically"),
    ("M25 Markdown block quotes not checked",
     "Sources/SylviaAI/Grounding/QuoteVerifier.swift",
     "            found.append((quote, match.range, cited))", "            _ = (quote, cited)",
     "markdownBlockQuotesAreChecked"),
    ("M26 earlier turn from another destination included",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "if !turn.destination.isSameDestination(as: endpoint) {", "if false, !turn.destination.isSameDestination(as: endpoint) {",
     "earlierAnswerBasedOnNotesNeverReachesANewDestination"),
    ("M27 coordinator accepts a pack resending another destination's turn",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "guard pack.historyViolations.isEmpty else { throw AskError.packHistoryInvalid }", "",
     "earlierAnswerBasedOnNotesNeverReachesANewDestination"),
    ("M28 earlier turns' scopes left out of consent",
     "Sources/SylviaAI/Consent/Consent.swift",
     "let scopes = evidenceScopes.union(earlierTurnScopes)", "let scopes = evidenceScopes",
     "earlierTurnsAreDisclosedAndCountTowardsConsent"),
    ("M29 earlier citation markers kept in the pack",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "resent.answer = PromptTemplate.neutralizeCitationMarkers(turn.answer)", "resent.answer = turn.answer",
     "earlierCitationIDsAreNeverResentOrResolvedAgainstTheNewPack"),
    ("M30 earlier citation markers resent by the template",
     "Sources/SylviaAI/Grounding/PromptTemplate.swift",
     "text: neutralizeCitationMarkers(turn.answer)", "text: turn.answer",
     "earlierCitationIDsAreNeverResentOrResolvedAgainstTheNewPack"),
    # Added after review round 3.
    ("M31 normal end with no answer text stored as a complete answer",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "            if hasAnswer {\n                record.state = .complete\n                record.outcome = .answer\n            } else if hasRefusal {",
     "            if true {\n                record.state = .complete\n                record.outcome = .answer\n            } else if hasRefusal {",
     "replyWithNoAnswerTextIsNeverComplete"),
    ("M32 text cut off by a content filter kept as complete",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "            // The provider omitted content, so any text before the stop is truncated.\n            record.state = hasAnswer ? .interrupted : .complete",
     "            // The provider omitted content, so any text before the stop is truncated.\n            record.state = .complete",
     "textCutOffByAFilterOrARefusalStopIsAPartialAnswer"),
    ("M33 text before a refusal stop kept as complete",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "            // Text before a refusal stop is cut off where the provider stopped it: a partial answer.\n            record.state = hasAnswer ? .interrupted : .complete",
     "            // Text before a refusal stop is cut off where the provider stopped it: a partial answer.\n            record.state = .complete",
     "finishReasonsMapToHonestStates"),
    ("M34 every complete record reads \"Complete\"",
     "Sources/SylviaAI/Lifecycle/AskRecord.swift",
     "case .complete: return outcome == .answer && hasAnswerText ? \"Complete\" :",
     "case .complete: return true ? \"Complete\" :",
     "finalEventsWithoutAnswerTextAreNeverAnAnswer"),
    ("M35 whitespace alone counted as answer text",
     "Sources/SylviaAI/Lifecycle/AskRecord.swift",
     "public var hasAnswerText: Bool { Self.isVisibleText(answerText) }", "public var hasAnswerText: Bool { !answerText.isEmpty }",
     "finalEventsWithoutAnswerTextAreNeverAnAnswer"),
    ("M36 audio disclosure says the question is sent",
     "Sources/SylviaAI/Consent/Consent.swift",
     "var sent: [String] = content == .question ? [\"your question\"] : []", "var sent: [String] = [\"your question\"]",
     "multipartUploadWithTimingAndProvenance"),
    ("M37 transcription queue kept only in memory",
     "Sources/SylviaAI/Transcription/Transcription.swift",
     "    func persist(_ clipID: UUID) throws {\n        guard let job = jobs[clipID]",
     "    func persist(_ clipID: UUID) throws {\n        guard false, let job = jobs[clipID]",
     "queuedClipSurvivesARelaunchAndIsSentOnlyUnderThePolicy"),
    ("M38 upload cut off by a relaunch not reported as possibly sent",
     "Sources/SylviaAI/Transcription/Transcription.swift",
     "            if case .sending = stored.state {", "            if false, case .sending = stored.state {",
     "uploadCutOffByARelaunchIsNeverResentAutomatically"),
    ("M39 audio consent not stored",
     "Sources/SylviaAI/Transcription/Transcription.swift",
     "        try store.saveConsent(consent)\n", "",
     "queuedClipSurvivesARelaunchAndIsSentOnlyUnderThePolicy"),
    ("M40 audio consent not checked again at send time",
     "Sources/SylviaAI/Transcription/Transcription.swift",
     "        if case .required(let disclosure) = consent.evaluate(endpoint, providerID: config.providerID, scopes: [.audio], content: .audioClip) {\n            job.state = .awaitingAudioConsent(disclosure)",
     "        if false, case .required(let disclosure) = consent.evaluate(endpoint, providerID: config.providerID, scopes: [.audio], content: .audioClip) {\n            job.state = .awaitingAudioConsent(disclosure)",
     "queuedClipWithoutStoredConsentAsksBeforeSending"),
    ("M41 letter case ignored for an exact quotation",
     "Sources/SylviaAI/Grounding/QuoteVerifier.swift",
     "        if foldCase { out = out.lowercased() }", "        out = out.lowercased()",
     "letterCaseIsSignificantForAnExactQuotation"),
    ("M42 the quotation's first letter must match case too",
     "Sources/SylviaAI/Grounding/QuoteVerifier.swift",
     "            let variants = initialCaseVariants(segments)", "            let variants = [segments]",
     "letterCaseIsSignificantForAnExactQuotation"),
    # Added after review round 4.
    ("M43 a second request for a clip being sent uploads it again",
     "Sources/SylviaAI/Transcription/Transcription.swift",
     "            case .awaitingAudioConsent, .queuedOffline, .sending, .complete, .failed(_, _, resendNeedsConfirmation: true): return existing",
     "            case .queuedOffline, .sending: break\n            case .awaitingAudioConsent, .complete, .failed(_, _, resendNeedsConfirmation: true): return existing",
     "concurrentRequestsForOneClipUploadItOnce"),
    ("M44 a second request replaces a finished transcript",
     "Sources/SylviaAI/Transcription/Transcription.swift",
     "            case .awaitingAudioConsent, .queuedOffline, .sending, .complete, .failed(_, _, resendNeedsConfirmation: true): return existing",
     "            case .complete: break\n            case .awaitingAudioConsent, .queuedOffline, .sending, .failed(_, _, resendNeedsConfirmation: true): return existing",
     "correctionSurvivesASecondRequestAndARelaunch"),
    ("M45 uncertain transcription failure resent without confirmation",
     "Sources/SylviaAI/Transcription/Transcription.swift",
     "if needsConfirmation && !userConfirmedResend { throw TranscriptionError.resendNeedsConfirmation }",
     "if false && needsConfirmation && !userConfirmedResend { throw TranscriptionError.resendNeedsConfirmation }",
     "uncertainTranscriptionFailureIsResentOnlyOnConfirmation"),
    ("M46 uncertain transcription failure not marked for confirmation",
     "Sources/SylviaAI/Transcription/Transcription.swift",
     "resendNeedsConfirmation: classified.acceptance == .uncertain)", "resendNeedsConfirmation: false)",
     "uncertainTranscriptionFailureIsResentOnlyOnConfirmation"),
    ("M47 saved thoughts counted as passages from the book",
     "Sources/SylviaAI/Consent/Consent.swift",
     "            case .savedQuote, .userNote, .transcript: thoughts += 1",
     "            case .savedQuote, .userNote, .transcript: thoughts += 1; selected += 1",
     "disclosureCountsPassagesByHowTheyWereChosenAndThoughtsApart"),
    ("M48 retrieved passages described as selected",
     "Sources/SylviaAI/Consent/Consent.swift",
     "                case .retrieved, .adjacent: retrieved += 1",
     "                case .retrieved, .adjacent: selected += 1",
     "disclosureCountsPassagesByHowTheyWereChosenAndThoughtsApart"),
    ("M49 a refusal with no text says its reply is shown",
     "Sources/SylviaAI/Lifecycle/AskRecord.swift",
     "            return Self.isVisibleText(refusalText) ? ", "            return true ? ",
     "finalEventsWithoutAnswerTextAreNeverAnAnswer"),
    ("M50 a failed record without a failure reads \"Draft · not sent\"",
     "Sources/SylviaAI/Lifecycle/AskRecord.swift",
     "case .failedRetryable, .failedFinal: return failure?.userMessage ?? \"No answer\"",
     "case .failedRetryable, .failedFinal: return failure?.userMessage ?? \"Draft · not sent\"",
     "failedStatesNeverFallBackToDraftNotSent"),
    ("M51 a thought on this work is stored without its place",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "position: position, retrieval: nil, captureID: thought.captureID, required: false,",
     "position: nil, retrieval: nil, captureID: thought.captureID, required: false,",
     "restrictedThoughtsBeyondThePositionAreExcluded"),
    ("M52 spoiler self-check skips items from this work without a position",
     "Sources/SylviaAI/Model/ContextPack.swift",
     "            } else if isFromThisWork(item) {", "            } else if false, isFromThisWork(item) {",
     "packWithALaterThoughtIsNeverStored"),
    ("M53 a key is sent to an origin it was not entered for",
     "Sources/SylviaAI/Providers/TextGenerationProvider.swift",
     "        guard ref.origin == origin.description else {", "        guard ref.origin == ref.origin else {",
     "aStoredKeyNeverReachesAnotherOrigin"),
    # Added after review round 5.
    # createDraft looks for an existing record in three places: the cache before any suspension (createDraft), the
    # store (storeDraftIfNew, which also re-checks the cache inside that branch), and the cache again after the store
    # found nothing (a send may have loaded it meanwhile). M54 removes all three, so the mutated code writes a fresh
    # draft over any record, inside one coordinator and after a relaunch alike.
    ("M54 createDraft overwrites an existing record (all three lookups removed)",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     ("        } else if let cached = records[id] {\n            return try existingRecord(cached, for: pack)\n",
      "        if let stored = try await store.load(id) {\n",
      "        if let cached = records[id] { return cached }\n        let now = clock.now()\n"),
     ("        } else if false, let cached = records[id] {\n            return try existingRecord(cached, for: pack)\n",
      "        if false, let stored = try await store.load(id) {\n",
      "        if false, let cached = records[id] { return cached }\n        let now = clock.now()\n"),
     "secondDraftForAnAnsweredRequestKeepsTheAnswer"),
    ("M55 the reconnect loop sends a clip that is no longer queued",
     "Sources/SylviaAI/Transcription/Transcription.swift",
     "            guard policy == .sendWhenOnline, jobs[id]?.state == .queuedOffline else { continue }",
     "            guard policy == .sendWhenOnline else { continue }",
     "reconnectLoopSendsOnlyClipsStillQueued"),
    ("M56 a thought's ordinal is read in another edition",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "if inThisWork, thought.editionID == work.editionID, let ordinal = thought.ordinal {",
     "if inThisWork, let ordinal = thought.ordinal {",
     "thoughtFromAnotherEditionHasNoPlaceInThisOne"),
    ("M57 spoiler self-check accepts a position in another edition",
     "Sources/SylviaAI/Model/ContextPack.swift",
     "                if item.editionID == nil || item.editionID != work?.editionID {",
     "                if false, item.editionID == nil || item.editionID != work?.editionID {",
     "spoilerSelfCheckRefusesAPositionInAnotherEdition"),
    ("M58 a turn counted in another edition enters a restricted pack",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "if boundary.enabled, turn.maxEvidenceOrdinal != nil, !turn.isPlaced(inEdition: work.editionID) {",
     "if false, boundary.enabled, turn.maxEvidenceOrdinal != nil, !turn.isPlaced(inEdition: work.editionID) {",
     "earlierTurnsFromAnotherEditionAreExcluded"),
    # Added after review round 6.
    ("M59 a turn with an unknown place is reported as beyond the position",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "if boundary.enabled, turn.maxEvidenceOrdinal == nil {\n                unknownPlace += 1",
     "if boundary.enabled, turn.maxEvidenceOrdinal == nil {\n                beyondBoundary += 1",
     "earlierTurnsWithAnUnknownPlaceSayWhy"),
    ("M60 turns excluded with no position set are reported as beyond it",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "if boundary.enabled, boundary.basis == .none, turn.maxEvidenceOrdinal != -1 {",
     "if false, boundary.enabled, boundary.basis == .none, turn.maxEvidenceOrdinal != -1 {",
     "earlierTurnsWithoutAPositionToCompareSayWhy"),
    ("M61 a confirmed position from another edition is applied",
     "Sources/SylviaContext/ContextPackBuilder.swift",
     "guard confirmed.editionID == work.editionID else { throw ContextBuildError.confirmedPositionInAnotherEdition }", "",
     "confirmedPositionFromAnotherEditionIsRefused"),
    # Since review round 7 the earlier attempt's projection is cleared in `supersedeEarlierAttempt`, called once before
    # the consent check; M62 now makes that call depend on being online (its round 6 form anchored the inline code).
    ("M62 an offline confirmed resend keeps the earlier answer and failure",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "        Self.supersedeEarlierAttempt(&record)\n        // Consent is re-checked",
     "        if connectivity.isOnline { Self.supersedeEarlierAttempt(&record) }\n        // Consent is re-checked",
     "confirmedResendWhileOfflineIsADraftOfTheResendOnly"),
    # Added after review round 7.
    # M63 restores the round 6 order: the earlier attempt's projection cleared after the consent check.
    ("M63 a resend that needs consent keeps the earlier answer and failure",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     ("        Self.supersedeEarlierAttempt(&record)\n        // Consent is re-checked",
      "        guard connectivity.isOnline else {\n            record.state = .draft"),
     ("        // Consent is re-checked",
      "        Self.supersedeEarlierAttempt(&record)\n        guard connectivity.isOnline else {\n            record.state = .draft"),
     "confirmedResendThatNeedsConsentIsADraftOfTheResendOnly"),
    ("M64 an attempt stopped on the wire records no failure kind or acceptance",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "                closeAttempt(&record, failure: ProviderError(kind: .cancelled, acceptance: .uncertain, host: record.pack.endpoint.host))",
     "                closeAttempt(&record, failure: nil)",
     "confirmedResendWhileOfflineKeepsHowTheEarlierAttemptEnded"),
    ("M65 a relaunch leaves the attempt that was on the wire open, with no ending",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "            if let last = record.attempts.last, last.endedAt == nil {\n                closeAttempt(&record, failure: ProviderError(kind: .connectionLost",
     "            if false, let last = record.attempts.last, last.endedAt == nil {\n                closeAttempt(&record, failure: ProviderError(kind: .connectionLost",
     "confirmedResendWhileOfflineKeepsHowTheEarlierAttemptEnded"),
    ("M66 an answer that stopped without a final event shows no reason",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "                if record.hasAnswerText { record.outcome = .partial }\n                record.failure = FailureSummary(kind: ended.kind",
     "                record.failure = FailureSummary(kind: ended.kind",
     "confirmedResendWhileOfflineKeepsHowTheEarlierAttemptEnded"),
    ("M67 a stream without a final event leaves no ending on its attempt",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "                                                resubmitNeedsConfirmation: true)\n                closeAttempt(&record, failure: ended)",
     "                                                resubmitNeedsConfirmation: true)\n                closeAttempt(&record, failure: nil)",
     "confirmedResendWhileOfflineKeepsHowTheEarlierAttemptEnded"),
    ("M68 an attempt does not record its outcome",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "        record.attempts[last].outcome = record.outcome\n", "",
     "confirmedResendWhileOfflineKeepsHowTheEarlierAttemptEnded"),
    ("M69 an attempt does not record its usage",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "        record.attempts[last].usage = record.usage\n", "",
     "confirmedResendClearsEverythingTheEarlierAttemptLeftOnTheRecord"),
    ("M70 a resend drops the earlier attempt's refusal text",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "            if !record.refusalText.isEmpty { record.attempts[last].supersededRefusalText = record.refusalText }\n", "",
     "confirmedResendClearsEverythingTheEarlierAttemptLeftOnTheRecord"),
    ("M71 a resend shows the earlier attempt's usage as its own",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "        record.usage = nil\n        record.reasoningOmitted = false\n", "        record.reasoningOmitted = false\n",
     "confirmedResendClearsEverythingTheEarlierAttemptLeftOnTheRecord"),
    ("M72 a resend keeps the earlier attempt's reasoning flag",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "        record.reasoningOmitted = false\n", "",
     "confirmedResendClearsEverythingTheEarlierAttemptLeftOnTheRecord"),
    ("M73 a resend keeps the earlier attempt's tool-call flag",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "        record.toolCallRejected = false\n", "",
     "confirmedResendClearsEverythingTheEarlierAttemptLeftOnTheRecord"),
    ("M74 a relaunch during a retry wait says the request may have reached the host",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "            if waitingToRetry && !record.hasAnswerText {", "            if false, waitingToRetry && !record.hasAnswerText {",
     "relaunchWhileWaitingToRetryKeepsTheRefusedAttempt"),
    ("M75 a relaunch overwrites the ending of an attempt that already ended",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "            if let last = record.attempts.last, last.endedAt == nil {", "            if !record.attempts.isEmpty {",
     "relaunchWhileWaitingToRetryKeepsTheRefusedAttempt"),
    ("M76 a stopped retry says the server refused an attempt that never reached it",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "        earlier == .notSent ? ", "        false ? ",
     "relaunchWhileWaitingToRetryKeepsTheRefusedAttempt"),
    ("M77 a retry stopped by the user names the wrong reason",
     "Sources/SylviaAI/Lifecycle/AskCoordinator.swift",
     "userMessage: Self.retryStoppedMessage(host: record.pack.endpoint.host, earlier: error.acceptance),",
     "userMessage: Self.retryStoppedMessage(host: record.pack.endpoint.host, earlier: .rejected),",
     "stopDuringBackoffWaitTakesEffectAndSendsNothingMore"),
]


def main(only: list[str]) -> int:
    """Runs every mutation, or only those whose label starts with one of `only` (for example M18)."""
    survived = 0
    selected = [m for m in MUTATIONS if not only or any(m[0].split(" ")[0] == name for name in only)]
    print(f"{'mutation':58} {'test':62} result")
    for label, relative, old, new, test in selected:
        path = SPIKE / relative
        original = path.read_bytes()
        text = original.decode("utf-8")
        olds, news = (old, new) if isinstance(old, tuple) else ((old,), (new,))
        counts = [text.count(anchor) for anchor in olds]
        if any(count != 1 for count in counts):
            print(f"{label:58} {test:62} ERROR anchor found {counts} times")
            survived += 1
            continue
        mutated = text
        for anchor, replacement in zip(olds, news):
            mutated = mutated.replace(anchor, replacement)
        try:
            path.write_text(mutated, encoding="utf-8")
            try:
                run = subprocess.run(["swift", "test", "--force-resolved-versions", "--filter", test], cwd=SPIKE, capture_output=True, text=True, timeout=600)
                output, returncode = run.stdout + run.stderr, run.returncode
            except subprocess.TimeoutExpired as expired:
                # A hang is not a caught mutation: only a failing expectation counts.
                output = (expired.stdout or b"").decode("utf-8", "replace") if isinstance(expired.stdout, bytes) else (expired.stdout or "")
                returncode = 0
                print(f"    timed out after 600 s")
            # Caught only when the named test itself ran and recorded an issue; a build error does not count.
            failed_lines = [line for line in output.splitlines()
                            if line.startswith("✘ Test") and test in line and "recorded an issue" in line]
            caught = returncode != 0 and bool(failed_lines)
            if not caught and "error:" in output:
                print(f"    build or run error: {[l for l in output.splitlines() if 'error:' in l][:2]}")
        finally:
            path.write_bytes(original)
        if path.read_bytes() != original:
            print(f"FATAL: {relative} not restored")
            return 2
        print(f"{label:58} {test:62} {'caught' if caught else 'SURVIVED'}")
        for line in failed_lines[:2]:
            print(f"    {line[:200]}")
        survived += 0 if caught else 1
    print(f"{len(selected) - survived} of {len(selected)} mutations caught; sources restored")
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
