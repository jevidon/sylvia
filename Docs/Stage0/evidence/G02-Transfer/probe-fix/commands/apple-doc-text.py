"""G0.2 probe fix: prints the prose of an Apple documentation JSON page (DocC render JSON), one paragraph per line.

Reference nodes are written as their title (or identifier's last component), code voice as its text.
Usage: python3 -I doc-text.py FILE.json
"""
import json
import sys


def inline(nodes, refs):
    out = []
    for n in nodes or []:
        t = n.get("type")
        if t == "text":
            out.append(n.get("text", ""))
        elif t == "codeVoice":
            out.append(n.get("code", ""))
        elif t == "reference":
            ident = n.get("identifier", "")
            ref = refs.get(ident, {})
            out.append(ref.get("title") or ident.rsplit("/", 1)[-1])
        elif t in ("emphasis", "strong", "newTerm", "inlineHead", "strikethrough", "subscript", "superscript"):
            out.append(inline(n.get("inlineContent"), refs))
        elif t == "link":
            out.append(n.get("title", n.get("destination", "")))
        elif t == "image":
            out.append("[image]")
        else:
            out.append(inline(n.get("inlineContent"), refs))
    return "".join(out)


def blocks(nodes, refs, depth=0):
    for n in nodes or []:
        t = n.get("type")
        if t == "heading":
            print("#" * n.get("level", 2), n.get("text", ""))
        elif t == "paragraph":
            print("  " * depth + inline(n.get("inlineContent"), refs))
        elif t in ("unorderedList", "orderedList"):
            for item in n.get("items", []):
                print("  " * depth + "-", end=" ")
                blocks(item.get("content"), refs, depth + 1)
        elif t == "aside":
            print("  " * depth + f"[{n.get('style', 'note')}]", end=" ")
            blocks(n.get("content"), refs, depth + 1)
        elif t == "codeListing":
            print("  " * depth + "```")
            for line in n.get("code", []):
                print("  " * depth + line)
            print("  " * depth + "```")
        elif t == "table":
            for row in n.get("rows", []):
                cells = []
                for cell in row:
                    import io, contextlib
                    buf = io.StringIO()
                    with contextlib.redirect_stdout(buf):
                        blocks(cell, refs, 0)
                    cells.append(buf.getvalue().strip().replace("\n", " "))
                print("  " * depth + "| " + " | ".join(cells) + " |")
        else:
            blocks(n.get("content"), refs, depth)


doc = json.load(open(sys.argv[1], encoding="utf-8"))
refs = doc.get("references", {})
meta = doc.get("metadata", {})
print("title:", meta.get("title"))
print("platforms:", ", ".join(f"{p.get('name')} {p.get('introducedAt', '')}" + (" deprecated" if p.get("deprecated") else "") for p in meta.get("platforms", [])))
abstract = doc.get("abstract")
if abstract:
    print("abstract:", inline(abstract, refs))
for section in doc.get("primaryContentSections", []):
    blocks(section.get("content"), refs)
