-- Run registry: one row per run whose data is complete. A step writes its
-- rows first and this marker last, so readers, who see data only through
-- views joined with this table (README, rule 11), never see a run halfway.
-- Written by the platform layer of the Jobs (mle_models/src/jobs), not by
-- model code.
--
-- run_id is unique across the platform and is the whole key: a repeated
-- commit (a Job retried after its commit) is a duplicate that merges away,
-- which is why views read `runs FINAL`.
CREATE TABLE ml_data.runs
(
    run_id       String,
    kind         LowCardinality(String),
    -- Keys of the inputs, named as their columns downstream: lineage.
    parents      Map(LowCardinality(String), String),
    -- Logical time: when the workflow scheduled the step. It stays the same
    -- across retries, so an old run retried late never becomes the latest.
    started_at   DateTime64(3, 'UTC'),
    rows         UInt64,
    committed_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(committed_at)
ORDER BY run_id
