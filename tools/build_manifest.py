"""Regenerate public release manifests after intentional, reviewed source edits."""
import csv
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path.cwd()
skip = {".git", "work", "__pycache__"}
paths = [p for p in root.rglob("*") if p.is_file() and not set(p.relative_to(root).parts) & skip]
paths = sorted(paths, key=lambda p: str(p.relative_to(root)))
excluded = {"FILE_MANIFEST.tsv", "SHA256SUMS.txt"}
with (root / "FILE_MANIFEST.tsv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
    writer.writerow(["file", "bytes", "sha256"])
    for path in paths:
        if path.name in excluded:
            continue
        writer.writerow([str(path.relative_to(root)), path.stat().st_size, hashlib.sha256(path.read_bytes()).hexdigest()])
paths = sorted([p for p in root.rglob("*") if p.is_file() and not set(p.relative_to(root).parts) & skip], key=lambda p: str(p.relative_to(root)))
with (root / "SHA256SUMS.txt").open("w", encoding="utf-8", newline="") as handle:
    for path in paths:
        if path.name == "SHA256SUMS.txt":
            continue
        handle.write(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(root)}\n")
print("Updated FILE_MANIFEST.tsv (excluding manifests) and SHA256SUMS.txt (excluding itself).")
