-- Output of the `predict` step: one row per test example per run.
CREATE TABLE ml_data.predictions
(
    run_id        LowCardinality(String),
    model_version LowCardinality(String),
    idx           UInt32,
    label         UInt8,
    predicted     UInt8,
    confidence    Float32,
    predicted_at  DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (run_id, idx)
