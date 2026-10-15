import Foundation

/// Builds `Contracts/design/marginalia.v1.json` (plan 4.4.9, Appendix A.5) from the token
/// definitions in this module. Never edit the JSON by hand.
public enum TokenExport {
    public static let schemaVersion = 1
    public static let tokenVersion = "0.3.0"
    public static let relativePath = "Contracts/design/marginalia.v1.json"

    public static func document() -> JSONValue {
        .object([
            ("schema_version", .integer(schemaVersion)),
            ("language", .string("marginalia")),
            ("token_version", .string(tokenVersion)),
            ("generator", .string("Packages/Design: swift run sylvia-design-export write (do not edit by hand)")),
            ("plan_reference", .string("Sylvia V1 iOS implementation plan, draft 0.3, Section 4.4 and Appendix A.5")),
            ("appearances", .array(Appearance.allCases.map { .string($0.rawValue) })),
            ("color", colors()),
            ("contrast", contrast()),
            ("marker", markers()),
            ("capture_kind_mapping", captureKindMapping()),
            ("symbols", symbols()),
            ("status_glyphs", .object(StatusGlyph.allCases.map { ($0.rawValue, .string($0.systemSymbol)) })),
            ("typefaces", typefaces()),
            ("type", typeRoles()),
            ("type_scaling", typeScaling()),
            ("space", space()),
            ("radius", .object(Radius.allCases.map { ($0.rawValue, $0.points.map { .number($0) } ?? .string("full")) })),
            ("hairline", .object([("width", .number(Hairline.width)), ("unit", .string("pt")),
                                  ("color", .string(ColorToken.hairline.reference))])),
            ("elevation", elevation()),
            ("motion", motion()),
            ("cover", cover()),
            ("components", components()),
            ("vocabulary", .object(VocabularyKey.allCases.map { ($0.rawValue, .string($0.text)) })),
            ("vocabulary_entries", vocabularyEntries()),
            ("status_moments", statusMoments()),
            ("import_state_mapping", importStateMapping()),
            ("labels", .object(LabelKey.allCases.map { ($0.rawValue, .string($0.text)) })),
            ("formats", .object(FormatKey.allCases.map { ($0.rawValue, .string($0.text)) })),
            ("lint", lint()),
        ])
    }

    public static func serialized() -> String {
        document().serialized(style: .standard)
    }

    // MARK: Sections

    static func appearanceValues(_ token: ColorToken) -> [(String, JSONValue)] {
        Appearance.allCases.map { ($0.rawValue, .string(token.value(in: $0).hex)) }
    }

    static func colorName(_ token: ColorToken) -> String {
        String(token.reference.dropFirst("color.".count))
    }

    static func colors() -> JSONValue {
        var members: [(String, JSONValue)] = []
        for token in ColorToken.allCases where token.reference.hasPrefix("color.") {
            var entry = appearanceValues(token)
            if !token.value(in: .light).isOpaque {
                entry.append(("alpha", .object(Appearance.allCases.map {
                    ($0.rawValue, .number(token.value(in: $0).alpha))
                })))
            }
            entry.append(("use", .string(token.use)))
            if let derivation = token.derivation { entry.append(("derivation", .string(derivation))) }
            if let listed = Palette.planListedDarkTints[token] {
                entry.append(("plan_listed_dark", .string(listed.hexRGB)))
            }
            members.append((colorName(token), .object(entry)))
        }
        return .object(members)
    }

