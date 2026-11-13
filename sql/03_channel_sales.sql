-- =============================================================================
-- 03_channel_sales.sql  |  BUSINESS QUESTION 1: "Which channels drive sales?"
-- -----------------------------------------------------------------------------
-- Channel = utm_source, with NULL (untagged/direct) folded into one bucket.
-- Grain: one row per channel. Every session is the denominator for conversion;
-- revenue is attributed to the channel of the session that produced the order.
-- =============================================================================

-- 3.1  Headline channel scorecard -------------------------------------------
SELECT
    s.channel,
    COUNT(*)                                                       AS sessions,
    COUNT(o.order_id)                                              AS orders,
    ROUND(100.0 * COUNT(o.order_id) / COUNT(*), 2)                 AS session_cvr_pct,
    ROUND(COALESCE(SUM(o.price_usd), 0), 2)                        AS gross_revenue_usd,
    ROUND(COALESCE(SUM(o.net_revenue_usd), 0), 2)                  AS net_revenue_usd,
    ROUND(COALESCE(SUM(o.gross_margin_usd), 0), 2)                 AS gross_margin_usd,
    ROUND(COALESCE(SUM(o.price_usd), 0) / NULLIF(COUNT(o.order_id), 0), 2) AS aov_usd,
    ROUND(COALESCE(SUM(o.price_usd), 0) / COUNT(*), 4)             AS revenue_per_session_usd,
    ROUND(100.0 * COALESCE(SUM(o.price_usd), 0)
          / SUM(COALESCE(SUM(o.price_usd), 0)) OVER (), 1)         AS revenue_share_pct
FROM v_session_channel s
LEFT JOIN v_order_revenue o USING (website_session_id)
GROUP BY s.channel
ORDER BY gross_revenue_usd DESC;

-- 3.2  Same scorecard, but splitting paid traffic into brand vs non-brand ----
--      (utm_campaign) to see whether the channel effect is really a campaign
--      effect.
SELECT
    s.channel,
    COALESCE(s.utm_campaign, '(untagged)')                         AS utm_campaign,
    COUNT(*)                                                       AS sessions,
    COUNT(o.order_id)                                              AS orders,
    ROUND(100.0 * COUNT(o.order_id) / COUNT(*), 2)                 AS session_cvr_pct,
    ROUND(COALESCE(SUM(o.price_usd), 0), 2)                        AS gross_revenue_usd,
    ROUND(COALESCE(SUM(o.price_usd), 0) / NULLIF(COUNT(o.order_id), 0), 2) AS aov_usd
FROM v_session_channel s
LEFT JOIN v_order_revenue o USING (website_session_id)
GROUP BY s.channel, COALESCE(s.utm_campaign, '(untagged)')
ORDER BY gross_revenue_usd DESC;

-- 3.3  Ad/content-level detail for the single largest channel (Google Search)
SELECT
    s.utm_content,
    COUNT(*)                                                       AS sessions,
    COUNT(o.order_id)                                              AS orders,
    ROUND(100.0 * COUNT(o.order_id) / COUNT(*), 2)                 AS session_cvr_pct,
    ROUND(COALESCE(SUM(o.price_usd), 0), 2)                        AS gross_revenue_usd
FROM v_session_channel s
LEFT JOIN v_order_revenue o USING (website_session_id)
WHERE s.utm_source = 'gsearch'
GROUP BY s.utm_content
ORDER BY gross_revenue_usd DESC;
