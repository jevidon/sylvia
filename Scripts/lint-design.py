#!/usr/bin/env python3
"""Design-system checks for Sylvia (plan Sections 4.4.9, 20.1, 22.2; ADR-0013).

Subcommands
  lint [--root DIR] [PATH ...]
      Rejects literal colors, font sizes and status phrases in product UI targets. With no PATH,
      scans the UI targets under --root (default: the repository root):
        * Apps/** (every app and extension target), and
        * every package under Packages/ other than Packages/Design whose Swift sources import
          SwiftUI, UIKit or AppKit (a "UI package"),
      excluding Spikes/, Packages/Design/, build products and test directories (*Tests/).
      A PATH given explicitly must exist, must not be excluded and must contain at least one Swift
      or strings file; otherwise the lint exits 2 instead of reporting "0 finding(s)".
      Code rules run over the whole comment-free file, so a call wrapped over several lines
      (".font(.system(\n size: 13))", "Color(\n red: ...)") is one match, reported on the line
      where it starts. Rules:
        hex-color       a hex color string ("#F4F2ED", "#FFF", "#F4F2EDAA"), #colorLiteral(...),
                         a Color/UIColor/NSColor/CGColor/CIColor(hex:) call, or a 6/8-digit 0x
                         integer on a line that mentions color
        color-components Color/UIColor/NSColor/CGColor/CIColor component initializers, also
                         spelled Color.init(...) or a bare .init(...) (red:, white:, hue:,
                         displayP3Red:, srgbRed:, calibrated*, device*, linear*/extended*; with a
                         color type also gray: and colorSpace:)
        named-color      a named system color: Color/UIColor/NSColor/CGColor/CIColor.<member>
                         (Color.red, UIColor.label, NSColor.labelColor; Color.clear is allowed, it
                         draws nothing), any .system<Color> name (.systemBlue, .systemBackground),
                         a bare palette or hierarchical name (.red, .black, .secondary,
                         .accentColor, ...) as the argument of a color modifier (foregroundStyle,
                         background, fill, stroke, tint, ...) or a color:/tint:/fill: (...) label, a bare
                         palette name followed by .opacity/.gradient/.mix/.shadow, a palette name as
                         a ternary branch in a color modifier's arguments (on ? .red : .blue), a
                         named color typed as a color (let c: Color = .red, : UIColor = .label,
                         var c: Color { .red }), bridged (Color(uiColor: .label), Color(.label)),
                         assigned to a color property (view.backgroundColor = .white) or passed
                         to a color setter (setTitleColor(.white, for:)), and a color looked up by
                         a string name (Color("Name"), UIColor(named:))
        color-provider   a dynamic color built in a UI target (UIColor { traits in ... },
                         UIColor(dynamicProvider:), NSColor(name:dynamicProvider:))
        font-size        Font.system(size:) / .system(size:), any *Font(ofSize:) factory
                         (systemFont, boldSystemFont, monospacedDigitSystemFont, NSFont.userFont,
                         ...), UIFont/NSFont (name:size:) and (descriptor:size:) (also .init),
                         UIFontDescriptor/NSFontDescriptor(name:size:), .custom(_:size:),
                         .custom(_:fixedSize:), .withSize(_:), a size in font descriptor
                         attributes ([.size: 22], AttributeName.size, kCTFontSizeAttribute),
                         CTFontCreate*(...) and CTFontDescriptorCreate*Size*(...)
        status-phrase    a string literal that is a permitted vocabulary phrase (also with leading
                         or trailing punctuation, symbols or Markdown: "Saved.", "Ready!", "Saved ✓",
                         "**Saved**", "_Done_", "[Saved](url)"), has a
                         punctuation-separated segment that is one ("Error: ...", "Title · Ready"),
                         or contains a multi-word one ({name} placeholders match any text,
                         including Swift interpolation)
        forbidden-phrase the same for a phrase the vocabulary forbids ("Done!", "Downloading…",
                         "Error: the file could not be read")
        color-asset      a .colorset in a UI target (colors come only from Packages/Design)
      Phrase lists come from Contracts/design/marginalia.v1.json (lint.permitted_phrases and
      lint.forbidden_phrases), the export generated from Packages/Design. Matching ignores case,
      treats "..." as "…" and collapses whitespace. Comments are ignored.
      Not caught (review, not lint; ADR-0013 Section 8 has the full list): colors and sizes
      computed at run time from non-literal values (for example a size read from a variable and
      passed to a role-free API the rules above do not name), a palette name passed to a parameter
      the rules do not name (MyView(highlight: .red)) or returned from a multi-statement body,
      and status text assembled from fragments that are not phrases on their own.
  self-test
      Runs the linter over Packages/Design/LintFixtures: every file under violating/ must produce
      exactly the findings its "lint-expect: <rule>" comments name (one per marked line), and every
      file under clean/ must produce none.
  contrast [--export FILE] [--out FILE]
      Independently recomputes WCAG 2.x contrast for every pair in the export's contrast.pairs in
      every appearance, fails on any pair under its threshold, and writes a Markdown table.
  fixtures
      Checks that each invalid design-token fixture differs from the valid export at exactly one
      location and fails schema validation only there (Contracts/README.md: one reason per file).

Exit status is non-zero on any finding or failure.
"""
from __future__ import annotations

import argparse
import bisect
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPORT = ROOT / "Contracts" / "design" / "marginalia.v1.json"
LINT_FIXTURES = ROOT / "Packages" / "Design" / "LintFixtures"
UI_IMPORT_RE = re.compile(r"^\s*(@preconcurrency\s+)?import\s+(SwiftUI|UIKit|AppKit)\b", re.M)
EXCLUDED_PARTS = {".build", "DerivedData", ".swiftpm", "node_modules"}


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str
    detail: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: {self.rule}: {self.detail}"


# ---------------------------------------------------------------------------------------------
# Swift lexing: separate code, string literals and comments.

@dataclass
class StringLiteral:
    text: str  # contents with interpolations replaced by "{}"
    line: int