    static func contrast() -> JSONValue {
        .object([
            ("minimum_ratio", .number(ColorRules.minimumTextContrast)),
            ("minimum_ratio_large_text", .number(ColorRules.minimumLargeTextContrast)),
            ("large_text_minimum_points", .number(ColorRules.largeTextMinimumPointSize)),
            ("method", .string("WCAG 2.x relative luminance contrast on opaque sRGB values, in every appearance")),
            ("pairs", .array(ContrastPairs.all.map { pair in
                .object([("text", .string(pair.foreground.reference)), ("fill", .string(pair.background.reference)),
                         ("text_size", .string(pair.textSize.rawValue)), ("use", .string(pair.use))])
            })),
            ("minimum_ratio_non_text", .number(ColorRules.minimumNonTextContrast)),
            ("component_pairs", .array(ComponentContrastPairs.all.map { componentPairJSON($0) })),
            ("overrides", .array(ContrastOverrides.all.map { o in
                .object([("token", .string(o.token.reference)), ("appearance", .string(o.appearance.rawValue)),
                         ("before", .string(o.before.hexRGB)), ("after", .string(o.after.hexRGB)),
                         ("darkening_step", .integer(o.darkeningStep)), ("reason", .string(o.reason))])
            })),
            ("rules", .object([
                ("derived_dark_tint_opacity", .number(ColorRules.derivedDarkTintOpacity)),
                ("increased_contrast_tint_step", .number(ColorRules.increasedContrastTintStep)),
                ("minimal_darkening", .string("multiply each sRGB channel by 1 - k/100 for k = 1, 2, ...; first k at which every pair using the token passes")),
            ])),
        ])
    }

    /// One entry of `contrast.component_pairs` (`requirement` overrides the pair's own, for the
    /// invalid fixture that exempts a busy state).
    static func componentPairJSON(_ pair: ComponentContrastPair, requirement: String? = nil) -> JSONValue {
        .object([("component", .string(pair.component)), ("state", .string(pair.state)),
                 ("text", .string(pair.foreground.reference)),
                 ("text_appearance", .string(pair.foregroundFromOppositeAppearance ? "opposite" : "same")),
                 ("fill", .string(pair.background.reference)),
                 ("opacity_over_ground", .number(pair.opacity)),
                 ("content", .string(pair.content.rawValue)),
                 ("requirement", .string(requirement ?? pair.requirement.rawValue)),
                 ("use", .string(pair.use))])
    }

    static func markers() -> JSONValue {
        .object(Marker.allCases.map { marker in
            var entry: [(String, JSONValue)] = [
                ("category", .string(marker.category.rawValue)),
                ("capture_kinds", .array(marker.captureKinds.map { .string($0) })),
                ("text", .object(appearanceValues(marker.textColor))),
                ("tint", marker.tint.map { .object(appearanceValues($0)) } ?? .null),
                ("glyph", .string(marker.glyph.identifier)),
                ("glyph_rendering", glyphRendering(marker.glyph)),
                ("label", .string(marker.labelKey.text.uppercased())),
                ("label_key", .string(marker.labelKey.rawValue)),
                ("alternate_labels", .array(marker.alternateLabelKeys.map { .string($0.text.uppercased()) })),
                ("frame", .string(marker.frame.rawValue)),
                ("body", .object([
                    ("face", marker.body.face.map { .string($0.rawValue) } ?? .null),
                    ("roles", .array(marker.body.roles.map { .string($0.rawValue) })),
                    ("weight", marker.body.weight.map { .integer($0) } ?? .null),
                    ("treatment", .string(marker.body.description)),
                ])),
            ]
            entry.append(("filter_label", marker.filterLabelKey.map { .string($0.text) } ?? .null))
            return (marker.rawValue, .object(entry))
        })
    }

    static func glyphRendering(_ glyph: Glyph) -> JSONValue {
        switch glyph {
        case .systemSymbol(let name):
            .object([("kind", .string("system_symbol")), ("name", .string(name))])
        case .customSymbol(let symbol):
            .object([("kind", .string("custom_symbol")), ("name", .string(symbol.rawValue))])
        case .typeset(let text, let face, let equivalent):
            .object([("kind", .string("typeset")), ("text", .string(text)), ("face", .string(face.rawValue)),
                     ("equivalent_symbol", .string(equivalent))])
        }
    }

