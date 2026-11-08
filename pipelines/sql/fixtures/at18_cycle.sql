-- AT-18 (second case): a table with run-time lineage but no resolved ultimate source. Two
-- tables are written from each other, so the upstream walk from at18_cycle_a meets only a cycle
-- and ends at an intermediate node (design §5.4.1; kc-control-plane c14.rules.resolve).
CREATE TABLE IF NOT EXISTS `${core_project}.${business}_curated.at18_cycle_a` (fixture_id STRING);
CREATE TABLE IF NOT EXISTS `${core_project}.${business}_curated.at18_cycle_b` (fixture_id STRING);
INSERT INTO `${core_project}.${business}_curated.at18_cycle_a` (fixture_id)
SELECT fixture_id FROM `${core_project}.${business}_curated.at18_cycle_b`;
INSERT INTO `${core_project}.${business}_curated.at18_cycle_b` (fixture_id)
SELECT fixture_id FROM `${core_project}.${business}_curated.at18_cycle_a`;
