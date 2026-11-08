"""Rendering of the SQL step templates (string.Template, ${name} placeholders)."""

from __future__ import annotations

import re
from pathlib import Path
from string import Template

_LEFTOVER = re.compile(r"\$\{[^}]*\}")


def render(text: str, values: dict[str, str]) -> str:
    """Render a template. A placeholder without a value raises KeyError."""
    rendered = Template(text).substitute(values)
    leftover = _LEFTOVER.search(rendered)
    if leftover:
        raise ValueError(f"unrendered placeholder {leftover.group(0)}")
    return rendered


def render_file(home: Path, relative: str, values: dict[str, str]) -> str:
    return render((home / relative).read_text(encoding="utf-8"), values)


_TABLE_REF = re.compile(r"`([a-z][a-z0-9-]*)\.([a-z][a-z0-9_]*)\.([a-z][a-z0-9_]*)`")


def table_refs(sql: str) -> list[str]:
    """Fully qualified table references (project.dataset.table) in rendered SQL."""
    return [".".join(m.groups()) for m in _TABLE_REF.finditer(sql)]
