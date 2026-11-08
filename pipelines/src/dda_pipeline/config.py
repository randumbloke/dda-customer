"""Pipeline configuration: steps.yaml, config.yaml and the runtime environment."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

import yaml


def pipeline_home() -> Path:
    """The pipelines/ directory (steps.yaml, sql/, lineage/). Override with DDA_PIPELINE_HOME."""
    env = os.environ.get("DDA_PIPELINE_HOME")
    if env:
        return Path(env)
    return Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Step:
    name: str
    stage: str
    sql: str


@dataclass(frozen=True)
class Fixture:
    name: str
    sql: str
    description: str = ""


@dataclass(frozen=True)
class Steps:
    steps: list[Step]
    fixtures: dict[str, Fixture]

    def for_stage(self, stage: str) -> list[Step]:
        return [s for s in self.steps if s.stage == stage]


def load_steps(home: Path | None = None) -> Steps:
    home = home or pipeline_home()
    doc = yaml.safe_load((home / "steps.yaml").read_text(encoding="utf-8"))
    steps = [Step(name=s["name"], stage=s["stage"], sql=s["sql"]) for s in doc.get("steps", [])]
    for s in steps:
        if s.stage not in ("ingest", "build"):
            raise ValueError(f"step {s.name}: stage must be ingest or build, not {s.stage!r}")
    fixtures = {
        k: Fixture(name=k, sql=v["sql"], description=v.get("description", ""))
        for k, v in (doc.get("fixtures") or {}).items()
    }
    return Steps(steps=steps, fixtures=fixtures)


@dataclass(frozen=True)
class RuntimeConfig:
    business: str
    env: str
    region: str
    job_project: str
    core_project: str
    analytics_project: str
    landing_bucket: str
    scans: list[str] = field(default_factory=list)
    consumed_tables: dict[str, str] = field(default_factory=dict)

    @property
    def domain(self) -> str:
        return f"{self.business}-{self.env}"

    def template_vars(self) -> dict[str, str]:
        values = {
            "business": self.business,
            "env": self.env,
            "domain": self.domain,
            "region": self.region,
            "core_project": self.core_project,
            "analytics_project": self.analytics_project,
            "landing_bucket": self.landing_bucket,
        }
        for key, table in self.consumed_tables.items():
            values[f"consumed_{key}"] = table
        return values

    @classmethod
    def from_env(cls, environ: dict[str, str] | None = None) -> "RuntimeConfig":
        e = os.environ if environ is None else environ

        def need(name: str) -> str:
            value = e.get(name, "")
            if not value:
                raise KeyError(f"environment variable {name} is required")
            return value

        scans = [s for s in e.get("DDA_SCANS", "").split(",") if s]
        consumed = json.loads(e.get("DDA_CONSUMED_TABLES") or "{}")
        return cls(
            business=need("DDA_BUSINESS"),
            env=need("DDA_ENV"),
            region=need("DDA_REGION"),
            job_project=need("DDA_JOB_PROJECT"),
            core_project=need("DDA_CORE_PROJECT"),
            analytics_project=need("DDA_ANALYTICS_PROJECT"),
            landing_bucket=need("DDA_LANDING_BUCKET"),
            scans=scans,
            consumed_tables=consumed,
        )