    static func captureKindMapping() -> JSONValue {
        var members: [(String, JSONValue)] = []
        for marker in Marker.allCases {
            for kind in marker.captureKinds { members.append((kind, .string(marker.rawValue))) }
        }
        return .object([
            ("kinds", .object(members)),
            ("matching", .string("exact, case-sensitive")),
            ("unrecognized", .object([("marker", .string(Marker.pending.rawValue)),
                                      ("label", .string("the raw kind string, or the label empty_label_key when the kind is empty or only white space")),
                                      ("empty_label_key", .string(LabelKey.markerUnknownKind.rawValue)),
                                      ("never", .string(Marker.quote.rawValue))])),
            ("status", .string("text_quote is from plan Appendix A.1; the capture-envelope schema adopts all five kind strings (ADR-0016)")),
        ])
    }

    static func symbols() -> JSONValue {
        .object(CustomSymbol.allCases.map { symbol in
            (symbol.rawValue, .object([
                ("view_box", .array([0, 0, 24, 24].map { .integer($0) })),
                ("stroke_width", .number(1.75)),
                ("line_cap", .string("round")),
                ("line_join", .string("round")),
                ("polylines", .array(symbol.polylines.map { line in
                    .array(line.map { .array([.number($0.x), .number($0.y)]) })
                })),
                ("accessibility_label_key", .string(symbol.accessibilityLabelKey.rawValue)),
                ("board_source", .string(symbol.boardSource)),
            ]))
        })
    }

    static func typefaces() -> JSONValue {
        .object([
            ("literata", .object([
                ("family", .string(LiterataFont.family)),
                ("files", .array(LiterataFont.files.map { .string($0) })),
                ("version", .string(LiterataFont.version)),
                ("license", .string(LiterataFont.license)),
                ("axes", .object([
                    ("wght", .array([.number(LiterataFont.weightAxis.lowerBound), .number(LiterataFont.weightAxis.upperBound)])),
                    ("opsz", .array([.number(LiterataFont.opticalSizeAxis.lowerBound), .number(LiterataFont.opticalSizeAxis.upperBound)])),
                ])),
                ("optical_size", .string("equal to the rendered point size, clamped to the axis")),
                ("role", .string("Everything that belongs to a book")),
            ])),
            ("system", .object([("apple", .string("SF Pro")), ("role", .string("Everything that belongs to the interface"))])),
            ("monospace", .object([("apple", .string("SF Mono")),
                                   ("role", .string("Values compared character by character; tabular figures"))])),
        ])
    }

    static func typeRoles() -> JSONValue {
        .object(TypeRole.allCases.map { role in
            let spec = role.spec
            var entry: [(String, JSONValue)] = [
                ("face", .string(spec.face == .literata ? "Literata" : "system")),
                ("weight", .integer(spec.weight)),
                ("size", .number(spec.size)),
                ("line", .number(spec.lineHeight)),
                ("tracking", .number(spec.tracking)),
                ("maps_to", .string(spec.textStyle.rawValue)),
                ("uppercase", .bool(spec.uppercase)),
                ("usage", .string(spec.usage)),
            ]
            if role == .reading {
                entry.append(("user_range", .array([.number(ReadingSize.range.lowerBound), .number(ReadingSize.range.upperBound)])))
            }
            return (role.rawValue, .object(entry))
        })
    }

    static func typeScaling() -> JSONValue {
        .object([
            ("units", .string("size and line in points at the default Dynamic Type size; tracking as a fraction of the size")),
            ("dynamic_type", .string("each role scales in proportion to its maps_to text style's system size at the current text size (iOS: UIFont.preferredFont); line height and tracking scale in proportion")),
            ("reading", .string("the user's size (within user_range at the default text size) scales with the body style")),
            ("bold_text_weight_increase", .integer(BoldText.weightIncrease)),
            ("maximum_weight", .integer(BoldText.maximumWeight)),
            ("macos", .string("sizes scale by the ratio of the macOS text style's size to the iOS default size")),
        ])
    }

    static func space() -> JSONValue {
        .object([
            ("grid", .number(Spacing.grid)),
            ("steps", .array(Spacing.steps.map { .number($0) })),
            ("gutter_phone", .number(Spacing.gutterPhone)),
            ("gutter_pad", .number(Spacing.gutterPad)),
        ])
    }

