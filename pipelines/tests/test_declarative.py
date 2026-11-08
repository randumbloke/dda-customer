import json

from dda_pipeline.validate import validate_document, validate_repository


def test_declarative_files_match_schemas(repo):
    assert validate_repository(repo) == []


def test_invalid_product_is_rejected(repo):
    schema = json.loads((repo / "schemas" / "product.schema.json").read_text())
    assert validate_document({"id": "x"}, schema)


def test_invalid_dq_threshold_is_rejected(repo):
    schema = json.loads((repo / "schemas" / "dq_spec.schema.json").read_text())
    spec = {"table": "customer_curated.contacts", "trigger": "on_demand",
            "rules": [{"name": "r", "dimension": "VALIDITY", "template": "non_null_expectation", "threshold": 95}]}
    assert validate_document(spec, schema)
