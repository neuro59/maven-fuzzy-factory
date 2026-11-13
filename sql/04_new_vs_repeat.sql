-- =============================================================================
-- 04_new_vs_repeat.sql  |  BUSINESS QUESTION 2:
--   "Do first-time vs. repeat visitors convert differently by channel?"
-- -----------------------------------------------------------------------------
-- is_repeat_session = 1 when the user had a previous session, so this is a
-- session-level new-vs-returning comparison within each acquisition channel.
-- =============================================================================

-- 4.1  Conversion by channel x visitor type ---------------------------------
SELECT
    s.channel,
    CASE s.is_repeat_session WHEN 1 THEN 'Repeat' ELSE 'First-time' END AS visitor_type,
    COUNT(*)                                                       AS sessions,
    COUNT(o.order_id)                                              AS orders,
    ROUND(100.0 * COUNT(o.order_id) / COUNT(*), 2)                 AS session_cvr_pct,
    ROUND(COALESCE(SUM(o.price_usd), 0), 2)                        AS gross_revenue_usd,
    ROUND(COALESCE(AVG(o.price_usd), 0), 2)                        AS aov_usd
FROM v_session_channel s
LEFT JOIN v_order_revenue o USING (website_session_id)
GROUP BY s.channel, visitor_type
ORDER BY s.channel, visitor_type;

-- 4.2  Side-by-side lift table (conditional aggregation) ---------------------
--      repeat_cvr_pct - first_time_cvr_pct = absolute conversion lift.
SELECT
    s.channel,
    COUNT(*) FILTER (WHERE s.is_repeat_session = 0)                AS first_time_sessions,
    COUNT(*) FILTER (WHERE s.is_repeat_session = 1)                AS repeat_sessions,
    ROUND(100.0 * COUNT(*) FILTER (WHERE s.is_repeat_session = 0 AND o.order_id IS NOT NULL)
          / NULLIF(COUNT(*) FILTER (WHERE s.is_repeat_session = 0), 0), 2) AS first_time_cvr_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE s.is_repeat_session = 1 AND o.order_id IS NOT NULL)
          / NULLIF(COUNT(*) FILTER (WHERE s.is_repeat_session = 1), 0), 2) AS repeat_cvr_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE s.is_repeat_session = 1 AND o.order_id IS NOT NULL)
              / NULLIF(COUNT(*) FILTER (WHERE s.is_repeat_session = 1), 0)
      - 100.0 * COUNT(*) FILTER (WHERE s.is_repeat_session = 0 AND o.order_id IS NOT NULL)
              / NULLIF(COUNT(*) FILTER (WHERE s.is_repeat_session = 0), 0), 2) AS cvr_lift_pp,
    ROUND(100.0 * COUNT(*) FILTER (WHERE s.is_repeat_session = 1)
          / COUNT(*), 1)                                           AS repeat_session_mix_pct
FROM v_session_channel s
LEFT JOIN v_order_revenue o USING (website_session_id)
GROUP BY s.channel
ORDER BY repeat_sessions DESC;

-- 4.3  Where does the repeat value sit? Revenue per session by type ---------
SELECT
    s.channel,
    CASE s.is_repeat_session WHEN 1 THEN 'Repeat' ELSE 'First-time' END AS visitor_type,
    ROUND(COALESCE(SUM(o.price_usd), 0) / COUNT(*), 4)             AS revenue_per_session_usd,
    ROUND(COALESCE(SUM(o.net_revenue_usd), 0) / COUNT(*), 4)       AS net_revenue_per_session_usd
FROM v_session_channel s
LEFT JOIN v_order_revenue o USING (website_session_id)
GROUP BY s.channel, visitor_type
ORDER BY s.channel, visitor_type;

-- 4.4  Are repeat *users* actually the same people re-converting? -----------
--      Orders per user, split by whether the ordering session was a repeat.
SELECT
    CASE s.is_repeat_session WHEN 1 THEN 'Repeat' ELSE 'First-time' END AS visitor_type,
    COUNT(DISTINCT s.user_id)                                      AS users,
    COUNT(*)                                                       AS sessions,
    ROUND(COUNT(*)::numeric / COUNT(DISTINCT s.user_id), 2)       AS sessions_per_user
FROM v_session_channel s
GROUP BY visitor_type
ORDER BY visitor_type;
