-- Load landed contacts into the raw dataset, as landed (P6-39). Lineage: GCS -> raw.
-- VERIFY IN BUILD (VA-64): run-time lineage from the Cloud Storage files appears for LOAD DATA
-- (AT-21 needs a resolved source for a table loaded from Cloud Storage); VA-22 bounds the latency.
LOAD DATA OVERWRITE `${core_project}.${business}_raw.contacts` (
  customer_id STRING,
  given_name STRING,
  family_name STRING,
  email STRING,
  phone STRING,
  postcode STRING,
  state STRING,
  date_of_birth DATE,
  segment_code STRING,
  marketing_opt_in BOOL,
  created_date DATE
)
FROM FILES (
  format = 'CSV',
  skip_leading_rows = 1,
  uris = ['gs://${landing_bucket}/contacts/*.csv']
);
