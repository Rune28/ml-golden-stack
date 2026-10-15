-- Markers for reports written before the registry, as in 0007.
INSERT INTO ml_data.runs (run_id, kind, parents, started_at, rows)
SELECT run_id, 'report', map('prediction_run_id', any(prediction_run_id)), min(created_at), count()
FROM ml_data.digit_report
WHERE run_id NOT IN (SELECT run_id FROM ml_data.runs)
GROUP BY run_id