def lex_swift(source: str) -> tuple[str, list[StringLiteral]]:
    """Returns (code with comments removed and string contents blanked, string literals)."""
    code: list[str] = []
    strings: list[StringLiteral] = []
    i, n, line = 0, len(source), 1

    def count_newlines(s: str) -> int:
        return s.count("\n")

    while i < n:
        c = source[i]
        if source.startswith("//", i):
            j = source.find("\n", i)
            j = n if j == -1 else j
            i = j
            continue
        if source.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if source.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif source.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            newlines = count_newlines(source[i:j])
            code.append("\n" * newlines)
            line += newlines
            i = j
            continue
        # Raw string delimiters: #"..."#, ##"..."##, #"""..."""#
        m = re.match(r'(#*)("""|")', source[i:])
        if c in '#"' and m and (m.group(1) or c == '"'):
            hashes, quote = m.group(1), m.group(2)
            start_line = line
            j = i + len(hashes) + len(quote)
            text, j, consumed = read_string_body(source, j, quote, hashes)
            strings.append(StringLiteral(text, start_line))
            newlines = count_newlines(consumed)
            code.append('""' + "\n" * newlines)
            line += newlines
            i = j
            continue
        if c == "\n":
            line += 1
        code.append(c)
        i += 1
    return "".join(code), strings


def read_string_body(source: str, j: int, quote: str, hashes: str) -> tuple[str, int, str]:
    """Reads from just after the opening delimiter. Returns (text, index after close, raw span)."""
    start = j
    closing = quote + hashes
    escape = "\\" + hashes
    out: list[str] = []
    n = len(source)
    while j < n:
        if source.startswith(closing, j):
            return "".join(out), j + len(closing), source[start:j + len(closing)]
        if quote == '"' and source[j] == "\n":
            # Unterminated single-line literal; stop at the line end.
            return "".join(out), j, source[start:j]
        if source.startswith(escape + "(", j):
            # Interpolation: skip a balanced parenthesised expression (strings inside included).
            k = j + len(escape) + 1
            depth = 1
            while k < n and depth:
                ch = source[k]
                if ch == '"':
                    m = re.match(r'("""|")', source[k:])
                    _, k, _ = read_string_body(source, k + len(m.group(1)), m.group(1), "")
                    continue
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                k += 1
            out.append("{}")
            j = k
            continue
        if source.startswith(escape, j) and j + len(escape) < n:
            nxt = source[j + len(escape)]
            mapping = {"n": "\n", "t": "\t", "0": "\0", "\\": "\\", '"': '"', "'": "'", "r": "\r"}
            if nxt == "u":
                m = re.match(r"u\{([0-9A-Fa-f]{1,8})\}", source[j + len(escape):])
                if m:
                    out.append(chr(int(m.group(1), 16)))
                    j += len(escape) + len(m.group(0))
                    continue
            out.append(mapping.get(nxt, nxt))
            j += len(escape) + 1
            continue
        out.append(source[j])
        j += 1
    return "".join(out), j, source[start:j]


# ---------------------------------------------------------------------------------------------
# Rules

HEX_STRING_RE = re.compile(r"^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")
COLOR_TYPES = r"(?:Color|UIColor|NSColor|CGColor|CIColor)"
# Component labels of every Color/UIColor/NSColor/CGColor/CIColor initializer that builds a color
# from numbers. "gray:" and "colorSpace:" only with an explicit color type (a bare .init(gray:) or
# .init(colorSpace:) could be another type).
COMPONENT_NAMES = (r"red|white|hue|displayP3Red|srgbRed|calibratedRed|deviceRed|calibratedWhite|"
                   r"deviceWhite|calibratedHue|deviceHue|genericGrayGamma2_2Gray|deviceCyan|"
                   r"linearRed|extendedRed|extendedSRGBRed")
# Named system colors (plan 4.4.9 and CLAUDE.md: product UI never declares a literal color; a named
# system color is one). `clear` is allowed: it draws nothing and is the layout-spacer idiom.
PALETTE = (r"(?:red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|gray|grey|"
           r"black|magenta|darkGray|lightGray|primary|secondary|tertiary|quaternary|quinary|accentColor)")
SYSTEM_COLOR = (r"system(?:Red|Orange|Yellow|Green|Mint|Teal|Cyan|Blue|Indigo|Purple|Pink|Brown|Gray[2-6]?|"
                r"Background|SecondaryBackground|TertiaryBackground|GroupedBackground|"
                r"SecondaryGroupedBackground|TertiaryGroupedBackground|Fill|SecondaryFill|TertiaryFill|"
                r"QuaternaryFill)\b")
COLOR_MODIFIERS = (r"(?:foregroundStyle|foregroundColor|background|backgroundStyle|fill|stroke|"
                   r"strokeBorder|tint|accentColor|border|listRowBackground|listRowSeparatorTint|overlay|"
                   r"colorMultiply|toolbarBackground|containerBackground|shadow)")
COLOR_CONTEXT = (rf"(?:\b{COLOR_MODIFIERS}\s*\(\s*(?:[\w.]+\s*,\s*)?"
                 r"|\b(?:color|tint|foreground|background|fill|stroke)\s*:\s*)")
# UIKit and AppKit semantic color names (UIColor.label, NSColor.labelColor, ...) in addition to the
# palette, for places where the type is a UIKit or AppKit color: Color(uiColor: .label),
# `: UIColor = .label`, `view.backgroundColor = .label`.
PLATFORM_NAMES = (r"(?:label|secondaryLabel|tertiaryLabel|quaternaryLabel|link|placeholderText|separator|"
                  r"opaqueSeparator|darkText|lightText|\w+Color)")
