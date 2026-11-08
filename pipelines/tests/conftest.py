from pathlib import Path

import pytest

from dda_pipeline.config import RuntimeConfig

PIPELINES = Path(__file__).resolve().parents[1]
REPO = PIPELINES.parent


@pytest.fixture
def home() -> Path:
    return PIPELINES


@pytest.fixture
def repo() -> Path:
    return REPO


@pytest.fixture
def business(repo) -> str:
    # dda-<business> repository; the business is the dataset prefix in datasets.yaml.
    import yaml

    datasets = yaml.safe_load((repo / "datasets.yaml").read_text())["datasets"]
    return next(iter(datasets)).split("_")[0]


@pytest.fixture
def runtime(business) -> RuntimeConfig:
    import yaml

    consumes = yaml.safe_load((PIPELINES / "config.yaml").read_text()).get("consumes") or {}
    return RuntimeConfig(
        business=business,
        env="dev",
        region="australia-southeast1",
        job_project="kcdda-core-dwh-dev",
        core_project="kcdda-core-dwh-dev",
        analytics_project=f"kcdda-{business}-analytics-dev",
        landing_bucket=f"kcdda-core-dwh-dev-{business}-landing",
        scans=[f"projects/kcdda-core-dwh-dev/locations/australia-southeast1/dataScans/dq-{business}-x"],
        consumed_tables={k: "kcdda-customer-analytics-dev.customer_analytics.customer_profile" for k in consumes},
    )
