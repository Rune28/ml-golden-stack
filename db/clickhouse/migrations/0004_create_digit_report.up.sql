-- Output of the `report` step: how many of each digit the model recognized
-- in one prediction run, next to how many there really were. One row per
-- digit; a repeated report on the same prediction run rewrites it.
CREATE TABLE ml_data.digit_report
(
    prediction_run_id LowCardinality(String),
    report_run_id     LowCardinality(String),
    model_version     LowCardinality(String),
    digit             UInt8,
    recognized        UInt32,
    actual            UInt32,
    created_at        DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (prediction_run_id, digit)
