-- Chạy: psql -d shop -v scale=0.2 -f setup.sql
-- scale = 1  ->  ~1M customers, 5M orders, ~11M order_items, 20M events (~5 GB)
\set ON_ERROR_STOP on
\timing on
\if :{?scale}
\else
  \set scale 1
\endif
\echo '>>> scale =' :scale

\ir 01_schema.sql
\ir 02_data.sql
\ir 03_finalize.sql
