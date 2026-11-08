# dda-customer

Domain repository of the **Customer** business domain (`customer-<env>`) of the Decentralised
Data Architecture (DDA) reference deployment. It holds the domain's declarative files, the
Terraform that turns them into datasets, bindings, scans, products and contracts for this domain
only, and the domain's reference pipeline (design §3, §6.1; change `mvp-phase-1-build`, phase 1).
Applied by `tf-customer-<tier>` (with `single_deployer = true`, `tf-deployer`).

## Layout

```text
datasets.yaml                 datasets and table contacts (design §3.3)
products/customer-profile.yaml  the Customer Profile data product (§3.2)
dq/<dataset>/<table>.yaml     one scan specification per sensitive table (§3.6)
schemas/                      vendored JSON Schemas (from kc-control-plane/schemas; see schemas/VERSION)
envs/labels.json              labels (§1.6)
envs/dev/core/                datasets, access entries, bindings, table contacts, scans, products,
                              assets, access groups, published files, pipeline jobs (§6.13.2)
envs/dev/contract/            refresh-cadence on each published product's @dataplex entry (§3.2.1)
pipelines/                    P6-39 reference pipeline (Python, uv): generator, SQL steps, Cloud Run
                              job entrypoint, lineage manifest, Dockerfile, cloudbuild.yaml
.github/workflows/ci.yml      ci-checks
```

The `.tf` files are generic: every value comes from `<env>.tfvars`, the declarative files and the
published JSON files, so `dda-accounts` uses the same `.tf` files unchanged.

## Checks

```sh
terraform fmt -check -recursive
for s in envs/dev/core envs/dev/contract; do terraform -chdir=$s init -backend=false && terraform -chdir=$s validate; done
cd pipelines && uv sync && uv run pytest && uv run dda-pipeline validate --root ..
```

## Deployment

The build applies `envs/dev/core`, then `envs/dev/contract` (§6.13.1, §6.14), each with
`terraform init -backend-config=state.config` and `-var-file=dev.tfvars`. `core` reads
`bootstrap/estate.json`, the `dda-platform` and `cdmc-governance` tier and `dev` outputs; a missing
file fails the plan (AT-26). `contract` reads `outputs/dda-customer/dev/outputs.json` written by `core`.

### Apply order on first deployment

Tables are created by the pipeline, not Terraform. Resources that need an existing table (scans,
product assets, table contacts) are declared for tables that exist at plan time, so the stack
converges in two passes:

1. `core` apply: datasets, access entries, bindings, products, access groups, published files.
2. Upload the synthetic files (`uv run dda-pipeline generate --business customer --bucket kcdda-core-dwh-dev-customer-landing`),
   then run `customer-ingest` and `customer-build` (or run the stages locally with the `DDA_*` variables).
3. `core` apply again: scans, assets and table contacts for the new tables (`terraform output pending_tables` lists what is still waiting).
4. `contract` apply; then run the pipeline again so the scans run after the load.

The pipeline jobs are off (`pipeline.enabled = false`) until the image is built
(`gcloud builds submit --config pipelines/cloudbuild.yaml .`) and its path is set in `dev.tfvars`.

## Acceptance tests served (design §6.18)