NAMED = rf"(?:{PALETTE}|{PLATFORM_NAMES})"
# Code rules are searched in the whole comment-free file, so a call split across lines ("Color(\n
# red: ...)", ".font(.system(\n size: 13))") is still one match; `\s*` spans line breaks. A finding
# is reported on the line where the match starts.
CODE_RULES: list[tuple[str, re.Pattern[str], str]] = [
    ("hex-color", re.compile(r"#colorLiteral\s*\("), "#colorLiteral"),
    ("hex-color", re.compile(rf"\b{COLOR_TYPES}\s*(?:\.init)?\s*\(\s*hex\s*:"), "hex color initializer"),
    ("color-components", re.compile(
        rf"\b{COLOR_TYPES}\s*(?:\.\s*init)?\s*\(\s*(?:\.\w+\s*,\s*)?"
        rf"(?:{COMPONENT_NAMES}|gray|colorSpace)\s*:"), "color component initializer"),
    ("color-components", re.compile(
        rf"(?<![\w])\.\s*init\s*\(\s*(?:\.\w+\s*,\s*)?(?:{COMPONENT_NAMES})\s*:"),
     "color component initializer (.init)"),
    ("named-color", re.compile(rf"\b{COLOR_TYPES}\s*\.\s*(?!clear\b|init\b|self\b)[a-z]\w*"), "named system color"),
    ("named-color", re.compile(rf"\.\s*{SYSTEM_COLOR}"), "named system color"),
    ("named-color", re.compile(rf"{COLOR_CONTEXT}\.\s*{PALETTE}\b(?!\s*\()"), "named system color"),
    ("named-color", re.compile(rf"(?<![\w])\.\s*{PALETTE}\s*\.\s*(?:opacity|gradient|mix|shadow)\b"),
     "named system color"),
    ("named-color", re.compile(rf"\b(?:Color|UIColor|NSColor)\s*(?:\.init)?\s*\(\s*(?:named\s*:\s*)?\"\""),
     "color looked up by name (colors come only from Packages/Design)"),
    # Color(uiColor: .label), Color(.label), UIColor(cgColor: .black): a named color of the bridged
    # type. The color-space argument of Color(.sRGB, red:...) is not a color.
    ("named-color", re.compile(
        rf"\b{COLOR_TYPES}\s*(?:\.\s*init)?\s*\(\s*(?:(?:uiColor|nsColor|cgColor|ciColor|color)\s*:\s*)?"
        rf"\.\s*(?!init\b|sRGB\b|sRGBLinear\b|displayP3\b){NAMED}\b(?!\s*\()"), "named system color (bridged)"),
    # let c: Color = .red; let u: UIColor = .label; var c: Color { .red }; func c() -> Color { return .red }
    ("named-color", re.compile(rf"(?::|->)\s*Color\s*\??\s*(?:=|\{{\s*(?:return\s+)?)\s*\.\s*{PALETTE}\b(?!\s*\()"),
     "named system color (typed as Color)"),
    ("named-color", re.compile(rf"(?::|->)\s*(?:UIColor|NSColor|CGColor|CIColor)\s*!?\??\s*(?:=|\{{\s*(?:return\s+)?)"
                               rf"\s*\.\s*{NAMED}\b(?!\s*\()"), "named system color (typed as a platform color)"),
    # view.backgroundColor = .label, label.textColor = .white, layer.borderColor = .black
    ("named-color", re.compile(rf"\b\w*[cC]olor\s*=\s*\.\s*(?!init\b|clear\b){NAMED}\b(?!\s*\()"),
     "named system color assigned to a color property"),
    # button.setTitleColor(.white, for: .normal)
    ("named-color", re.compile(rf"\bset\w*Color\s*\(\s*\.\s*(?!init\b|clear\b){NAMED}\b(?!\s*\()"),
     "named system color passed to a color setter"),
    ("font-size", re.compile(r"\.system\s*\(\s*size\s*:"), "Font.system(size:)"),
    # systemFont, boldSystemFont, monospacedSystemFont, NSFont.userFont, labelFont, ... (ofSize:)
    ("font-size", re.compile(r"\.\s*\w*[fF]ont\s*\(\s*ofSize\s*:"), "font(ofSize:)"),
    ("font-size", re.compile(r"\b(?:UIFont|NSFont|UIFontDescriptor|NSFontDescriptor)\s*(?:\.\s*init)?\s*\("
                             r"\s*(?:name|descriptor)\s*:"), "UIFont/NSFont(name:size:)"),
    ("font-size", re.compile(r"\.\s*withSize\s*\("), "font .withSize(_:)"),
    ("font-size", re.compile(r"\bCTFont(?:Create\w*|DescriptorCreate\w*Size\w*)\s*\("), "Core Text font with a size"),
    # A size in a font descriptor's attributes: [.size: 22], UIFontDescriptor.AttributeName.size,
    # kCTFontSizeAttribute.
    ("font-size", re.compile(r"[\[,]\s*\.\s*size\s*:"), "font descriptor size attribute"),
    ("font-size", re.compile(r"\bAttributeName\s*\.\s*size\b|\bkCTFontSizeAttribute\b"),
     "font descriptor size attribute"),
]
# Calls whose balanced argument list is examined (see call_arguments): Font.custom(...) and a bare
# .init(name:|descriptor: ...) with a size label anywhere in the arguments, and a color modifier
# whose top-level arguments hold a palette name as a ternary branch (`on ? .red : .blue`).
CUSTOM_FONT_RE = re.compile(r"\.\s*custom\s*\(")
BARE_FONT_INIT_RE = re.compile(r"(?<![\w])\.\s*init\s*\(\s*(?=(?:name|descriptor)\s*:)")
SIZE_LABEL_RE = re.compile(r"\b(?:size|fixedSize)\s*:")
COLOR_MODIFIER_CALL_RE = re.compile(rf"\b{COLOR_MODIFIERS}\s*\(")
# A ternary branch: "?" or ":" with white space before it (a label's colon has none).
TERNARY_PALETTE_RE = re.compile(rf"\s[?:]\s*\.\s*{PALETTE}\b(?!\s*\()")
# `: Color = cond ? .red : .blue` and the same for platform colors.
TYPED_COLOR_ASSIGNMENT_RE = re.compile(r"(?::|->)\s*(?:Color|UIColor|NSColor|CGColor|CIColor)\s*[!?]?\s*=")
HEX_INT_RE = re.compile(r"\b0x(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})\b")
# A dynamic color built in a UI target: UIColor { traits in ... }, UIColor(dynamicProvider:),
# NSColor(name:dynamicProvider:). Appearance variants come only from the asset catalog.
COLOR_PROVIDER_RE = re.compile(r"\b(?:UIColor|NSColor)\s*(?:\.\s*init)?\s*(?:\{|\(\s*(?:name\s*:[^()]*?,\s*)?dynamicProvider\s*:)")
COLOR_PROVIDER_PRECEDERS = re.compile(r"(?:[=(\[,?]|\breturn|\bin)\s*$")

