-- Clean and de-duplicate contacts into the curated dataset. Truncate and insert, never replace:
-- replacing a table would drop its catalog aspects and any table IAM.
CREATE TABLE IF NOT EXISTS `${core_project}.${business}_curated.contacts` (
  customer_id STRING,
  given_name STRING,
  family_name STRING,
  email STRING,
  phone STRING,
  postcode STRING,
  state STRING,
  date_of_birth DATE,
  segment_code STRING,
  segment_name STRING,
  marketing_opt_in BOOL,
  created_date DATE,
  load_ts TIMESTAMP
);

TRUNCATE TABLE `${core_project}.${business}_curated.contacts`;

INSERT INTO `${core_project}.${business}_curated.contacts`
SELECT
  c.customer_id,
  TRIM(c.given_name) AS given_name,
  TRIM(c.family_name) AS family_name,
  LOWER(TRIM(c.email)) AS email,
  c.phone,
  c.postcode,
  UPPER(TRIM(c.state)) AS state,
  c.date_of_birth,
  c.segment_code,
  s.segment_name,
  c.marketing_opt_in,
  c.created_date,
  CURRENT_TIMESTAMP() AS load_ts
FROM `${core_project}.${business}_raw.contacts` AS c
LEFT JOIN `${core_project}.${business}_raw.segments` AS s
  USING (segment_code)
QUALIFY ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY c.created_date DESC) = 1;
