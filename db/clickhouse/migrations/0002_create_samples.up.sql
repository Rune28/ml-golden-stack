-- MNIST examples, added in batches by the `ingest` step. Append-only:
-- a batch is never changed, a retried ingest skips a batch_id it already wrote.
CREATE TABLE ml_data.samples
(
    -- Link to the rest of the platform: the id of the ingest workflow that
    -- wrote the batch. Leading the sorting key, so per-batch lookups
    -- (the idempotency check, lineage queries) read only that batch.
    batch_id LowCardinality(String),
    idx      UInt32,
    split    Enum8('train' = 1, 'test' = 2),
    label    UInt8,
    -- 28x28 grayscale, row by row. ZSTD packs the mostly-zero background
    -- several times better than the default LZ4.
    pixels   Array(UInt8) CODEC(ZSTD(3)),
    added_at DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (batch_id, idx)