    static func elevation() -> JSONValue {
        .object([("shadow", .object([
            ("x", .number(Elevation.shadowX)), ("y", .number(Elevation.shadowY)),
            ("blur", .number(Elevation.shadowBlur)), ("color", .string(ColorToken.shadow.reference)),
            ("components", .array(Elevation.shadowedComponents.map { .string($0) })),
        ]))])
    }

    static func motion() -> JSONValue {
        func spec(_ m: MotionSpec) -> JSONValue {
            .object([("duration_ms", .integer(m.durationMilliseconds)), ("curve", .string(m.curve.rawValue)),
                     ("stated_in_plan", .bool(m.statedInPlan))])
        }
        return .object([
            ("sheet", spec(Motion.sheet)),
            ("highlight", spec(Motion.highlight)),
            ("progress_rule", spec(Motion.progressRule)),
            ("reduce_motion", .string(Motion.reduceMotionRule)),
            ("while_reading", .string(Motion.readingRule)),
        ])
    }

    static func cover() -> JSONValue {
        .object([
            ("fields", .array(ColorToken.coverFields.map { .string($0.reference) })),
            ("title", .string(ColorToken.coverTitle.reference)),
            ("assignment", .string(CoverFields.assignmentRule)),
        ])
    }

    /// Component dimensions and rules (Section 4.4.7; ADR-0013 Section 10). Optional for readers of
    /// v1 (added in token version 0.2.0).
    static func components() -> JSONValue {
        .object([
            ("metrics", .object(ComponentMetrics.all.map { m in
                (m.name, .object([("points", .number(m.points)), ("stated_in_plan", .bool(m.statedInPlan)),
                                  ("use", .string(m.use))]))
            })),
            ("label_weight", .integer(ComponentMetrics.labelWeight)),
            ("waveform_minimum_level", .number(ComponentMetrics.waveformMinimumLevel)),
            ("quiet_label_weight", .integer(ComponentMetrics.quietLabelWeight)),
            ("pressed_opacity", .number(ComponentMetrics.pressedOpacity)),
            ("disabled_opacity", .number(ComponentMetrics.disabledOpacity)),
            ("bar_maximum_text_size", .string(ComponentMetrics.barMaximumTextSize)),
            ("separator", .string(Microcopy.separator)),
            ("cover_layout", .object([
                ("list_aspect_ratio", .number(CoverLayout.listAspectRatio)),
                ("player_aspect_ratio", .number(CoverLayout.playerAspectRatio)),
                ("thumbnail_maximum_width", .number(CoverLayout.thumbnailMaximumWidth)),
                ("title_scale", .number(CoverLayout.titleScale)),
                ("author_scale", .number(CoverLayout.authorScale)),
                ("initial_scale", .number(CoverLayout.initialScale)),
                ("inset_scale", .number(CoverLayout.insetScale)),
                ("minimum_title_scale_factor", .number(CoverLayout.minimumTitleScaleFactor)),
                ("title_weight", .integer(CoverLayout.titleWeight)),
                ("author_weight", .integer(CoverLayout.authorWeight)),
            ])),
            ("rating", .object([
                ("stored_range", .array([.integer(RatingValue.range.lowerBound), .integer(RatingValue.range.upperBound)])),
                ("stars", .integer(RatingValue.starCount)),
                ("cleared", .string("null; never zero")),
                ("glyphs", .object(RatingValue.StarFill.allCases.map { ($0.rawValue, .string($0.systemSymbol)) })),
            ])),
            ("audio_range", .object([
                ("default_length_ms", .integer(Int(AudioRange.defaultLengthMilliseconds))),
                ("maximum_length_ms", .integer(Int(AudioRange.maximumLengthMilliseconds))),
                ("minimum_length_ms", .integer(Int(AudioRange.minimumLengthMilliseconds))),
                ("step_ms", .integer(Int(AudioRange.stepMilliseconds))),
            ])),
            ("control_symbols", .object(ControlSymbol.allCases.map { symbol in
                (snakeCase("\(symbol)"), .object([("glyph", .string(symbol.systemName)), ("use", .string(symbol.use))]))
            })),
            ("glyph_text", .object([("reader_settings", .string(GlyphText.readerSettings))])),
            ("button_roles", .object(ComponentRoles.buttons.map { role in
                (role.name, .object([
                    ("text", .string(role.text.reference)),
                    ("fill", role.fill.map { .string($0.reference) } ?? .null),
                    ("border", role.border.map { .string($0.reference) } ?? .null),
                    ("minimum_height", .number(role.minimumHeight)),
                ]))
            })),
        ])
    }

