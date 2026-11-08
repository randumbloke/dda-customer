-- Load the segment reference file into the raw dataset (P6-39).
LOAD DATA OVERWRITE `${core_project}.${business}_raw.segments` (
  segment_code STRING,
  segment_name STRING
)
FROM FILES (
  format = 'CSV',
  skip_leading_rows = 1,
  uris = ['gs://${landing_bucket}/segments/*.csv']
);
