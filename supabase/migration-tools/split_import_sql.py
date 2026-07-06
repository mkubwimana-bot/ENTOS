#!/usr/bin/env python3
"""Split output/import.sql into Supabase SQL Editor–sized chunks."""

from __future__ import annotations

import re
from pathlib import Path

MAX_LINES_PER_CHUNK = 150


def main() -> None:
    src = Path(__file__).parent / "output" / "import.sql"
    out_dir = Path(__file__).parent / "output" / "chunks"
    if out_dir.exists():
        for old in out_dir.glob("*.sql"):
            old.unlink()
    out_dir.mkdir(parents=True, exist_ok=True)

    text = src.read_text(encoding="utf-8")
    lines = text.splitlines()

    # Strip outer transaction — each chunk gets its own begin/commit.
    body = [ln for ln in lines if ln.strip() not in ("begin;", "commit;")]

    sections: list[tuple[str, list[str]]] = []
    current_name = "preamble"
    current: list[str] = []
    header_re = re.compile(r"^-- =+$")

    i = 0
    while i < len(body):
        line = body[i]
        if header_re.match(line) and i + 2 < len(body) and header_re.match(body[i + 2]):
            title = body[i + 1].strip("- ").strip()
            if current:
                sections.append((current_name, current))
            current_name = title
            current = []
            i += 3
            continue
        current.append(line)
        i += 1
    if current:
        sections.append((current_name, current))

    chunks: list[tuple[str, list[str]]] = []
    for name, sec_lines in sections:
        if name == "Active movements (chronological replay)" and len(sec_lines) > MAX_LINES_PER_CHUNK:
            part = 1
            for start in range(0, len(sec_lines), MAX_LINES_PER_CHUNK):
                piece = sec_lines[start : start + MAX_LINES_PER_CHUNK]
                chunks.append((f"04_active_movements_part{part}", piece))
                part += 1
        else:
            slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_") or "section"
            chunks.append((slug, sec_lines))

    manifest: list[str] = []
    for idx, (slug, chunk_lines) in enumerate(chunks, start=1):
        fname = f"{idx:02d}_{slug}.sql"
        wrapped = ["begin;", *chunk_lines, "commit;", ""]
        (out_dir / fname).write_text("\n".join(wrapped), encoding="utf-8")
        manifest.append(f"{idx}. {fname}  ({len(chunk_lines)} statements/lines)")

    (out_dir / "README.txt").write_text(
        "Run these files IN ORDER in Supabase SQL Editor (one at a time).\n\n"
        + "\n".join(manifest)
        + "\n\nIf a chunk still fails as 'too large', use psql or:\n"
        "  python migrate_entos.py --config migration_config.json --execute\n"
        "with DATABASE_URL set to your Supabase connection string.\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(chunks)} chunks to {out_dir}")
    for line in manifest:
        print(f"  {line}")


if __name__ == "__main__":
    main()
