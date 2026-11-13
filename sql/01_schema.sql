-- =============================================================================
-- 01_schema.sql  |  Maven Fuzzy Factory (fictional online toy retailer)
-- -----------------------------------------------------------------------------
-- Drops and recreates the reporting schema in dependency order, then adds
-- join indexes and two convenience views used by the analysis scripts.
--
-- Run order:  01_schema.sql -> 02_load_data.sql -> 03/04/05 analysis scripts
-- =============================================================================

DROP TABLE IF EXISTS order_item_refunds CASCADE;
DROP TABLE IF EXISTS order_items       CASCADE;
DROP TABLE IF EXISTS orders            CASCADE;
DROP TABLE IF EXISTS website_pageviews CASCADE;
DROP TABLE IF EXISTS website_sessions  CASCADE;
DROP TABLE IF EXISTS products          CASCADE;

-- ---------------------------------------------------------------------------
-- Dimension / fact tables (mirrors maven_fuzzy_factory_data_dictionary.csv)
-- ---------------------------------------------------------------------------
CREATE TABLE products (
    product_id    SMALLINT     PRIMARY KEY,
    created_at    TIMESTAMP    NOT NULL,
    product_name  TEXT         NOT NULL
);

CREATE TABLE website_sessions (
    website_session_id  INTEGER   PRIMARY KEY,
    created_at          TIMESTAMP NOT NULL,
    user_id             INTEGER   NOT NULL,
    is_repeat_session   SMALLINT  NOT NULL CHECK (is_repeat_session IN (0, 1)),
    utm_source          TEXT,
    utm_campaign        TEXT,
    utm_content         TEXT,
    device_type         TEXT,
    http_referer        TEXT
);

CREATE TABLE website_pageviews (
    website_pageview_id  INTEGER   PRIMARY KEY,
    created_at           TIMESTAMP NOT NULL,
    website_session_id   INTEGER   NOT NULL REFERENCES website_sessions (website_session_id),
    pageview_url         TEXT      NOT NULL
);

CREATE TABLE orders (
    order_id            INTEGER       PRIMARY KEY,
    created_at          TIMESTAMP     NOT NULL,
    website_session_id  INTEGER       NOT NULL REFERENCES website_sessions (website_session_id),
    user_id             INTEGER       NOT NULL,
    primary_product_id  SMALLINT      REFERENCES products (product_id),
    items_purchased     SMALLINT      NOT NULL,
    price_usd           NUMERIC(10,2) NOT NULL,
    cogs_usd            NUMERIC(10,2) NOT NULL
);

CREATE TABLE order_items (
    order_item_id    INTEGER       PRIMARY KEY,
    created_at       TIMESTAMP     NOT NULL,
    order_id         INTEGER       NOT NULL REFERENCES orders (order_id),
    product_id       SMALLINT      NOT NULL REFERENCES products (product_id),
    is_primary_item  SMALLINT      NOT NULL CHECK (is_primary_item IN (0, 1)),
    price_usd        NUMERIC(10,2) NOT NULL,
    cogs_usd         NUMERIC(10,2) NOT NULL
);

CREATE TABLE order_item_refunds (
    order_item_refund_id  INTEGER       PRIMARY KEY,
    created_at            TIMESTAMP     NOT NULL,
    order_item_id         INTEGER       NOT NULL REFERENCES order_items (order_item_id),
    order_id              INTEGER       NOT NULL REFERENCES orders (order_id),
    refund_amount_usd     NUMERIC(10,2) NOT NULL
);

-- ---------------------------------------------------------------------------
-- Indexes for the join key paths exercised by the analysis queries
-- ---------------------------------------------------------------------------
CREATE INDEX idx_sessions_user          ON website_sessions (user_id);
CREATE INDEX idx_sessions_utm_source    ON website_sessions (utm_source);
CREATE INDEX idx_pageviews_session      ON website_pageviews (website_session_id);
CREATE INDEX idx_orders_session         ON orders (website_session_id);
CREATE INDEX idx_order_items_order      ON order_items (order_id);
CREATE INDEX idx_refunds_order          ON order_item_refunds (order_id);
CREATE INDEX idx_refunds_order_item     ON order_item_refunds (order_item_id);

-- ---------------------------------------------------------------------------
-- Views: one canonical session-level channel label and one order-level
-- revenue table (net of refunds). Keeps every downstream query consistent.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_session_channel AS
SELECT
    website_session_id,
    created_at,
    user_id,
    is_repeat_session,
    device_type,
    utm_source,
    utm_campaign,
    utm_content,
    CASE utm_source
        WHEN 'gsearch'    THEN 'Google Search'
        WHEN 'bsearch'    THEN 'Bing Search'
        WHEN 'socialbook' THEN 'SocialBook'
        ELSE 'Direct / Untagged'           -- NULL utm_source = untagged/direct traffic
    END AS channel
FROM website_sessions;

CREATE OR REPLACE VIEW v_order_revenue AS
SELECT
    o.order_id,
    o.created_at,
    o.website_session_id,
    o.user_id,
    o.price_usd,
    o.cogs_usd,
    o.price_usd - o.cogs_usd                       AS gross_margin_usd,
    COALESCE(r.refund_amount_usd, 0)               AS refund_amount_usd,
    o.price_usd - COALESCE(r.refund_amount_usd, 0) AS net_revenue_usd
FROM orders o
LEFT JOIN (
    SELECT order_id, SUM(refund_amount_usd) AS refund_amount_usd
    FROM order_item_refunds
    GROUP BY order_id
) r ON r.order_id = o.order_id;
