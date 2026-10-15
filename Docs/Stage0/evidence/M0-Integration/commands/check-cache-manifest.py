"""Checks every file listed in a G0.4 cache manifest.tsv against its size and SHA-256; prints totals."""
import hashlib, pathlib, sys
d = pathlib.Path(sys.argv[1])
n = total = bad = 0
for line in (d / "manifest.tsv").read_text().splitlines():
    if not line or line.startswith("#"):
        continue
    parts = line.split("\t")
    name = next(p for p in parts if (d / p).is_file()) if any((d / p).is_file() for p in parts) else parts[0]
    f = d / name
    sha = next((p for p in parts if len(p) == 64), None)
    size = next((int(p) for p in parts if p.isdigit()), None)
    h = hashlib.sha256()
    with open(f, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    ok = h.hexdigest() == sha and f.stat().st_size == size
    n += 1; total += f.stat().st_size; bad += (not ok)
    if not ok:
        print("MISMATCH", name)
print(f"{d}: {n} files, {total} bytes, {bad} mismatches")
