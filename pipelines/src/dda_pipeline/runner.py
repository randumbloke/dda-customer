"""Run the SQL steps of one stage, then the stage's on-demand data quality scans (P6-39)."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from pathlib import Path

from dda_pipeline.config import RuntimeConfig, Steps
from dda_pipeline.sql import render_file

log = logging.getLogger("dda_pipeline")

TERMINAL_SCAN_STATES = {"SUCCEEDED", "FAILED", "CANCELLED"}


def job_labels(cfg: RuntimeConfig, step: str) -> dict[str, str]:
    """Labels on every BigQuery job: dda-domain for cost attribution (design §1.6, §2.6)."""
    return {"dda-domain": cfg.domain, "dda-step": step.lower().replace("_", "-")[:63]}


@dataclass
class RunResult:
    steps: list[str] = field(default_factory=list)
    scans: dict[str, str] = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return all(state in ("SUCCEEDED", "SKIPPED") for state in self.scans.values())


def run_sql(cfg: RuntimeConfig, name: str, sql: str, bq_client) -> None:
    from google.cloud import bigquery

    job_config = bigquery.QueryJobConfig(labels=job_labels(cfg, name))
    log.info("step %s: running", name)
    job = bq_client.query(sql, job_config=job_config, location=cfg.region)
    job.result()
    log.info("step %s: done (job %s)", name, job.job_id)


def run_scan(name: str, scan_client, poll_seconds: float = 10.0, timeout_seconds: float = 1800.0) -> str:
    """Start an on-demand scan and wait for its job. Returns the job state, or SKIPPED when the
    scan does not exist yet (its table was created by this run; the next core apply adds it)."""
    from google.api_core import exceptions

    try:
        response = scan_client.run_data_scan(request={"name": name})
    except exceptions.NotFound:
        log.warning("scan %s does not exist yet; skipped", name)
        return "SKIPPED"
    job_name = response.job.name
    deadline = time.monotonic() + timeout_seconds
    while True:
        job = scan_client.get_data_scan_job(request={"name": job_name})
        state = job.state.name
        if state in TERMINAL_SCAN_STATES:
            log.info("scan %s: %s", name, state)
            return state
        if time.monotonic() > deadline:
            log.error("scan %s: no result after %s s", name, timeout_seconds)
            return "TIMEOUT"
        time.sleep(poll_seconds)


def run_stage(
    cfg: RuntimeConfig,
    steps: Steps,
    stage: str,
    home: Path,
    bq_client=None,
    scan_client=None,
    sql_runner=run_sql,
    scan_runner=run_scan,
) -> RunResult:
    if bq_client is None:
        from google.cloud import bigquery

        bq_client = bigquery.Client(project=cfg.job_project, location=cfg.region)
    result = RunResult()
    values = cfg.template_vars()
    for step in steps.for_stage(stage):
        sql = render_file(home, step.sql, values)
        sql_runner(cfg, step.name, sql, bq_client)
        result.steps.append(step.name)
    if cfg.scans:
        if scan_client is None:
            from google.cloud import dataplex_v1

            scan_client = dataplex_v1.DataScanServiceClient()
        for scan in cfg.scans:
            result.scans[scan] = scan_runner(scan, scan_client)
    return result


def run_fixture(cfg: RuntimeConfig, steps: Steps, fixture: str, home: Path, bq_client=None, sql_runner=run_sql) -> str:
    if fixture not in steps.fixtures:
        raise KeyError(f"unknown fixture {fixture!r}; known: {sorted(steps.fixtures)}")
    if bq_client is None:
        from google.cloud import bigquery

        bq_client = bigquery.Client(project=cfg.job_project, location=cfg.region)
    f = steps.fixtures[fixture]
    sql = render_file(home, f.sql, cfg.template_vars())
    sql_runner(cfg, f"fixture-{fixture}", sql, bq_client)
    return sql
