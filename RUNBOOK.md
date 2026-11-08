# Runbook: dda-customer, phase 1 (`dev`)

How to deploy this repository the first time, then run each acceptance test (design §6.18) that it
serves, with commands and the evidence to record. In phase 1 every apply runs as `tf-deployer`
from the merge build (§6.7.2). The commands below show the same steps by hand, for a bootstrap
administrator or a scratch build. They are not a way around the merge gate.

```sh
export REGION=australia-southeast1 HUB=kcdda-dgov-hub-nonprod CORE=kcdda-core-dwh-dev \
       ANA=kcdda-customer-analytics-dev STATE=tfstate-pltfrm-ngnrng HUBSTATE=kcdda-dgov-hub-nonprod-dda-state \
       LANDING=kcdda-core-dwh-dev-customer-landing DOMAIN=customer-dev
```

## 0. Preconditions

| Check | Command | Expected |
|---|---|---|
| Upstream files published | `gcloud storage ls gs://$STATE/bootstrap/estate.json gs://$STATE/outputs/dda-platform/tiers/nonprod/outputs.json gs://$STATE/outputs/dda-platform/dev/outputs.json gs://$STATE/outputs/cdmc-governance/tiers/nonprod/outputs.json gs://$STATE/outputs/cdmc-governance/dev/outputs.json` | All five listed |
| Domain and discovery present | `gcloud storage cat gs://$STATE/outputs/cdmc-governance/dev/outputs.json \| jq '.domains["customer-dev"].subdomains \| keys, .discovery_configs \| keys'` | `analytics`, `curated`, `raw` (and `staging`); both data projects |
| Groups exist (task 2.5) | `gcloud identity groups describe dda-customer-dev-owners@mikegyoung.joonix.net` (and `-stewards`, `dda-dp-customer-profile-dev-owners`) | Found |

## 1. First deployment

| Step | Command | Evidence |
|---|---|---|
| 1. `core` apply 1 | `cd envs/dev/core && terraform init -backend-config=state.config && terraform apply -var-file=dev.tfvars -var commit_sha=$(git rev-parse HEAD)` | Datasets, products, access group, bindings created. `terraform output pending_tables` lists the six scanned tables and the asset table |
| 2. Land files | `cd pipelines && uv sync && uv run dda-pipeline generate --business customer --bucket $LANDING` (needs write on the bucket) | `gs://$LANDING/{contacts,segments,postcodes}/*.csv` |
| 3. Pipeline run | With jobs enabled: `gcloud run jobs execute customer-ingest --project $CORE --region $REGION --wait`, then `gcloud run jobs execute customer-build --project $ANA --region $REGION --wait`. Without jobs: export the `DDA_*` variables of `main.pipeline.tf` and run `uv run dda-pipeline run --stage ingest` as `customer-ingest-dev` (impersonation), then `--stage build` as `customer-analytics-dev` | `bq ls $CORE:customer_raw`, `customer_curated`, `$ANA:customer_analytics` show the tables. Scans print `SKIPPED` on this first run |
| 4. `core` apply 2 | Same as step 1 | Six `dq-*` scans, the asset `customer-profile`, the table contacts on `customer_curated.contacts`. `pending_tables` is empty |
| 5. `contract` apply | `cd envs/dev/contract && terraform init -backend-config=state.config && terraform apply -var-file=dev.tfvars` | Imports `@dataplex` entry; sets `refresh-cadence` |
| 6. Pipeline run 2 | As step 3 | Each scan prints `SUCCEEDED` |
| 7. Pipeline image (once) | `gcloud builds submit --project pltfrm-ngnrng --config pipelines/cloudbuild.yaml --service-account=projects/pltfrm-ngnrng/serviceAccounts/tf-deployer@pltfrm-ngnrng.iam.gserviceaccount.com --substitutions=_BUSINESS=customer,_TAG=$(git rev-parse --short HEAD) .` (tags are immutable: one `_TAG` per build). Then set `pipeline.image` to the printed `PIPELINE_IMAGE=...@sha256:...` and `pipeline.enabled = true` in `dev.tfvars` and merge | Jobs `customer-ingest`, `customer-build` and two scheduler jobs |

If step 1 fails on a missing published file, apply the upstream stack first (that is AT-26).

## 2. Acceptance tests

