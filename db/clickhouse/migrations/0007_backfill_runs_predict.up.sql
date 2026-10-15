-- Markers for prediction runs written before the registry. Every one of
-- them counts as complete, since a partial run cannot be told apart here;
-- its logical start is unknown, the time of its first row stands in.
INSERT INTO ml_data.runs (run_id, kind, parents, started_at, rows)
SELECT run_id, 'predict', map('model_version', any(model_version)), min(predicted_at), count()
FROM ml_data.predictions
WHERE run_id NOT IN (SELECT run_id FROM ml_data.runs)
GROUP BY run_id
