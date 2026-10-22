"""Public-release file checks. No external services or participant input access."""
import argparse
import hashlib
import pathlib
import re
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--root", default=".")
parser.add_argument("--verify-hashes", action="store_true")
args = parser.parse_args()
root = pathlib.Path(args.root).resolve()
skip = {".git", "work", "__pycache__"}
forbidden_dirs = {"PRIVATE_DO_NOT_UPLOAD", "INTERNAL_RESTRICTED", "CONTROLLED_REPRODUCTION_DO_NOT_UPLOAD"}
forbidden_suffixes = {".xlsx", ".xls", ".bed", ".bam", ".cram", ".fastq", ".fq", ".rds", ".pptx", ".docx", ".pem", ".key", ".pyc"}
patterns = {
    "workstation home path": re.compile(r"/home/(?!runner(?:/|\b)|rstudio(?:/|\b))[A-Za-z_][A-Za-z0-9_.-]*/"),
    "workstation project path": re.compile(r"/data/" + r"Codex|/mnt/" + r"r[0-9]+(?:hdd|ssd)"),
    "literal clinical sample identifier": re.compile(r"(['\"])(?:AD|AC|SC)[0-9]{1,3}\1"),
    "standalone clinical sample identifier": re.compile(r"^(?:AD|AC|SC)[0-9]{1,3}$", re.M),
    "GitHub credential": re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})"),
    "private key": re.compile(r"-{5}BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-{5}"),
}
failures = []
files = []
for path in sorted(root.rglob("*")):
    rel = path.relative_to(root)
    if set(rel.parts) & skip:
        continue
    if path.is_symlink():
        failures.append(f"Symlink: {rel}")
        continue
    if set(rel.parts) & forbidden_dirs:
        failures.append(f"Restricted path: {rel}")
        continue
    if not path.is_file():
        continue
    files.append(path)
    if path.suffix.lower() in forbidden_suffixes or path.name.endswith((".bed.gz", ".fastq.gz", ".fq.gz")):
        failures.append(f"Non-public data/binary type: {rel}")
    if path.stat().st_size > 10_000_000:
        failures.append(f"Unexpectedly large file: {rel}")
    try:
        text = path.read_text(encoding="utf-8-sig")
    except UnicodeError:
        failures.append(f"Unexpected binary/non-UTF-8 content: {rel}")
        continue
    for label, regex in patterns.items():
        if regex.search(text):
            failures.append(f"{label}: {rel}")
if args.verify_hashes:
    checksum_file = root / "SHA256SUMS.txt"
    if not checksum_file.exists():
        failures.append("Missing SHA256SUMS.txt")
    else:
        listed = set()
        for line in checksum_file.read_text().splitlines():
            digest, rel = line.split("  ", 1)
            path = root / rel
            listed.add(rel)
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                failures.append(f"Hash mismatch/missing: {rel}")
        actual = {str(p.relative_to(root)) for p in files if p.name != "SHA256SUMS.txt"}
        if listed != actual:
            failures.append("Checksum inventory differs from public file inventory")
if failures:
    print("RELEASE CHECK FAILED\n" + "\n".join(failures), file=sys.stderr)
    sys.exit(1)
print(f"PASS public release checks: {len(files)} UTF-8 files; no matched restricted-file/path/credential patterns")
print("Automated checks do not establish consent, legal clearance or a complete absence of sensitive information.")
