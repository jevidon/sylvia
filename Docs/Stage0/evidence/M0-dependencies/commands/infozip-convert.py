"""ADR-0014 evidence: the Info-ZIP license page (https://infozip.sourceforge.net/license.html) as plain text.

  python3 -I infozip-convert.py <license.html> <page.txt> <license.txt>

The page is read as data (Latin-1, as served): tags removed, items of each numbered list numbered, entities decoded,
runs of blank lines collapsed. <license.txt> is the license itself, cut from "This is version" to the end of its last
condition ("own source and binary releases."). No network.
"""
import html, re, sys
t = open(sys.argv[1], encoding="latin-1").read().replace("\r\n", "\n")
t = re.sub(r"(?is)<(script|style|head)[^>]*>.*?</\1>", "", t)


def number(block):
    n = [0]

    def item(_):
        n[0] += 1
        return f"\n{n[0]}. "
    return re.sub(r"(?i)<li[^>]*>", item, block.group(0))


t = re.sub(r"(?is)<ol[^>]*>.*?</ol>", number, t)
t = re.sub(r"(?i)<li[^>]*>", "\n- ", t)
t = re.sub(r"(?i)<br\s*/?>|</p>|</li>|</h[1-6]>|</dd>|</dt>|<p[^>]*>", "\n", t)
t = html.unescape(re.sub(r"(?s)<[^>]+>", "", t))
lines = [" ".join(l.split()) for l in t.splitlines()]
out, blank = [], False
for l in lines:
    if l or not blank:
        out.append(l)
    blank = not l
page = "\n".join(out).strip() + "\n"
open(sys.argv[2], "w", encoding="utf-8").write(page)
start = page.index("This is version ")
end = page.index("own source and binary releases.") + len("own source and binary releases.")
open(sys.argv[3], "w", encoding="utf-8").write(page[start:end] + "\n")
