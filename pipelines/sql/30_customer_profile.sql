-- Build the Customer Profile product table in the analytics dataset (design §3.4, pipeline-built
-- table). Runs as the analytics account, which reads curated and writes analytics.
CREATE TABLE IF NOT EXISTS `${analytics_project}.${business}_analytics.customer_profile` (
  customer_id STRING,
  full_name STRING,
  email STRING,
  phone STRING,
  postcode STRING,
  state STRING,
  segment_code STRING,
  segment_name STRING,
  marketing_opt_in BOOL,
  age_band STRING,
  customer_since DATE,
  refreshed_at TIMESTAMP
);

TRUNCATE TABLE `${analytics_project}.${business}_analytics.customer_profile`;

INSERT INTO `${analytics_project}.${business}_analytics.customer_profile`
SELECT
  customer_id,
  CONCAT(given_name, ' ', family_name) AS full_name,
  email,
  phone,
  postcode,
  state,
  segment_code,
  segment_name,
  marketing_opt_in,
  CASE
    WHEN age < 30 THEN '18-29'
    WHEN age < 45 THEN '30-44'
    WHEN age < 60 THEN '45-59'
    ELSE '60+'
  END AS age_band,
  created_date AS customer_since,
  CURRENT_TIMESTAMP() AS refreshed_at
FROM (
  SELECT *, DATE_DIFF(CURRENT_DATE(), date_of_birth, YEAR) AS age
  FROM `${core_project}.${business}_curated.contacts`
);
