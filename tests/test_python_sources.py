"""Parse Python without importing scientific code or writing bytecode."""
import ast
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path.cwd()
paths = [p for p in root.rglob("*.py") if not set(p.relative_to(root).parts) & {".git", "work", "__pycache__"}]
for path in paths:
    ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
print(f"PASS Python AST: {len(paths)} files")