# Punctuation and symbols that end or separate a phrase in UI text ("Saved.", "Error: ...",
# "Done!", "Saved ✓", "Ready · 3 new"), and the Markdown emphasis characters that SwiftUI renders
# from a literal ("**Saved**", "_Done_", "~~Ready~~", "`Saved`"). Stripped before the
# whole-string comparison, and used to split a literal into segments for single-word phrases.
EDGE_CHARS = ".,!?:;…·•|—–✓✔✗✘×\"'“”‘’()[]*_~` \t\n"
SEGMENT_SPLIT = re.compile(r"\s*(?:[·•|—–✓✔✗✘×]+|[.,!?:;…]+(?=\s|$)|(?:^|(?<=\s))[.,!?:;…]+)\s*")
# Markdown that SwiftUI's Text renders from a literal: a link's visible text, and emphasis, strike
# and code markers around words.
MARKDOWN_LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")
MARKDOWN_MARKS_RE = re.compile(r"(?<![\w*~`])(\*{1,3}|_{1,3}|~~|`+)(?=\S)(.+?)(?<=\S)\1(?![\w*~`])")


def strip_markdown(text: str) -> str:
    """The text SwiftUI shows for a Markdown literal: link text kept, emphasis, strike and code
    markers around words removed ("**Not saved** · your text is still here")."""
    previous = None
    text = MARKDOWN_LINK_RE.sub(r"\1", text)
    while previous != text:
        previous, text = text, MARKDOWN_MARKS_RE.sub(r"\2", text)
    return text


def normalize(text: str) -> str:
    text = text.replace("...", "…")
    text = re.sub(r"\{[A-Za-z_]*\}", "{}", text)
    return re.sub(r"\s+", " ", text).strip().lower()


def strip_edges(text: str) -> str:
    """Normalized text without leading and trailing punctuation and symbols."""
    return text.strip(EDGE_CHARS)


def segments(text: str) -> list[str]:
    """Normalized text split at punctuation that separates phrases (": ", ". ", " · ", "!")."""
    return [s for s in (part.strip(EDGE_CHARS) for part in SEGMENT_SPLIT.split(text)) if s]


def phrase_regex(phrase: str, stripped: bool = False) -> re.Pattern[str]:
    text = normalize(phrase)
    parts = (strip_edges(text) if stripped else text).split("{}")
    return re.compile("^" + ".+".join(re.escape(p) for p in parts) + "$")


def contains_regex(phrase: str) -> re.Pattern[str]:
    parts = normalize(phrase).split("{}")
    body = ".+".join(re.escape(p) for p in parts)
    return re.compile(r"(?<![\w])" + body + r"(?![\w])")


class PhraseMatcher:
    def __init__(self, export_path: Path):
        data = json.loads(export_path.read_text(encoding="utf-8"))
        self.permitted = list(data["lint"]["permitted_phrases"])
        self.forbidden = list(data["lint"]["forbidden_phrases"])
        self.exact = [(p, phrase_regex(p), "status-phrase") for p in self.permitted]
        self.exact += [(p, phrase_regex(p), "forbidden-phrase") for p in self.forbidden]
        # The same phrases without their edge punctuation ("Saving…" is also "Saving"), compared
        # with the literal's own edges stripped and with each punctuation-separated segment.
        self.stripped = [(p, phrase_regex(p, stripped=True), rule) for p, _, rule in self.exact]
        multi = lambda p: len(normalize(p).replace("{}", " ").split()) >= 2
        self.contained = [(p, contains_regex(p), "status-phrase") for p in self.permitted if multi(p)]
        self.contained += [(p, contains_regex(p), "forbidden-phrase") for p in self.forbidden if multi(p)]

    def match(self, literal: str) -> tuple[str, str] | None:
        """The rule and phrase a literal matches, if any:
        * the whole literal is a phrase ("Saved"), also after stripping edge punctuation and
          symbols ("Saved.", "Done!", "Downloading…", "“Ready”");
        * a segment between separating punctuation is a phrase ("Error: the file could not be
          read", "Upload finished. Done!", "Saved ✓", "Title · Ready"); a separator is ":", ";",
          ",", ".", "!", "?" or "…" next to a space or the string's end, or one of "·", "•", "|",
          "—", "–", "✓", "✔", "✗", "×"; so "ask.generated" and "Done reading" are not split;
        * the literal contains a multi-word phrase as words ("Upload finished. Not saved · your
          text is still here").
        """
        text = normalize(strip_markdown(literal))
        if not strip_edges(text) or strip_edges(text) == "{}":
            return None
        for phrase, regex, rule in self.exact:
            if regex.match(text):
                return rule, phrase
        candidates = [strip_edges(text)] + segments(text)
        for candidate in candidates:
            if candidate == "{}":
                continue
            for phrase, regex, rule in self.stripped:
                if regex.match(candidate):
                    return rule, phrase
        for phrase, regex, rule in self.contained:
            if regex.search(text):
                return rule, phrase
        return None


