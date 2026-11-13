-- =============================================================================
-- 05_extended_analytics.sql  |  Supporting analyses beyond the two core
-- questions: conversion funnel, device, monthly trend, refunds, products.
-- =============================================================================

-- 5.1  Session-level conversion funnel --------------------------------------
--      Classify each pageview, then count distinct sessions that reached
--      each stage. The final "thank you" stage reconciles to orders.
WITH pageview_steps AS (
    SELECT
        website_session_id,
        CASE
            WHEN pageview_url = '/home' OR pageview_url LIKE '/lander-%' THEN '1. Lander / Home'
            WHEN pageview_url = '/products' OR pageview_url LIKE '/the-%' THEN '2. Product page'
            WHEN pageview_url = '/cart'                                   THEN '3. Cart'
            WHEN pageview_url = '/shipping'                               THEN '4. Shipping'
            WHEN pageview_url LIKE '/billing%'                            THEN '5. Billing'
            WHEN pageview_url = '/thank-you-for-your-order'               THEN '6. Thank you'
        END AS funnel_step
    FROM website_pageviews
)
SELECT
    funnel_step,
    COUNT(DISTINCT website_session_id)                                  AS sessions,
    ROUND(100.0 * COUNT(DISTINCT website_session_id)
          / (SELECT COUNT(*) FROM website_sessions), 2)                 AS pct_of_all_sessions
FROM pageview_steps
WHERE funnel_step IS NOT NULL
GROUP BY funnel_step
ORDER BY funnel_step;

-- 5.2  Funnel by channel ----------------------------------------------------
WITH pageview_steps AS (
    SELECT
        website_session_id,
        CASE
            WHEN pageview_url = '/products' OR pageview_url LIKE '/the-%' THEN '2. Product page'
            WHEN pageview_url = '/cart'                                   THEN '3. Cart'
            WHEN pageview_url = '/shipping'                               THEN '4. Shipping'
            WHEN pageview_url LIKE '/billing%'                            THEN '5. Billing'
            WHEN pageview_url = '/thank-you-for-your-order'               THEN '6. Thank you'
        END AS funnel_step
    FROM website_pageviews
)
SELECT
    s.channel,
    COUNT(DISTINCT s.website_session_id)                                AS sessions,
    COUNT(DISTINCT CASE WHEN p.funnel_step = '2. Product page' THEN p.website_session_id END) AS reached_product,
    COUNT(DISTINCT CASE WHEN p.funnel_step = '3. Cart'         THEN p.website_session_id END) AS reached_cart,
    COUNT(DISTINCT CASE WHEN p.funnel_step = '4. Shipping'     THEN p.website_session_id END) AS reached_shipping,
    COUNT(DISTINCT CASE WHEN p.funnel_step = '5. Billing'      THEN p.website_session_id END) AS reached_billing,
    COUNT(DISTINCT CASE WHEN p.funnel_step = '6. Thank you'    THEN p.website_session_id END) AS purchased
FROM v_session_channel s
LEFT JOIN pageview_steps p USING (website_session_id)
GROUP BY s.channel
ORDER BY sessions DESC;

-- 5.3  Device performance ---------------------------------------------------
SELECT
    s.device_type,
    COUNT(*)                                                            AS sessions,
    COUNT(o.order_id)                                                   AS orders,
    ROUND(100.0 * COUNT(o.order_id) / COUNT(*), 2)                      AS session_cvr_pct,
    ROUND(COALESCE(SUM(o.price_usd), 0), 2)                             AS gross_revenue_usd,
    ROUND(100.0 * COALESCE(SUM(o.price_usd), 0)
          / SUM(COALESCE(SUM(o.price_usd), 0)) OVER (), 1)              AS revenue_share_pct
FROM v_session_channel s
LEFT JOIN v_order_revenue o USING (website_session_id)
GROUP BY s.device_type
ORDER BY gross_revenue_usd DESC;

-- 5.4  Device x channel -----------------------------------------------------
SELECT
    s.channel,
    s.device_type,
    COUNT(*)                                                            AS sessions,
    COUNT(o.order_id)                                                   AS orders,
    ROUND(100.0 * COUNT(o.order_id) / COUNT(*), 2)                      AS session_cvr_pct
FROM v_session_channel s
LEFT JOIN v_order_revenue o USING (website_session_id)
GROUP BY s.channel, s.device_type
ORDER BY s.channel, s.device_type;

-- 5.5  Monthly trend --------------------------------------------------------
WITH months AS (
    SELECT
        DATE_TRUNC('month', s.created_at) AS month,
        COUNT(*)                          AS sessions
    FROM v_session_channel s
    GROUP BY 1
),
order_months AS (
    SELECT
        DATE_TRUNC('month', o.created_at) AS month,
        COUNT(*)                          AS orders,
        SUM(o.price_usd)                  AS gross_revenue_usd,
        SUM(o.net_revenue_usd)            AS net_revenue_usd
    FROM v_order_revenue o
    GROUP BY 1
)
SELECT
    m.month,
    m.sessions,
    COALESCE(om.orders, 0)                                              AS orders,
    ROUND(100.0 * COALESCE(om.orders, 0) / m.sessions, 2)               AS session_cvr_pct,
    ROUND(COALESCE(om.gross_revenue_usd, 0), 2)                         AS gross_revenue_usd,
    ROUND(COALESCE(om.net_revenue_usd, 0), 2)                           AS net_revenue_usd
FROM months m
LEFT JOIN order_months om USING (month)
ORDER BY m.month;

-- 5.6  Refunds by channel ---------------------------------------------------
SELECT
    s.channel,
    COUNT(DISTINCT o.order_id)                                          AS orders,
    ROUND(SUM(o.refund_amount_usd), 2)                                  AS refunds_usd,
    ROUND(100.0 * SUM(o.refund_amount_usd)
          / NULLIF(SUM(o.price_usd), 0), 2)                             AS refund_rate_pct
FROM v_session_channel s
JOIN v_order_revenue o USING (website_session_id)
GROUP BY s.channel
ORDER BY refunds_usd DESC;

-- 5.7  Product performance --------------------------------------------------
SELECT
    p.product_name,
    COUNT(*)                                                            AS units_sold,
    ROUND(SUM(oi.price_usd), 2)                                         AS gross_revenue_usd,
    ROUND(SUM(oi.price_usd - oi.cogs_usd), 2)                           AS gross_margin_usd,
    ROUND(100.0 * SUM(oi.price_usd)
          / (SELECT SUM(price_usd) FROM order_items), 1)                AS revenue_share_pct
FROM order_items oi
JOIN products p USING (product_id)
GROUP BY p.product_name
ORDER BY gross_revenue_usd DESC;