| AT | Steps | Evidence to record |
|---|---|---|
| AT-04 | `for d in customer_raw customer_curated; do bq show --format=prettyjson $CORE:$d \| jq '.labels, .access'; done; bq show --format=prettyjson $ANA:customer_analytics \| jq '.labels, .access'` | Labels `dda-domain=customer-dev`, `dda-stage`, `cdmc-sensitivity=sensitive`. Access: OWNER `tf-deployer`, WRITER ingest or analytics account, READER `dda-customer-dev-owners`, plus later entries (Dataplex agent, analytics reader, `ddaDomainDelegate`). No `projectReaders`/`projectWriters`/`projectOwners` |
| AT-05 | `curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" "https://dataplex.googleapis.com/v1/$(gcloud storage cat gs://$STATE/outputs/cdmc-governance/dev/outputs.json \| jq -r '.domains["customer-dev"].subdomains.curated.name')/bindings"` for each subdomain; `gcloud storage cat gs://$HUBSTATE/bindings/dev/$DOMAIN/bindings.json` | `ds-customer-raw`, `ds-customer-curated`, `ds-customer-analytics`, `dp-customer-profile` exist and match the file |
| AT-06 | `terraform plan -var-file=dev.tfvars -detailed-exitcode` in `core` and `contract` after step 6 | Exit code 0 (no changes) |
| AT-07 | Add a member to `dda-dp-customer-profile-dev-reader` by console approval (see AT-23 in `dda-accounts`). Then `core` apply, then `gcloud identity groups memberships list --group-email=dda-dp-customer-profile-dev-reader@mikegyoung.joonix.net` | Member still present; plan shows no membership change |
| AT-08 | `curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" https://dataplex.googleapis.com/v1/projects/$ANA/locations/$REGION/dataProducts/customer-profile`; `gcloud storage cat gs://$HUBSTATE/products/dev/$DOMAIN/customer-profile.json` | `ownerEmails`, `accessApprovalConfig.approverEmails`, `accessGroups.reader`, one asset; published file valid (`uv run --project ../kc-control-plane kc-validate file <file> --schema published_product`) |
| AT-09 | `gcloud dataplex entries lookup --project=$ANA --location=$REGION --entry=<dataplex_entry from outputs.json> --view=ALL` (or `entries.lookup` by REST) | `refresh-cadence`: Daily, 06:00, 120. `cdmc-data-product-contract` written by `evaluator-dev` only (audit log `principalEmail`) |
| AT-11, AT-12, AT-13 | AT-11: step 4 or any `core` apply changes metadata. AT-12: run `customer-ingest` with twenty table updates, for example `for i in $(seq 20); do bq query --use_legacy_sql=false --label dda-domain:customer-dev "UPDATE \`$ANA.customer_analytics.customer_profile\` SET refreshed_at = CURRENT_TIMESTAMP() WHERE TRUE"; done` as the analytics account. AT-13: leave `customer_raw` untouched for a day | Evaluator logs and `cdmc_report.events` rows (governance repository); one rollup task for `customer-profile` |
| AT-14 | (a) `gcloud run jobs execute customer-ingest --args=fixtures,--at,at14 ...` (or `uv run dda-pipeline fixtures --at at14`). (b) `... --at at14-noexport`, then create the scan by hand: `gcloud dataplex datascans create data-quality at14-noexport --project=$CORE --location=$REGION --data-source-resource=//bigquery.googleapis.com/projects/$CORE/datasets/customer_curated/tables/at14_noexport --data-quality-spec-file=pipelines/sql/fixtures/at14_noexport_scan.yaml --on-demand=true`, then `gcloud dataplex datascans run at14-noexport --project=$CORE --location=$REGION` | Two C12 coverage findings in `cdmc_report.events`: no scan for `at14_unscanned`; no export for `at14_noexport`. Then delete both tables and the scan |
| AT-15 | `uv run dda-pipeline generate --business customer --bucket $LANDING --inject-failures`, then run both jobs | `customer-id-not-null` fails on `customer_profile`; `aggregate_dq_status = NON_COMPLIANT` on Customer Profile; product status finding. Restore with a normal `generate` and rerun |
| AT-16 | Skip `customer-build` for more than 06:00 plus 120 minutes (pause `customer-build-daily`: `gcloud scheduler jobs pause customer-build-daily --project $ANA --location $REGION`) | `freshness_status = LATE`; finding. Resume afterwards |
| AT-17 | During AT-15 | The scan report e-mail for `dq-customer-analytics-customer-profile` reaches `dda-dp-customer-profile-dev-owners` (score below 95) |
| AT-18 | On the test day: `--at at18` (no lineage) and `--at at18-cycle` (lineage with no resolved source) | C14 `PENDING` on `customer_curated.at18_no_lineage` and `customer_curated.at18_cycle_a` |
| AT-19 | On day 1: `--at at19`; assert on day 3 or later | C14 `INSUFFICIENT_EVIDENCE` on `customer_curated.at19_no_lineage` (sensitive). The non-sensitive table is in `dda-accounts` |
| AT-20 | After step 6 | `MISMATCH` on `customer_curated.contacts_by_region` with `undeclared_sources` naming `customer_raw.postcodes` (or its landing file). `customer_profile` declares `customer_curated.contact_preferences`, which is never read, and is not `MISMATCH` for it |
| AT-21 | After step 6 | `VERIFIED` on `customer_analytics.customer_profile`, with `cdmc-lineage-evidence` written. `VERIFIED` on `customer_raw.postcodes` (Cloud Storage source, no manifest entry). VERIFY IN BUILD (VA-64): the Cloud Storage FQN that `LOAD DATA` records; if load jobs record no Cloud Storage source, the raw tables become the leaves and `customer_profile` compares them with its expanded declaration |
| AT-26 | Rename the governance outputs object temporarily in a scratch state bucket, or plan with `-var tf_state_bucket=<empty scratch bucket>` | Plan fails at `data.google_storage_bucket_object_content.published` naming the missing file; nothing changes. `terraform test` covers it offline (`missing_published_file_fails_plan`) |
