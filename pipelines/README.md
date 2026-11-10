# Reference domain pipeline (P6-39)

The domain's pipeline code (design §3.1, decision P6-39). It is the domain's choice; this is the
reference implementation used in phase 1.

| Part | File | What it does |
|---|---|---|
| Generator | `src/dda_pipeline/generator.py` | Faker (`en_AU`) with a fixed seed (`20261109`); e-mails only at `example.com/.net/.org`; telephone numbers only from the ACMA fictitious-use ranges. Writes `<entity>/<entity>.csv` to the landing bucket |
| Steps | `steps.yaml`, `sql/*.sql` | BigQuery SQL in order: `LOAD DATA` from the landing bucket, transform, build the product tables. Every job carries `dda-domain=<domain>` |
| Runner | `src/dda_pipeline/runner.py` | Runs one stage, then starts each of the stage's on-demand data quality scans and waits for it |
| Fixtures | `sql/fixtures/` | Acceptance-test tables (AT-14, AT-18, AT-19), run on demand |
| Lineage | `lineage/manifest.json` | Hand-written design-time lineage manifest (design §5.4.1), published by the core stack |
| Image | `Dockerfile` | One image for both Cloud Run jobs, built by the bootstrap trigger `dda-<business>-image` at each merge that changes `pipelines/` (P6-43); no build file lives here |

## Stages and identities

| Stage | Cloud Run job | Project | Runs as | Writes |
|---|---|---|---|---|
| `ingest` | `<business>-ingest` | core data | `<business>-ingest-<env>` | `_raw`/`_staging`, `_curated` |
| `build` | `<business>-build` | analytics | `<business>-analytics-<env>` | `_analytics` (product tables) |

The jobs and their daily Cloud Scheduler triggers are declared in `envs/<env>/core/main.pipeline.tf`
behind `pipeline.enabled`. Job configuration comes from `DDA_*` environment variables set there.

## Commands

```sh
uv sync
uv run pytest
uv run dda-pipeline generate --business <business> --out-dir out          # local files
uv run dda-pipeline generate --business <business> --bucket <landing-bucket>  # needs write on the bucket
uv run dda-pipeline validate --root ..                                     # declarative files vs schemas/
gcloud run jobs execute <business>-ingest --region australia-southeast1 --project <core>   # run a stage
gcloud run jobs execute <business>-ingest --args=fixtures,--at,at19 ...   # create a fixture
```

The generator is not run inside the jobs: the ingest account holds only `storage.objectViewer` on
the landing bucket (design §2.4.2). A developer or a build with write access to the bucket runs
it. `--inject-failures` breaks critical rules for AT-15 and AT-17.
