-- AT-14 (second case): a sensitive table whose scan publishes to the catalogue but does not
-- export. The scan is created by hand from sql/fixtures/at14_noexport_scan.yaml (RUNBOOK.md),
-- because this repository's scans always export. Delete both after the test.
CREATE TABLE IF NOT EXISTS `${core_project}.${business}_curated.at14_noexport` AS
SELECT customer_id, email
FROM `${core_project}.${business}_curated.contacts`
LIMIT 10;
