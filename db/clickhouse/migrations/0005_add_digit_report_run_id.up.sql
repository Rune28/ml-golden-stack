-- Expand step of renaming digit_report.report_run_id to run_id. The own key
-- of a table, the run that wrote the rows, is `run_id` in every table
-- (README, rule 5); 0004 named it after the step instead.
--
-- run_id defaults to report_run_id: the Job image of the previous release,
-- which writes only report_run_id, keeps working, and old rows read the
-- right value. The new image writes both columns. The contract step
-- (BACKLOG) drops report_run_id once no image writes it.
ALTER TABLE ml_data.digit_report
    ADD COLUMN IF NOT EXISTS run_id LowCardinality(String) DEFAULT report_run_id AFTER prediction_run_id