| AT | Artefact |
|---|---|
| AT-04 | `main.datasets.tf`: three datasets with labels, explicit access list, `ignore_changes` |
| AT-05 | `main.bindings.tf`: three dataset and one product binding; `bindings/dev/customer-dev/bindings.json` |
| AT-06 | Every stack: no timestamps or other per-run values in resources; `commit_sha` only changes per commit |
| AT-07 | `google_cloud_identity_group.access` declares no memberships; dataset `ignore_changes = [access]` |
| AT-08 | `main.products.tf`: product with owners, approvers, access group, asset; published definition |
| AT-09 | `envs/dev/contract`: `refresh-cadence` from `contract.refresh_cadence`; the contract aspect is not written here |
| AT-11, AT-12, AT-13 | Metadata changes from every apply and pipeline run (tables, aspects, scans) feed `feed-evaluator`; twenty table updates: re-run `customer-ingest`; AT-13 uses a dataset with no event |
| AT-14 | `dq/` (six specs, export on); fixture `at14` (sensitive table with no spec). The scan that publishes but does not export is created by hand during the test, because this repository always exports |
| AT-15 | `customer_profile` critical rules; `generate --inject-failures` makes them fail |
| AT-16 | `contract.refresh_cadence` (daily, 120 min); skip a pipeline run |
| AT-17 | `notification_report` to the product owners group, `score_threshold` 95 |
| AT-18 | Fixture `at18` (no source table, created that day) |
| AT-19 | Fixture `at19` (sensitive, no lineage; assert after 48 hours) |
| AT-20 | `pipelines/lineage/manifest.json`: **deliberate undeclared source** — `customer_curated.contacts_by_region` reads `customer_raw.postcodes` (step `contacts-by-region`), which its manifest entry omits → `MISMATCH`. `customer_profile` declares `customer_curated.contact_preferences`, which it never reads → not a mismatch |
| AT-21 | `customer_profile` (all run-time sources declared) → `VERIFIED`; `customer_raw.postcodes`, loaded from Cloud Storage with no manifest entry → `VERIFIED` on run-time evidence |
| AT-23 | Customer Profile's `reader` access group and asset; consumed by `dda-accounts` |
| AT-26 | `main.inputs.tf` postconditions on every published file; `contract` on `outputs.json` |

## VERIFY IN BUILD markers

| ID | Where | What |
|---|---|---|
| VA-12 | `main.bindings.tf` | `policy_member` can be granted a role |
| VA-15 | `main.bindings.tf` | Product full resource name accepted by bindings |
| VA-34 | `main.scans.tf` | `cdmc-critical` attribute survives to results and export |
| VA-35 | `main.scans.tf` | Cross-project export to the hub `dq_results.scan_results` |
| VA-42 | `main.contacts.tf` | Writing the `contacts` system aspect |
| VA-49 | `main.bindings.tf` | `ddaDomainDelegate` suffices for a binding |
| VA-55 | `main.products.tf` | `ownerEmails` accepts a group |
| VA-56 | `main.products.tf`, `main.contacts.tf`, `contract/main.contracts.tf` | `@dataplex` entry name and type; `google_dataplex_entry` changes only declared aspects (fallback `entries.patch` with `aspectKeys`) |
| VA-58 | `main.inputs.tf`, `main.datasets.tf`, `main.scans.tf` | Dataplex agent key `dataplex` and its grants; `dataScanEditor` to run scans |
| VA-63, VA-80 | `main.scans.tf` | Group recipients; 0 to 100 score threshold |
| VA-64 (VA-22) | `pipelines/sql/10_load_contacts.sql` | Lineage for `LOAD DATA` from Cloud Storage |
| VA-87 | `main.bindings.tf` | `ddaDomainBinder` scope |
| VA-94 | `main.datasets.tf` | Dataset access pattern |
| estate | `dev.tfvars`, `main.pipeline.tf`, `pipelines/cloudbuild.yaml` | Pipeline image repository `dda-pipelines`; Run and Scheduler APIs and `serviceAccountUser` on the runtime accounts |

## Contract differences

- **Product tables are built by `customer-analytics-dev`, not the ingest account.** Design §3.1 and
  P6-39 say the job runs as the ingest account and builds the product tables, but §2.4.2, §2.4.3
  and §3.3 give the ingest account write on raw/staging/curated only and make the analytics account
  the analytics datasets' writer. The pipeline therefore has two jobs from one image: `ingest`
  (ingest account) and `build` (analytics account).
- **Generator outside the job.** The ingest account has only `storage.objectViewer` on the landing bucket (§2.4.2).
- **Running scans** needs `dataplex.datascans.run`, which no grant table gives the runtime accounts;
  this stack grants `roles/dataplex.dataScanEditor` on each scan to the account that writes its table.
- **Access group managers** (`gate-<env>`, `reconciler-<env>`, product owners, §3.2) are not
  declared: §6.15.3 forbids `google_cloud_identity_group_membership` outside `bootstrap/`, and the
  gate and reconciler are off in phase 1.
- **Product IAM**: §3.2 names no `google_dataplex_data_product_iam_member`; the only product grant
  (`ddaDomainDelegate`) is made by the binding module.
- **Notification threshold for tables that serve no product** uses the domain's lowest product threshold.
- **Lineage manifest** lists immediate sources (as the contract fixture does); it is environment-specific (dev project IDs).
- **Artifact Registry `dda-pipelines`** is not in the contracts.