    /// "areaLibrary" -> "area_library".
    static func snakeCase(_ name: String) -> String {
        name.reduce(into: "") { result, c in
            if c.isUppercase { result += "_" + c.lowercased() } else { result.append(c) }
        }
    }

    static func vocabularyEntries() -> JSONValue {
        .object(VocabularyKey.allCases.map { key in
            var entry: [(String, JSONValue)] = [
                ("moment", .string(key.moment.rawValue)),
                ("placeholders", .array(key.placeholders.map { p in
                    .object([("name", .string(p.name)), ("kind", .string(p.kind.rawValue)), ("meaning", .string(p.meaning))])
                })),
            ]
            if let plural = key.plural {
                entry.append(("plural", .object([("placeholder", .string(plural.placeholder)),
                                                 ("one", .string(plural.one)), ("other", .string(plural.other))])))
            }
            entry.append(("source", .string(key.source)))
            return (key.rawValue, .object(entry))
        })
    }

    static func statusMoments() -> JSONValue {
        .object(StatusMoment.allCases.map { moment in
            (moment.rawValue, .object([
                ("title", .string(moment.title)),
                ("state_machine", .string(moment.stateMachine)),
                ("phrases", .array(moment.entries.map { .string($0.rawValue) })),
                ("forbidden", .array(moment.forbidden.map { rule in
                    .object([("kind", .string(rule.kind.rawValue)), ("text", .string(rule.text)),
                             ("qualifier", rule.qualifier.map { .string($0) } ?? .null)])
                })),
            ]))
        })
    }

    static func importStateMapping() -> JSONValue {
        .object(ImportState.allCases.map { state in
            guard let p = state.presentation() else {
                return (state.rawValue, .object([("shown", .bool(false)), ("note", .string("leaves the Inbox"))]))
            }
            var entry: [(String, JSONValue)] = [
                ("shown", .bool(true)),
                ("phrase", .string(p.phrase.rawValue)),
            ]
            if let indexing = state.presentation(indexingContinues: true), indexing.phrase != p.phrase {
                entry.append(("phrase_while_indexing", .string(indexing.phrase.rawValue)))
            }
            entry += [
                ("glyph", .string(p.glyph.rawValue)),
                ("text", .string(p.textColor.reference)),
                ("fill", .string(p.fill.reference)),
                ("requires_reason_and_next_step", .bool(p.requiresReasonAndNextStep)),
            ]
            return (state.rawValue, .object(entry))
        })
    }

    /// Phrase lists for `Scripts/lint-design.py` and T54.
    public static func permittedPhrases() -> [String] {
        VocabularyKey.allCases.flatMap(\.englishForms)
    }

    public static func forbiddenPhrases() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for moment in StatusMoment.allCases {
            for rule in moment.forbidden where rule.kind == .phrase && seen.insert(rule.text).inserted {
                result.append(rule.text)
            }
        }
        return result
    }

    static func lint() -> JSONValue {
        .object([
            ("permitted_phrases", .array(permittedPhrases().map { .string($0) })),
            ("forbidden_phrases", .array(forbiddenPhrases().map { .string($0) })),
            ("placeholder_syntax", .string("{name} matches any text")),
        ])
    }
}
