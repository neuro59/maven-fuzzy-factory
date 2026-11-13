-- =============================================================================
-- 02_load_data.sql  |  Bulk-load the six source CSVs with psql's \copy
-- -----------------------------------------------------------------------------
-- \copy reads files on the *client* machine, so no server-side file access is
-- needed. Paths below are relative to this repository's root; run psql from
-- the project root, e.g.:
--
--     psql -U postgres -d maven_fuzzy_factory -f sql/02_load_data.sql
--
-- (scripts/load_to_postgres.py performs the exact same load programmatically
--  and is the recommended cross-platform path.)
--
-- Load order respects foreign keys: products & website_sessions first.
-- =============================================================================

TRUNCATE TABLE order_item_refunds, order_items, orders,
               website_pageviews, website_sessions, products
    RESTART IDENTITY CASCADE;

\copy products          FROM 'maven-fuzzy-factory/products.csv'          WITH (FORMAT csv, HEADER true, NULL 'NULL')
\copy website_sessions  FROM 'maven-fuzzy-factory/website_sessions.csv'  WITH (FORMAT csv, HEADER true, NULL 'NULL')
\copy website_pageviews FROM 'maven-fuzzy-factory/website_pageviews.csv' WITH (FORMAT csv, HEADER true, NULL 'NULL')
\copy orders            FROM 'maven-fuzzy-factory/orders.csv'            WITH (FORMAT csv, HEADER true, NULL 'NULL')
\copy order_items       FROM 'maven-fuzzy-factory/order_items.csv'       WITH (FORMAT csv, HEADER true, NULL 'NULL')
\copy order_item_refunds FROM 'maven-fuzzy-factory/order_item_refunds.csv' WITH (FORMAT csv, HEADER true, NULL 'NULL')

-- Row-count sanity check (expected: 4 / 472871 / 1188124 / 32313 / 40025 / 1731)
SELECT 'products'          AS table_name, COUNT(*) FROM products
UNION ALL SELECT 'website_sessions',   COUNT(*) FROM website_sessions
UNION ALL SELECT 'website_pageviews',  COUNT(*) FROM website_pageviews
UNION ALL SELECT 'orders',             COUNT(*) FROM orders
UNION ALL SELECT 'order_items',        COUNT(*) FROM order_items
UNION ALL SELECT 'order_item_refunds', COUNT(*) FROM order_item_refunds;
