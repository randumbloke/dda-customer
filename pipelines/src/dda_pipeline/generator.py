"""Deterministic synthetic-data generator for the reference domain pipelines (P6-39).

Every value is fake and reproducible: Faker and the standard random module are seeded with a
fixed seed, e-mail addresses use only the reserved example domains (RFC 2606), and telephone
numbers use only numbers that the Australian Communications and Media Authority reserves for
fictitious use. Discovery therefore still finds personal-data infoTypes without real records
(change mvp-phase-1-build, "Synthetic data could look like real personal data").

The same module serves every domain. Customer and Accounts share the customer ID scheme, so
accounts reference customers that the customer generator produced.
"""

from __future__ import annotations

import csv
import io
import random
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from faker import Faker

DEFAULT_SEED = 20261109
DEFAULT_CUSTOMERS = 500
DEFAULT_ACCOUNTS = 800
DEFAULT_TRANSACTIONS = 4000

# Reserved example domains (RFC 2606).
RESERVED_EMAIL_DOMAINS = ("example.com", "example.net", "example.org")

# ACMA numbers for fictitious use: mobiles 0491 570 006, 156-159, 110, 313, 737 and the
# 0491 57x xxx list, and landlines (02) 5550 xxxx and (03) 7010 xxxx.
RESERVED_MOBILES = (
    "0491570006", "0491570156", "0491570157", "0491570158", "0491570159",
    "0491570110", "0491570313", "0491570737", "0491571266", "0491571491",
    "0491571804", "0491572549", "0491572665", "0491572983", "0491573770",
    "0491573087", "0491574118", "0491574632", "0491575254", "0491575789",
    "0491576398", "0491576801", "0491577426", "0491577644", "0491578957",
    "0491578148", "0491578888", "0491579212", "0491579760", "0491579455",
)
RESERVED_LANDLINE_PREFIXES = ("0255550", "0370100")

SEGMENTS = (
    ("RET", "Retail"),
    ("PRE", "Premier"),
    ("SMB", "Small business"),
    ("STU", "Student"),
)

# Postcode reference data: postcode, region, state.
POSTCODES = (
    ("2000", "Sydney CBD", "NSW"),
    ("2150", "Parramatta", "NSW"),
    ("2600", "Canberra", "ACT"),
    ("3000", "Melbourne CBD", "VIC"),
    ("3220", "Geelong", "VIC"),
    ("4000", "Brisbane CBD", "QLD"),
    ("4217", "Gold Coast", "QLD"),
    ("5000", "Adelaide CBD", "SA"),
    ("6000", "Perth CBD", "WA"),
    ("7000", "Hobart", "TAS"),
    ("0800", "Darwin", "NT"),
)

ACCOUNT_PRODUCTS = ("TRANSACTION", "SAVINGS", "CREDIT_CARD", "HOME_LOAN")

# Fixed reference time, so output does not depend on the clock.
REFERENCE_TIME = datetime(2026, 11, 1, 0, 0, tzinfo=timezone.utc)


@dataclass(frozen=True)
class GeneratorConfig:
    business: str
    seed: int = DEFAULT_SEED
    customers: int = DEFAULT_CUSTOMERS
    accounts: int = DEFAULT_ACCOUNTS
    transactions: int = DEFAULT_TRANSACTIONS
    # Inject rule failures (null IDs, invalid e-mails) for AT-15 and AT-17.
    inject_failures: bool = False


def customer_id(n: int) -> str:
    return f"C{n:06d}"


def account_id(n: int) -> str:
    return f"A{n:07d}"


def _rng(seed: int, stream: str) -> random.Random:
    # One independent stream per entity, so adding an entity does not shift the others.
    return random.Random(f"{seed}:{stream}")


def _faker(seed: int) -> Faker:
    fake = Faker("en_AU")
    fake.seed_instance(seed)
    return fake


def _to_csv(header: list[str], rows: list[list[object]]) -> str:
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(header)
    for row in rows:
        writer.writerow(["" if v is None else v for v in row])
    return buf.getvalue()


def _phone(rng: random.Random) -> str:
    if rng.random() < 0.7:
        return rng.choice(RESERVED_MOBILES)
    return rng.choice(RESERVED_LANDLINE_PREFIXES) + f"{rng.randrange(0, 1000):03d}"


def _email_local(text: str) -> str:
    return "".join(ch for ch in text.lower() if ch.isalnum() or ch == ".").strip(".") or "user"


