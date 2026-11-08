"""Validate the declarative files against the vendored JSON Schemas (contracts README §4)."""

from __future__ import annotations

import json
from pathlib import Path

import yaml

FILES = (
    ("datasets.yaml", "datasets.schema.json"),
    ("products/*.yaml", "product.schema.json"),
    ("dq/*/*.yaml", "dq_spec.schema.json"),
    ("pipelines/lineage/manifest.json", "lineage_manifest.schema.json"),
)


def _load(path: Path):
    text = path.read_text(encoding="utf-8")
    return json.loads(text) if path.suffix == ".json" else yaml.safe_load(text)


def validate_document(doc, schema: dict) -> list[str]:
    from jsonschema import Draft202012Validator

    validator = Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)
    return [
        f"{'/'.join(str(p) for p in err.absolute_path) or '<root>'}: {err.message}"
        for err in sorted(validator.iter_errors(doc), key=lambda e: list(e.absolute_path))
    ]


def validate_repository(root: str | Path) -> list[str]:
    root = Path(root)
    errors: list[str] = []
    for pattern, schema_name in FILES:
        schema = json.loads((root / "schemas" / schema_name).read_text(encoding="utf-8"))
        matches = sorted(root.glob(pattern))
        if not matches and "*" not in pattern:
            errors.append(f"{pattern}: missing")
        for path in matches:
            for e in validate_document(_load(path), schema):
                errors.append(f"{path.relative_to(root)}: {e}")
    # Cross-file rules the schemas cannot express.
    datasets = _load(root / "datasets.yaml")["datasets"]
    for path in sorted(root.glob("dq/*/*.yaml")):
        spec = _load(path)
        expected = f"{path.parent.name}.{path.stem}"
        if spec.get("table") != expected:
            errors.append(f"{path.relative_to(root)}: table must be {expected}")
        if spec.get("table", ".").split(".")[0] not in datasets:
            errors.append(f"{path.relative_to(root)}: dataset not declared in datasets.yaml")
    sensitive = {name for name, d in datasets.items() if d["sensitivity"] == "sensitive"}
    specs = {_load(p).get("table") for p in root.glob("dq/*/*.yaml")}
    for path in sorted(root.glob("products/*.yaml")):
        product = _load(path)
        if product.get("id") != path.stem:
            errors.append(f"{path.relative_to(root)}: id must be {path.stem}")
        for asset, a in product.get("assets", {}).items():
            # G3: every sensitive asset table has a scan specification (design §3.9).
            if a["table"].split(".")[0] in sensitive and a["table"] not in specs:
                errors.append(f"{path.relative_to(root)}: sensitive asset {asset} has no dq/ specification")
    return errors
