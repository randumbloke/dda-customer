-- AT-19: a sensitive table with no lineage, asserted 48 hours or more after creation.
CREATE TABLE IF NOT EXISTS `${core_project}.${business}_curated.at19_no_lineage` (
  fixture_id STRING,
  note STRING
);
INSERT INTO `${core_project}.${business}_curated.at19_no_lineage` (fixture_id, note)
VALUES ('1', 'synthetic AT-19 fixture with no source table');
