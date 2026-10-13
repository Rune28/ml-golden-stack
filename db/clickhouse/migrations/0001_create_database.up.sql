-- One statement per file: ClickHouse DDL is not transactional, so a
-- migration either fully applies or leaves nothing behind.
-- migrate connects to `default` and keeps schema_migrations there,
-- because this database does not exist before the first migration.
CREATE DATABASE IF NOT EXISTS ml_data
