-- What readers use instead of digit_report: the latest committed report of
-- every prediction run. The table keeps every report, and a report run
-- writes and rewrites only its own rows. A report is visible once its
-- marker is in the registry, and "latest" is by its logical start, so
-- neither a report halfway through nor an old run retried late is shown.
CREATE VIEW IF NOT EXISTS ml_data.digit_report_latest AS
SELECT prediction_run_id, run_id, model_version, digit, recognized, actual, created_at
FROM ml_data.digit_report
WHERE run_id IN (
    SELECT argMax(run_id, started_at)
    FROM ml_data.runs FINAL
    WHERE kind = 'report'
    GROUP BY parents['prediction_run_id']
)
