import csv
import hashlib
import io

import pytest

from dda_pipeline import generator
from dda_pipeline.generator import GeneratorConfig, generate


def _digest(files):
    return {k: hashlib.sha256(v.encode()).hexdigest() for k, v in files.items()}


@pytest.mark.parametrize("business", sorted(generator.GENERATORS))
def test_same_seed_same_bytes(business):
    a = generate(GeneratorConfig(business=business))
    b = generate(GeneratorConfig(business=business))
    assert _digest(a) == _digest(b)


@pytest.mark.parametrize("business", sorted(generator.GENERATORS))
def test_different_seed_differs(business):
    a = generate(GeneratorConfig(business=business, seed=1))
    b = generate(GeneratorConfig(business=business, seed=2))
    assert _digest(a) != _digest(b)


def _rows(text):
    return list(csv.DictReader(io.StringIO(text)))


def test_customer_values_are_reserved():
    files = generate(GeneratorConfig(business="customer", customers=200))
    rows = _rows(files["contacts"])
    assert len(rows) == 200
    for r in rows:
        assert r["email"].rsplit("@", 1)[1] in generator.RESERVED_EMAIL_DOMAINS
        assert r["phone"] in generator.RESERVED_MOBILES or r["phone"][:7] in generator.RESERVED_LANDLINE_PREFIXES
        assert r["customer_id"]
    assert len({r["customer_id"] for r in rows}) == 200
    postcodes = {r["postcode"] for r in _rows(files["postcodes"])}
    assert {r["postcode"] for r in rows} <= postcodes


def test_accounts_reference_generated_customers():
    customers = {r["customer_id"] for r in _rows(generate(GeneratorConfig(business="customer"))["contacts"])}
    files = generate(GeneratorConfig(business="accounts"))
    accounts = _rows(files["accounts"])
    assert {a["customer_id"] for a in accounts} <= customers
    account_ids = {a["account_id"] for a in accounts}
    assert {t["account_id"] for t in _rows(files["transactions"])} <= account_ids


def test_inject_failures_breaks_critical_rules():
    rows = _rows(generate(GeneratorConfig(business="customer", inject_failures=True))["contacts"])
    assert any(r["customer_id"] == "" for r in rows)
    assert any("@" not in r["email"] for r in rows)


def test_landing_paths_match_load_uris(home):
    # Each generated entity lands at <entity>/<entity>.csv, under the gs://.../<entity>/*.csv
    # URI that the load step reads.
    for business in generator.GENERATORS:
        for entity in generate(GeneratorConfig(business=business, customers=5, accounts=5, transactions=5)):
            assert generator.landing_object(entity) == f"{entity}/{entity}.csv"


def test_write_local(tmp_path):
    written = generator.write_local({"contacts": "a\n1\n"}, str(tmp_path))
    assert (tmp_path / "contacts" / "contacts.csv").read_text() == "a\n1\n"
    assert written == [str(tmp_path / "contacts" / "contacts.csv")]


def test_unknown_business():
    with pytest.raises(ValueError):
        generate(GeneratorConfig(business="nope"))


def test_output_does_not_depend_on_today(monkeypatch):
    import datetime as dt

    before = generate(GeneratorConfig(business="customer", customers=50))

    class FrozenDate(dt.date):
        @classmethod
        def today(cls):
            return cls(2031, 1, 1)

    monkeypatch.setattr(dt, "date", FrozenDate)
    after = generate(GeneratorConfig(business="customer", customers=50))
    assert _digest(before) == _digest(after)