def generate_customer(cfg: GeneratorConfig) -> dict[str, str]:
    fake = _faker(cfg.seed)
    rng = _rng(cfg.seed, "contacts")
    rows: list[list[object]] = []
    for n in range(1, cfg.customers + 1):
        given = fake.first_name()
        family = fake.last_name()
        postcode, _region, state = rng.choice(POSTCODES)
        email = f"{_email_local(given)}.{_email_local(family)}{n}@{rng.choice(RESERVED_EMAIL_DOMAINS)}"
        # Not fake.date_of_birth(): it is relative to today, so output would change by date.
        dob = (REFERENCE_TIME - timedelta(days=rng.randrange(18 * 366, 90 * 365))).date()
        created = (REFERENCE_TIME - timedelta(days=rng.randrange(1, 3650))).date()
        cid: str | None = customer_id(n)
        if cfg.inject_failures and n % 20 == 0:
            cid = None  # fails customer-id-not-null (critical)
        if cfg.inject_failures and n % 7 == 0:
            email = f"{_email_local(given)} at example dot com"  # fails email-valid
        rows.append([
            cid, given, family, email, _phone(rng), postcode, state, dob.isoformat(),
            rng.choice(SEGMENTS)[0], rng.random() < 0.4, created.isoformat(),
        ])
    contacts = _to_csv(
        ["customer_id", "given_name", "family_name", "email", "phone", "postcode", "state",
         "date_of_birth", "segment_code", "marketing_opt_in", "created_date"],
        rows,
    )
    segments = _to_csv(["segment_code", "segment_name"], [list(s) for s in SEGMENTS])
    postcodes = _to_csv(["postcode", "region", "state"], [list(p) for p in POSTCODES])
    return {"contacts": contacts, "segments": segments, "postcodes": postcodes}


def generate_accounts(cfg: GeneratorConfig) -> dict[str, str]:
    rng = _rng(cfg.seed, "accounts")
    accounts: list[list[object]] = []
    for n in range(1, cfg.accounts + 1):
        opened = (REFERENCE_TIME - timedelta(days=rng.randrange(1, 5000))).date()
        status = "CLOSED" if rng.random() < 0.08 else "OPEN"
        accounts.append([
            account_id(n), customer_id(rng.randrange(1, cfg.customers + 1)),
            rng.choice(ACCOUNT_PRODUCTS), opened.isoformat(), status, "AUD",
        ])
    trng = _rng(cfg.seed, "transactions")
    txns: list[list[object]] = []
    for n in range(1, cfg.transactions + 1):
        ts = REFERENCE_TIME - timedelta(minutes=trng.randrange(1, 60 * 24 * 90))
        txn_type = "CREDIT" if trng.random() < 0.35 else "DEBIT"
        amount = round(trng.uniform(1, 2500), 2)
        acct: str | None = account_id(trng.randrange(1, cfg.accounts + 1))
        if cfg.inject_failures and n % 25 == 0:
            acct = None
        txns.append([f"T{n:09d}", acct, ts.isoformat(), f"{amount:.2f}", txn_type])
    return {
        "accounts": _to_csv(
            ["account_id", "customer_id", "product_type", "opened_date", "status", "currency"], accounts
        ),
        "transactions": _to_csv(["txn_id", "account_id", "txn_ts", "amount", "txn_type"], txns),
    }


GENERATORS = {"customer": generate_customer, "accounts": generate_accounts}


def generate(cfg: GeneratorConfig) -> dict[str, str]:
    """Return {entity: csv_text} for the configured business domain."""
    try:
        gen = GENERATORS[cfg.business]
    except KeyError as exc:
        raise ValueError(f"no generator for business {cfg.business!r}") from exc
    return gen(cfg)


def landing_object(entity: str) -> str:
    """Object path of an entity's file in the landing bucket: <entity>/<entity>.csv."""
    return f"{entity}/{entity}.csv"


def write_local(files: dict[str, str], out_dir: str) -> list[str]:
    import pathlib

    written = []
    for entity, text in files.items():
        path = pathlib.Path(out_dir) / landing_object(entity)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        written.append(str(path))
    return written


def write_gcs(files: dict[str, str], bucket: str, client=None) -> list[str]:
    if client is None:
        from google.cloud import storage

        client = storage.Client()
    b = client.bucket(bucket)
    written = []
    for entity, text in files.items():
        name = landing_object(entity)
        b.blob(name).upload_from_string(text, content_type="text/csv")
        written.append(f"gs://{bucket}/{name}")
    return written


__all__ = [
    "GeneratorConfig", "generate", "write_local", "write_gcs", "landing_object",
    "RESERVED_EMAIL_DOMAINS", "RESERVED_MOBILES", "RESERVED_LANDLINE_PREFIXES",
]
