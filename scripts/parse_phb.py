"""Parse the PHB 2024 (PT-BR) HTML into priv/spells.json.

Usage:
    python scripts/parse_phb.py

Reads:  test/D&D 5.5 - Livro do Jogador (2024).html
Writes: priv/spells.json
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
from pathlib import Path

from bs4 import BeautifulSoup, NavigableString, Tag

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "test" / "D&D 5.5 - Livro do Jogador (2024).html"
OUT = ROOT / "priv" / "spells.json"

META_LABELS = {
    "Tempo de Conjuração": "casting_time",
    "Alcance": "range",
    "Componentes": "components",
    "Duração": "duration",
}

HEADER_LEVELED = re.compile(
    r"^(\d+)[ºo°]?\s*Círculo\s*,\s*(.+?)\s*\(([^)]+)\)\s*$"
)
HEADER_CANTRIP = re.compile(
    r"^Truque\s+de\s+(.+?)\s*\(([^)]+)\)\s*$"
)


def slugify(name: str) -> str:
    nfkd = unicodedata.normalize("NFKD", name)
    ascii_ = nfkd.encode("ascii", "ignore").decode("ascii")
    ascii_ = ascii_.lower()
    ascii_ = re.sub(r"[^a-z0-9]+", "-", ascii_).strip("-")
    return ascii_


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def parse_header(text: str) -> tuple[int, str, list[str]] | None:
    """Returns (level, school, classes) or None if the line isn't a spell header."""
    m = HEADER_LEVELED.match(text)
    if m:
        level = int(m.group(1))
        school = m.group(2).strip()
        classes = [c.strip() for c in m.group(3).split(",")]
        return level, school, classes
    m = HEADER_CANTRIP.match(text)
    if m:
        school = m.group(1).strip()
        classes = [c.strip() for c in m.group(2).split(",")]
        return 0, school, classes
    return None


def is_h2_spell(tag: Tag) -> bool:
    if tag.name != "h2":
        return False
    span = tag.find("span")
    return span is not None and "c29" in (span.get("class") or [])


def meta_from_p(p: Tag) -> tuple[str, str] | None:
    """If <p> is a 'Label: value' meta line, return (label, value)."""
    spans = p.find_all("span")
    if len(spans) < 2:
        return None
    label = clean(spans[0].get_text())
    label = label.rstrip(":")
    if label not in META_LABELS:
        return None
    value = clean(" ".join(s.get_text() for s in spans[1:]))
    return label, value


def block_text(tag: Tag) -> str:
    """Flatten a <p> or <li> to plain text, joining inline spans with spaces."""
    parts: list[str] = []
    for child in tag.descendants:
        if isinstance(child, NavigableString):
            parts.append(str(child))
    return clean("".join(parts))


def parse_spell(name: str, blocks: list[Tag]) -> dict | None:
    """Given the spell name and the run of tags after its <h2>, build the record."""
    if not blocks:
        return None

    # Illustrated spells have an art caption <p> before the real level/school header.
    # Scan forward until we find a block that parses as a header.
    header_idx = None
    parsed = None
    for i, block in enumerate(blocks):
        if block.name != "p":
            continue
        parsed = parse_header(clean(block.get_text()))
        if parsed is not None:
            header_idx = i
            break
    if parsed is None or header_idx is None:
        print(f"  ! skipping {name!r}: no header found in {len(blocks)} blocks", file=sys.stderr)
        return None
    level, school, classes = parsed

    meta: dict[str, str] = {}
    desc_parts: list[str] = []

    for block in blocks[header_idx + 1:]:
        if block.name == "p":
            kv = meta_from_p(block)
            if kv is not None:
                label, value = kv
                meta[META_LABELS[label]] = value
                continue
            text = block_text(block)
            if text:
                desc_parts.append(text)
        elif block.name in ("ul", "ol"):
            for li in block.find_all("li", recursive=False):
                text = block_text(li)
                if text:
                    desc_parts.append(f"• {text}")

    casting_time = meta.get("casting_time", "")
    duration = meta.get("duration", "")

    return {
        "name": name,
        "slug": slugify(name),
        "level": level,
        "school": school,
        "classes": classes,
        "casting_time": casting_time,
        "range": meta.get("range", ""),
        "components": meta.get("components", ""),
        "duration": duration,
        "ritual": "Ritual" in casting_time,
        "concentration": "Concentração" in duration,
        "description": "\n\n".join(desc_parts),
    }


def main() -> int:
    html = SRC.read_text(encoding="utf-8")
    soup = BeautifulSoup(html, "html.parser")

    h2s = [t for t in soup.find_all("h2") if is_h2_spell(t)]
    print(f"Found {len(h2s)} <h2> spell headers", file=sys.stderr)

    spells: list[dict] = []
    skipped = 0

    for h2 in h2s:
        name_span = h2.find("span", class_="c29")
        name = clean(name_span.get_text()) if name_span else clean(h2.get_text())

        # Collect every sibling until the next spell header.
        blocks: list[Tag] = []
        sib = h2.next_sibling
        while sib is not None:
            if isinstance(sib, Tag):
                if is_h2_spell(sib):
                    break
                if sib.name in ("p", "ul", "ol"):
                    blocks.append(sib)
            sib = sib.next_sibling

        record = parse_spell(name, blocks)
        if record is None:
            skipped += 1
            continue
        spells.append(record)

    # Sort by name for determinism.
    spells.sort(key=lambda s: s["name"])

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps({"spells": spells}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"Wrote {len(spells)} spells to {OUT.relative_to(ROOT)}", file=sys.stderr)
    if skipped:
        print(f"Skipped {skipped} entries", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
