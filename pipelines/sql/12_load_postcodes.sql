-- Load the postcode reference file into the raw dataset (P6-39). This table has no lineage
-- manifest entry: it is the AT-21 table "loaded directly from Cloud Storage".
LOAD DATA OVERWRITE `${core_project}.${business}_raw.postcodes` (
  postcode STRING,
  region STRING,
  state STRING
)
FROM FILES (
  format = 'CSV',
  skip_leading_rows = 1,
  uris = ['gs://${landing_bucket}/postcodes/*.csv']
);