def call_arguments(code: str, open_paren: int) -> str:
    """The text between the "(" at `open_paren` and its matching ")" (to the end of the file if it
    is unbalanced). Brackets and braces nest too."""
    depth, i, n = 0, open_paren, len(code)
    while i < n:
        ch = code[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return code[open_paren + 1:i]
        i += 1
    return code[open_paren + 1:]


def top_level(arguments: str) -> str:
    """The arguments with every nested (), [] and {} group blanked to spaces (line breaks kept), so
    offsets stay valid and a label inside a nested call is not mistaken for a ternary branch."""
    out, depth = [], 0
    for ch in arguments:
        if ch in "([{":
            depth += 1
            out.append(" ")
        elif ch in ")]}":
            depth = max(depth - 1, 0)
            out.append(" ")
        else:
            out.append(ch if depth == 0 or ch == "\n" else " ")
    return "".join(out)


def statement_end(code: str, start: int) -> int:
    """The end of the statement that continues at `start`: the first line break or ";" outside
    brackets (a statement continued on the next line with an operator is not followed)."""
    depth, i, n = 0, start, len(code)
    while i < n:
        ch = code[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                return i
            depth -= 1
        elif ch in "\n;" and depth == 0:
            return i
        i += 1
    return n


def lint_swift(path: Path, display: str, matcher: PhraseMatcher) -> list[Finding]:
    source = path.read_text(encoding="utf-8", errors="replace")
    code, strings = lex_swift(source)
    findings: list[Finding] = []
    seen: set[tuple[int, str]] = set()
    line_starts = [0] + [m.end() for m in re.finditer(r"\n", code)]

    def report(offset: int, rule: str, detail: str) -> None:
        number = bisect.bisect_right(line_starts, offset)
        if (number, rule) not in seen:  # one finding per rule and line
            seen.add((number, rule))
            findings.append(Finding(display, number, rule, detail))

    # The code rules run over the whole file (comments removed, string contents blanked, line
    # breaks kept), so a call wrapped over several lines is one match.
    for rule, regex, detail in CODE_RULES:
        for m in regex.finditer(code):
            report(m.start(), rule, detail)
    for m in CUSTOM_FONT_RE.finditer(code):
        if SIZE_LABEL_RE.search(call_arguments(code, m.end() - 1)):
            report(m.start(), "font-size", "Font.custom(_:size:)")
    for m in BARE_FONT_INIT_RE.finditer(code):
        if re.search(r"\bsize\s*:", call_arguments(code, code.index("(", m.start()))):
            report(m.start(), "font-size", "font .init(name:size:)")
    for m in COLOR_MODIFIER_CALL_RE.finditer(code):
        arguments = top_level(call_arguments(code, m.end() - 1))
        for t in TERNARY_PALETTE_RE.finditer(arguments):
            report(m.end() + t.start(), "named-color", "named system color (conditional)")
    for m in TYPED_COLOR_ASSIGNMENT_RE.finditer(code):
        expression = top_level(code[m.end():statement_end(code, m.end())])
        for t in TERNARY_PALETTE_RE.finditer(expression):
            report(m.end() + t.start(), "named-color", "named system color (conditional)")
    for m in COLOR_PROVIDER_RE.finditer(code):
        # UIColor { ... } as a value, not `extension UIColor {` or `-> UIColor {`.
        if COLOR_PROVIDER_PRECEDERS.search(code[max(0, m.start() - 40):m.start()]):
            report(m.start(), "color-provider", "dynamic color built outside Packages/Design")
    for number, text in enumerate(code.split("\n"), start=1):
        if HEX_INT_RE.search(text) and re.search(r"colou?r", text, re.I):
            findings.append(Finding(display, number, "hex-color", "hex integer color"))
    for literal in strings:
        if HEX_STRING_RE.match(literal.text.strip()):
            findings.append(Finding(display, literal.line, "hex-color", f'"{literal.text}"'))
            continue
        hit = matcher.match(literal.text)
        if hit:
            findings.append(Finding(display, literal.line, hit[0], f'"{literal.text}" matches "{hit[1]}"'))
    return sorted(findings, key=lambda f: f.line)


def lint_strings_file(path: Path, display: str, matcher: PhraseMatcher) -> list[Finding]:
    findings: list[Finding] = []
    values: list[str] = []
    if path.suffix == ".xcstrings":
        data = json.loads(path.read_text(encoding="utf-8"))
        for key, entry in data.get("strings", {}).items():
            values.append(key)
            for loc in entry.get("localizations", {}).values():
                unit = loc.get("stringUnit", {})
                if "value" in unit:
                    values.append(unit["value"])
    else:
        values = re.findall(r'"((?:[^"\\]|\\.)*)"', path.read_text(encoding="utf-8", errors="replace"))
    for value in values:
        cleaned = re.sub(r"%(\d+\$)?[@dDuUxXoOfFeEgGcCsSpaA]|%(\d+\$)?l{1,2}[dDuUxX]", "{}", value)
        hit = matcher.match(cleaned)
        if hit:
            findings.append(Finding(display, 1, hit[0], f'"{value}" matches "{hit[1]}"'))
    return findings


def is_excluded(rel: Path) -> bool:
    parts = rel.parts
    if not parts:
        return False
    if parts[0] == "Spikes" or parts[:2] == ("Packages", "Design"):
        return True
    return any(p in EXCLUDED_PARTS or p.endswith("Tests") or p.endswith(".xcodeproj") for p in parts)


def ui_roots(root: Path) -> list[Path]:
    roots: list[Path] = []
    if (root / "Apps").is_dir():
        roots.append(root / "Apps")
    packages = root / "Packages"
    if packages.is_dir():
        for package in sorted(p for p in packages.iterdir() if p.is_dir() and p.name != "Design"):
            sources = [f for f in package.rglob("*.swift") if not is_excluded(f.relative_to(root))]
            if any(UI_IMPORT_RE.search(f.read_text(encoding="utf-8", errors="replace")) for f in sources):
                roots.append(package)
    return roots


def lint_paths(paths: list[Path], root: Path, matcher: PhraseMatcher, apply_exclusions: bool,
               count: bool = False):
    """Findings for every Swift and strings file under the paths (and, with count, how many
    such files were checked)."""
    findings: list[Finding] = []
    files: list[Path] = []
    for base in paths:
        candidates = [base] if base.is_file() else [base] + sorted(base.rglob("*"))
        for f in candidates:
            try:
                rel = f.resolve().relative_to(root.resolve())
            except ValueError:
                rel = f
            if apply_exclusions and is_excluded(rel):
                continue
            if f.is_dir() and f.suffix == ".colorset":
                findings.append(Finding(str(rel), 1, "color-asset", "color set outside Packages/Design"))
            elif f.is_file():
                files.append(f)
    scanned = 0
    for f in files:
        try:
            display = str(f.resolve().relative_to(root.resolve()))
        except ValueError:
            display = str(f)
        if f.suffix == ".swift":
            findings += lint_swift(f, display, matcher)
            scanned += 1
        elif f.suffix in {".xcstrings", ".strings"}:
            findings += lint_strings_file(f, display, matcher)
            scanned += 1
    return (findings, scanned) if count else findings


# ---------------------------------------------------------------------------------------------
# Subcommands

def cmd_lint(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    matcher = PhraseMatcher(Path(args.export).resolve() if args.export else root / "Contracts/design/marginalia.v1.json")
    if args.paths:
        targets = [Path(p).resolve() for p in args.paths]
        # A path given on the command line must be something the lint really scans. A missing
        # path, or one the default scan excludes (Spikes/, Packages/Design/, build products, test
        # directories), would otherwise report "0 finding(s)" without looking at anything.
        refused = []
        for t in targets:
            rel = t.relative_to(root) if t.is_relative_to(root) else t
            if not t.exists():
                refused.append(f"{rel}: does not exist")
            elif is_excluded(rel):
                refused.append(f"{rel}: excluded from the UI scan (Spikes/, Packages/Design/, build "
                               f"products and test directories are not product UI; to lint a tree "
                               f"elsewhere, pass it as --root)")
        if refused:
            for reason in refused:
                print(f"design lint: error: {reason}")
            return 2
    else:
        targets = ui_roots(root)
    findings, scanned = lint_paths(targets, root, matcher, apply_exclusions=True, count=True)
    shown = ", ".join(str(t.relative_to(root)) if t.is_relative_to(root) else str(t) for t in targets) or "(none yet)"
    print(f"design lint: UI targets scanned: {shown}")
    print(f"design lint: {scanned} Swift and strings file(s) checked")
    print(f"design lint: {len(matcher.permitted)} permitted and {len(matcher.forbidden)} forbidden phrases from the export")
    if args.paths and scanned == 0:
        print("design lint: error: the paths given contain no Swift or strings file to check")
        return 2
    for f in findings:
        print(f)
    print(f"design lint: {len(findings)} finding(s)")
    return 1 if findings else 0


def expected_findings(path: Path, display: str) -> set[tuple[str, int, str]]:
    expected = set()
    for number, text in enumerate(path.read_text(encoding="utf-8").split("\n"), start=1):
        for rule in re.findall(r"lint-expect:\s*([a-z-]+)", text):
            expected.add((display, number, rule))
    return expected


def cmd_self_test(args: argparse.Namespace) -> int:
    matcher = PhraseMatcher(EXPORT)
    failures = 0
    checked = 0
    violating = sorted((LINT_FIXTURES / "violating").rglob("*"))
    clean = sorted((LINT_FIXTURES / "clean").rglob("*"))
    for f in violating:
        if f.is_dir() and f.suffix != ".colorset":
            continue
        if f.is_file() and any(p.suffix == ".colorset" for p in f.parents):
            continue
        display = str(f.relative_to(ROOT))
        got = {(x.path, x.line, x.rule) for x in lint_paths([f], ROOT, matcher, apply_exclusions=False)}
        if f.suffix == ".swift":
            want = expected_findings(f, display)
        elif f.suffix == ".colorset":
            want = {(display, 1, "color-asset")}
        else:
            want = {(display, 1, rule) for rule in re.findall(r"lint-expect:\s*([a-z-]+)", f.read_text())}
            got = {(p, 1, r) for p, _, r in got}
        checked += 1
        if not want:
            print(f"self-test FAIL: {display} declares no expected findings")
            failures += 1
        if got != want:
            failures += 1
            print(f"self-test FAIL: {display}")
            for item in sorted(want - got):
                print(f"  missed   {item[1]}: {item[2]}")
            for item in sorted(got - want):
                print(f"  extra    {item[1]}: {item[2]}")
        else:
            print(f"self-test ok: {display}: {len(got)} expected finding(s)")
    for f in clean:
        if not f.is_file():
            continue
        display = str(f.relative_to(ROOT))
        got = lint_paths([f], ROOT, matcher, apply_exclusions=False)
        checked += 1
        if got:
            failures += 1
            print(f"self-test FAIL: {display} should be clean:")
            for x in got:
                print(f"  {x}")
        else:
            print(f"self-test ok: {display}: clean")
    # The default scan must exclude the design package and spikes.
    for rel in ["Packages/Design/Sources/SylviaDesign/Colors.swift", "Spikes/G06/whatever.swift"]:
        if not is_excluded(Path(rel)):
            failures += 1
            print(f"self-test FAIL: {rel} should be excluded from the UI scan")
    for rel in ["Apps/Sylvia/Sources/Library.swift", "Packages/UI/Sources/Thoughts.swift"]:
        if is_excluded(Path(rel)):
            failures += 1
            print(f"self-test FAIL: {rel} should be scanned")
    # Target discovery on a synthetic repository: Apps/ and UI packages are scanned; a package
    # without UI imports, the design package, spikes and test directories are not.
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree = {
            "Apps/Sylvia/Sources/Library.swift": 'import SwiftUI\nlet t = Text("Saved")\n',
            "Apps/Sylvia/Tests/LibraryTests.swift": 'import SwiftUI\nlet t = "Saved"\n',
            "Packages/UI/Sources/Thoughts.swift": 'import SwiftUI\nlet c = Color(white: 0.5)\n',
            "Packages/Domain/Sources/State.swift": 'let state = "Ready"\n',
            "Packages/Design/Sources/Tokens.swift": 'import SwiftUI\nlet c = Color(red: 1, green: 0, blue: 0)\n',
            "Spikes/G06/Harness.swift": 'import SwiftUI\nlet t = Text("Saved")\n',
        }
        for rel, text in tree.items():
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(text, encoding="utf-8")
        roots = sorted(str(p.relative_to(root)) for p in ui_roots(root))
        got = sorted((f.path, f.rule) for f in lint_paths(ui_roots(root), root, matcher, apply_exclusions=True))
        want = [("Apps/Sylvia/Sources/Library.swift", "status-phrase"),
                ("Packages/UI/Sources/Thoughts.swift", "color-components")]
        checked += 1
        if roots != ["Apps", "Packages/UI"] or got != want:
            failures += 1
            print(f"self-test FAIL: target discovery scanned {roots}, found {got}")
        else:
            print("self-test ok: target discovery (Apps and UI packages in; Domain, Design, Spikes and Tests out)")
        # Explicit paths: an excluded or missing path is refused (exit 2) instead of reporting
        # "0 finding(s)"; a product path with a violation exits 1.
        import contextlib
        import io
        cases = [("Spikes/G06", 2), ("Apps/Sylvia/Tests", 2), ("Packages/Design/Sources", 2),
                 ("Apps/Missing", 2), ("Apps/Sylvia/Sources", 1)]
        for rel, want_status in cases:
            namespace = argparse.Namespace(root=str(root), export=str(EXPORT), paths=[str(root / rel)])
            with contextlib.redirect_stdout(io.StringIO()):
                status = cmd_lint(namespace)
            checked += 1
            if status != want_status:
                failures += 1
                print(f"self-test FAIL: lint {rel} exited {status}, expected {want_status}")
            else:
                print(f"self-test ok: lint {rel} exits {status}")
    print(f"lint self-test: {checked} sample file(s), {failures} failure(s)")
    return 1 if failures or checked == 0 else 0


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"#[0-9A-F]{6}", value):
        raise ValueError(f"contrast pairs need opaque #RRGGBB colors, got {value}")
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))  # type: ignore[return-value]


