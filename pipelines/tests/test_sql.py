import json

import pytest
import yaml

from dda_pipeline import generator
from dda_pipeline.config import RuntimeConfig, load_steps
from dda_pipeline.runner import job_labels, run_fixture, run_stage
from dda_pipeline.sql import render, render_file, table_refs


def test_every_step_and_fixture_renders(home, runtime):
    steps = load_steps(home)
    assert steps.steps, "no steps"
    for path in [s.sql for s in steps.steps] + [f.sql for f in steps.fixtures.values()]:
        sql = render_file(home, path, runtime.template_vars())
        assert "${" not in sql
        assert sql.strip()


def test_missing_placeholder_raises():
    with pytest.raises(KeyError):
        render("SELECT * FROM `${core_project}.x.y`", {})


def test_tables_are_in_declared_datasets(home, runtime, repo):
    datasets = yaml.safe_load((repo / "datasets.yaml").read_text())["datasets"]
    consumed = set(runtime.consumed_tables.values())
    for step in load_steps(home).steps:
        sql = render_file(home, step.sql, runtime.template_vars())
        for ref in table_refs(sql):
            if ref in consumed:
                continue
            project, dataset, _ = ref.split(".")
            assert dataset in datasets, f"{step.name}: {ref} is not in a declared dataset"
            expected = runtime.analytics_project if datasets[dataset]["stage"] == "analytics" else runtime.core_project
            assert project == expected, f"{step.name}: {ref} is in the wrong project"


def test_stage_writes_only_its_datasets(home, runtime, repo):
    # ingest writes raw, staging and curated; build writes analytics (design §2.4.2, §2.4.3).
    datasets = yaml.safe_load((repo / "datasets.yaml").read_text())["datasets"]
    for step in load_steps(home).steps:
        sql = render_file(home, step.sql, runtime.template_vars())
        targets = [r for r in table_refs(sql) if any(
            kw + " `" + r + "`" in sql for kw in ("LOAD DATA OVERWRITE", "INSERT INTO", "TRUNCATE TABLE", "CREATE TABLE IF NOT EXISTS")
        )]
        assert targets, step.name
        for t in targets:
            stage = datasets[t.split(".")[1]]["stage"]
            assert (stage == "analytics") == (step.stage == "build"), f"{step.name} writes {t}"


def test_load_uris_match_generator(home, runtime, business):
    entities = generator.generate(generator.GeneratorConfig(business=business, customers=5, accounts=5, transactions=5))
    loads = [s for s in load_steps(home).steps if s.name.startswith("load-")]
    rendered = "\n".join(render_file(home, s.sql, runtime.template_vars()) for s in loads)
    for entity in entities:
        assert f"gs://{runtime.landing_bucket}/{entity}/*.csv" in rendered


def test_lineage_manifest_matches_sql(home, runtime, repo):
    # Every manifest target is written by a step; the AT-20 deliberate omission is documented.
    manifest = json.loads((home / "lineage" / "manifest.json").read_text())
    assert manifest["domain"] == runtime.domain
    written = set()
    for step in load_steps(home).steps:
        sql = render_file(home, step.sql, runtime.template_vars())
        written |= {r for r in table_refs(sql) if f"INSERT INTO `{r}`" in sql or f"LOAD DATA OVERWRITE `{r}`" in sql}
    assert set(manifest["targets"]) <= written


def test_job_labels(runtime):
    labels = job_labels(runtime, "curate-contacts")
    assert labels["dda-domain"] == runtime.domain


def test_run_stage_order_labels_and_scans(home, runtime):
    calls, scans = [], []

    def sql_runner(cfg, name, sql, client):
        calls.append((name, job_labels(cfg, name)))

    def scan_runner(name, client):
        scans.append(name)
        return "SUCCEEDED"

    steps = load_steps(home)
    result = run_stage(runtime, steps, "ingest", home, bq_client=object(), scan_client=object(),
                       sql_runner=sql_runner, scan_runner=scan_runner)
    assert [c[0] for c in calls] == [s.name for s in steps.for_stage("ingest")]
    assert all(c[1]["dda-domain"] == runtime.domain for c in calls)
    assert scans == runtime.scans
    assert result.ok


def test_failed_scan_fails_run(home, runtime):
    result = run_stage(runtime, load_steps(home), "build", home, bq_client=object(), scan_client=object(),
                       sql_runner=lambda *a: None, scan_runner=lambda n, c: "FAILED")
    assert not result.ok


def test_fixtures(home, runtime):
    steps = load_steps(home)
    for name in steps.fixtures:
        sql = run_fixture(runtime, steps, name, home, bq_client=object(), sql_runner=lambda *a: None)
        assert f"{runtime.business}_curated.{name}" in sql


def test_runtime_from_env():
    cfg = RuntimeConfig.from_env({
        "DDA_BUSINESS": "customer", "DDA_ENV": "dev", "DDA_REGION": "australia-southeast1",
        "DDA_JOB_PROJECT": "p", "DDA_CORE_PROJECT": "p", "DDA_ANALYTICS_PROJECT": "a",
        "DDA_LANDING_BUCKET": "b", "DDA_SCANS": "s1,s2", "DDA_CONSUMED_TABLES": '{"x": "a.b.c"}',
    })
    assert cfg.scans == ["s1", "s2"] and cfg.template_vars()["consumed_x"] == "a.b.c"
    with pytest.raises(KeyError):
        RuntimeConfig.from_env({})


def test_optional_step_failure_does_not_stop_run(home, runtime, tmp_path):
    import shutil

    from dda_pipeline.config import load_steps as _load

    shutil.copytree(home / "sql", tmp_path / "sql")
    (tmp_path / "steps.yaml").write_text(
        "steps:\n"
        "  - {name: a, stage: ingest, sql: sql/" + _load(home).steps[0].sql.split("/", 1)[1] + ", optional: true}\n"
        "  - {name: b, stage: ingest, sql: sql/" + _load(home).steps[0].sql.split("/", 1)[1] + "}\n"
    )
    ran = []

    def sql_runner(cfg, name, sql, client):
        if name == "a":
            raise RuntimeError("Access Denied")
        ran.append(name)

    result = run_stage(runtime, _load(tmp_path), "ingest", tmp_path, bq_client=object(), scan_client=object(),
                       sql_runner=sql_runner, scan_runner=lambda n, c: "SUCCEEDED")
    assert ran == ["b"] and "a" in result.skipped_steps and result.ok


def test_consumed_products_are_read_by_optional_steps(home):
    # AT-23: a step that reads another domain's product runs before access may be approved, so it
    # must be optional; every consumed product is read by some step.
    consumes = yaml.safe_load((home / "config.yaml").read_text()).get("consumes") or {}
    steps = load_steps(home).steps
    for key in consumes:
        readers = [s for s in steps if "${consumed_" + key + "}" in (home / s.sql).read_text()]
        assert readers, f"no step reads consumed product {key}"
        assert all(s.optional for s in readers)
