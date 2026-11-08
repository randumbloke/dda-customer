-- AT-14: a sensitive table in ${business}_curated with no scan specification. Do not add a
-- dq/ file for it; delete it after the test.
CREATE TABLE IF NOT EXISTS `${core_project}.${business}_curated.at14_unscanned` AS
SELECT customer_id, email
FROM `${core_project}.${business}_curated.contacts`
LIMIT 10;