def luminance(rgb: tuple[int, int, int]) -> float:
    def lin(c: int) -> float:
        s = c / 255
        return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def resolve(data: dict, reference: str, appearance: str) -> str:
    kind, _, rest = reference.partition(".")
    if kind == "color":
        return data["color"][rest][appearance]
    if kind == "marker":
        name, _, part = rest.partition(".")
        value = data["marker"][name][part]
        if value is None:
            raise ValueError(f"{reference} is null")
        return value[appearance]
    raise ValueError(f"unknown reference {reference}")


def cmd_contrast(args: argparse.Namespace) -> int:
    data = json.loads(Path(args.export).read_text(encoding="utf-8"))
    contrast = data["contrast"]
    minimum, minimum_large = contrast["minimum_ratio"], contrast["minimum_ratio_large_text"]
    large_points = contrast["large_text_minimum_points"]
    if minimum < 4.5 or minimum_large < 3.0 or large_points < 24:
        print(f"contrast: thresholds weakened ({minimum}, {minimum_large} from {large_points} pt)")
        return 1
    rows, failures = [], 0
    for appearance in data["appearances"]:
        for pair in contrast["pairs"]:
            fg = hex_to_rgb(resolve(data, pair["text"], appearance))
            bg = hex_to_rgb(resolve(data, pair["fill"], appearance))
            r = ratio(fg, bg)
            needed = minimum_large if pair["text_size"] == "large" else minimum
            ok = r >= needed
            failures += not ok
            rows.append((appearance, pair["text"], pair["fill"], resolve(data, pair["text"], appearance),
                         resolve(data, pair["fill"], appearance), r, needed, ok))
    lowest = min(rows, key=lambda row: row[5])
    out = ["# Contrast check over the token export (Python, independent of the Swift package)", "",
           f"Source: `Contracts/design/marginalia.v1.json` (token_version {data['token_version']}). "
           f"Command: `Scripts/lint-design.py contrast`. Environment: host (Python {sys.version.split()[0]}).", "",
           f"{len(rows)} measurements ({len(contrast['pairs'])} pairs x {len(data['appearances'])} appearances), "
           f"{failures} failing; lowest {lowest[5]:.2f} ({lowest[1]} on {lowest[2]}, {lowest[0]}).", "",
           "| Appearance | Text | Fill | Text color | Fill color | Ratio | Needs | Result |",
           "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for a, t, f, tc, fc, r, needed, ok in rows:
        out.append(f"| {a} | {t} | {f} | {tc} | {fc} | {r:.2f} | {needed:.1f} | {'pass' if ok else 'FAIL'} |")
    # Component pairs: text and glyphs as components draw them (a color from the opposite
    # appearance, a non-token fill, or a control faded over the ground by its state).
    opposite = {"light": "dark", "dark": "light", "light_increased_contrast": "dark_increased_contrast",
                "dark_increased_contrast": "light_increased_contrast"}
    minimum_glyph = contrast.get("minimum_ratio_non_text", 3.0)
    if minimum_glyph < 3.0:
        print(f"contrast: non-text threshold weakened ({minimum_glyph})")
        return 1

    def composite(top: tuple[int, int, int], bottom: tuple[int, int, int], alpha: float) -> tuple[int, int, int]:
        # Source-over in gamma-encoded sRGB, rounded half away from zero (as the Swift package does).
        return tuple(int(alpha * t + (1 - alpha) * b + 0.5) for t, b in zip(top, bottom))  # type: ignore[return-value]

    component_rows, component_failures, exempt_below = [], 0, 0
    for appearance in data["appearances"]:
        for pair in contrast.get("component_pairs", []):
            if pair["requirement"] == "exempt_disabled" and pair["state"] != "disabled":
                print(f"contrast: {pair['component']}.{pair['state']} is exempt but not a disabled state")
                return 1
            text_appearance = opposite[appearance] if pair["text_appearance"] == "opposite" else appearance
            fg = hex_to_rgb(resolve(data, pair["text"], text_appearance))
            bg = hex_to_rgb(resolve(data, pair["fill"], appearance))
            alpha = pair["opacity_over_ground"]
            if alpha < 1:
                ground = hex_to_rgb(resolve(data, "color.ground", appearance))
                fg, bg = composite(fg, ground, alpha), composite(bg, ground, alpha)
            r = ratio(fg, bg)
            needed = minimum_glyph if pair["content"] == "glyph" else minimum
            ok = r >= needed
            if not ok and pair["requirement"] == "required":
                component_failures += 1
                result = "FAIL"
            elif not ok:
                exempt_below += 1
                result = "below (disabled, exempt)"
            else:
                result = "pass (glyph; below 4.5)" if pair["content"] == "glyph" and r < minimum else "pass"
            component_rows.append((appearance, pair["component"], pair["state"], pair["content"],
                                   "#%02X%02X%02X" % fg, "#%02X%02X%02X" % bg, r, needed, result))
    failures += component_failures
    out += ["", "## Component pairs", "",
            f"`contrast.component_pairs`: {len(component_rows)} measurements, {component_failures} failing, "
            f"{exempt_below} exempt disabled-state measurements below the minimum (reported, not enforced). "
            f"Colors after compositing a faded control over the ground. Text needs {minimum:.1f}:1, "
            f"glyphs {minimum_glyph:.1f}:1.", "",
            "| Appearance | Component | State | Content | Text color | Fill color | Ratio | Needs | Result |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for a, comp, state, content, tc, fc, r, needed, result in component_rows:
        out.append(f"| {a} | {comp} | {state} | {content} | {tc} | {fc} | {r:.2f} | {needed:.1f} | {result} |")
    # For reference: pairs the plan does not permit (muted captions on tints).
    out += ["", "## Not permitted, for reference", "",
            "Section 4.4.2 allows only ink and the marker's own color on a tint. Muted text on tints, measured "
            "here so components never use it:", "",
            "| Appearance | Fill | Muted | Fill color | Ratio |", "| --- | --- | --- | --- | --- |"]
    for appearance in data["appearances"]:
        muted = resolve(data, "color.muted", appearance)
        for fill in sorted({p["fill"] for p in contrast["pairs"] if p["fill"].endswith("tint")}):
            fc = resolve(data, fill, appearance)
            out.append(f"| {appearance} | {fill} | {muted} | {fc} | {ratio(hex_to_rgb(muted), hex_to_rgb(fc)):.2f} |")
    # Grayscale: the sRGB-encoded grey of each tint's relative luminance (an approximation of a
    # luminance grayscale filter). Tints that collapse to nearly the same grey must differ by glyph,
    # label and body form (Section 4.4.8); this table is input to the T53 snapshot method.
    def grey(hex_value: str) -> int:
        y = luminance(hex_to_rgb(hex_value))
        encoded = 12.92 * y if y <= 0.0031308 else 1.055 * y ** (1 / 2.4) - 0.055
        return round(encoded * 255)
    out += ["", "## Tints in grayscale, for reference", "",
            "Grey level (0-255) of each marker tint and text color after a luminance grayscale conversion.", "",
            "| Appearance | Marker | Tint | Tint grey | Text | Text grey |", "| --- | --- | --- | --- | --- | --- |"]
    for appearance in data["appearances"]:
        for name, marker in data["marker"].items():
            tint = marker["tint"][appearance] if marker["tint"] else None
            text_hex = marker["text"][appearance]
            out.append(f"| {appearance} | {name} | {tint or 'none'} | {grey(tint) if tint else '-'} | "
                       f"{text_hex} | {grey(text_hex)} |")
    text = "\n".join(out) + "\n"
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
    print(f"contrast: {len(rows)} measurements, {failures - component_failures} failing, lowest {lowest[5]:.2f}; "
          f"{len(component_rows)} component measurements, {component_failures} failing, "
          f"{exempt_below} exempt (disabled) below the minimum")
    for row in rows:
        if not row[7]:
            print(f"  FAIL {row[0]} {row[1]} on {row[2]}: {row[5]:.2f} < {row[6]}")
    for row in component_rows:
        if row[8] == "FAIL":
            print(f"  FAIL {row[0]} {row[1]}.{row[2]}: {row[6]:.2f} < {row[7]}")
    return 1 if failures else 0


def diff_paths(a, b, path=()) -> list[tuple]:
    if isinstance(a, dict) and isinstance(b, dict):
        out = []
        for key in sorted(set(a) | set(b)):
            if key not in a or key not in b:
                out.append(path + (key,))
            else:
                out += diff_paths(a[key], b[key], path + (key,))
        return out
    return [] if a == b and type(a) is type(b) else [path]


def cmd_fixtures(args: argparse.Namespace) -> int:
    from jsonschema import Draft202012Validator, FormatChecker

    schema = json.loads((ROOT / "Contracts/schemas/design-tokens.v1.schema.json").read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    base = json.loads(EXPORT.read_text(encoding="utf-8"))
    fixture_dir = ROOT / "Contracts/fixtures/design-tokens.v1"
    failures = 0
    for f in sorted((fixture_dir / "invalid").glob("*.json")):
        instance = json.loads(f.read_text(encoding="utf-8"))
        diffs = diff_paths(base, instance)
        errors = list(validator.iter_errors(instance))
        if len(diffs) != 1:
            failures += 1
            print(f"FAIL {f.name}: differs from the export at {len(diffs)} locations: {diffs[:5]}")
            continue
        changed = diffs[0]
        unrelated = [e for e in errors
                     if not (tuple(e.absolute_path) == changed[:len(e.absolute_path)]
                             or changed == tuple(e.absolute_path)[:len(changed)])]
        if not errors or unrelated:
            failures += 1
            print(f"FAIL {f.name}: {len(errors)} errors, {len(unrelated)} unrelated to {'/'.join(map(str, changed))}")
            for e in unrelated[:5]:
                print(f"  {'/'.join(map(str, e.absolute_path))}: {e.message[:120]}")
            continue
        print(f"ok   {f.name}: one change at {'/'.join(map(str, changed))}; "
              f"{len(errors)} error(s) all there: {errors[0].message[:90]}")
    for f in sorted((fixture_dir / "valid").glob("*.json")):
        errors = list(validator.iter_errors(json.loads(f.read_text(encoding="utf-8"))))
        if errors:
            failures += 1
            print(f"FAIL {f.name}: expected valid: {errors[0].message[:120]}")
        else:
            print(f"ok   {f.name}: valid")
    print(f"design-token fixtures: {failures} failure(s)")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("lint")
    p.add_argument("--root", default=str(ROOT))
    p.add_argument("--export", default=None)
    p.add_argument("paths", nargs="*")
    p.set_defaults(func=cmd_lint)
    p = sub.add_parser("self-test")
    p.set_defaults(func=cmd_self_test)
    p = sub.add_parser("contrast")
    p.add_argument("--export", default=str(EXPORT))
    p.add_argument("--out", default=None)
    p.set_defaults(func=cmd_contrast)
    p = sub.add_parser("fixtures")
    p.set_defaults(func=cmd_fixtures)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
