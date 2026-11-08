-- Customer counts by region. This step reads ${business}_raw.postcodes, which the lineage
-- manifest entry for ${business}_curated.contacts_by_region deliberately omits: the AT-20
-- MISMATCH (pipelines/lineage/manifest.json, README).
CREATE TABLE IF NOT EXISTS `${core_project}.${business}_curated.contacts_by_region` (
  region STRING,
  state STRING,
  customer_count INT64,
  load_ts TIMESTAMP
);

TRUNCATE TABLE `${core_project}.${business}_curated.contacts_by_region`;

INSERT INTO `${core_project}.${business}_curated.contacts_by_region`
SELECT
  p.region,
  p.state,
  COUNT(*) AS customer_count,
  CURRENT_TIMESTAMP() AS load_ts
FROM `${core_project}.${business}_curated.contacts` AS c
JOIN `${core_project}.${business}_raw.postcodes` AS p
  USING (postcode)
GROUP BY p.region, p.state;
