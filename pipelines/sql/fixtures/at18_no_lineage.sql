-- AT-18: a table created today with no lineage (no source table), in a sensitive dataset.
CREATE TABLE IF NOT EXISTS `${core_project}.${business}_curated.at18_no_lineage` (
  fixture_id STRING,
  note STRING
);
INSERT INTO `${core_project}.${business}_curated.at18_no_lineage` (fixture_id, note)
VALUES ('1', 'synthetic AT-18 fixture with no source table');
