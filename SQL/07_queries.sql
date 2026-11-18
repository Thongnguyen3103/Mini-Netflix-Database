/*
 * Mini-Netflix database: advanced queries for the report (section 4.2).
 * Read-only. Run after 06_seed_sample_data.sql; results depend on
 * CURRENT_DATE because the sample data is dated relative to it.
 *
 * Techniques used:
 *   Q01 multi-table JOIN, COUNT DISTINCT, GROUP BY, LIMIT
 *   Q02 aggregate with CASE, date_trunc, GROUP BY two keys
 *   Q03 NOT EXISTS (anti-join) on a view
 *   Q04 window function ROW_NUMBER, CTE
 *   Q05 correlated subquery, LEFT JOIN
 *   Q06 window function RANK over an aggregate
 *   Q07 HAVING, ratio with FILTER
 *   Q08 derived table, AVG over a grouped count
 *   Q09 scalar subqueries, JOIN with GROUP BY
 *   Q10 window function LAG over subscriptions
 *   Q11 NOT EXISTS against watch history through two subclasses
 *   Q12 IN subquery, BETWEEN
 *   Q13 CASE buckets on EXTRACT(HOUR)
 *   Q14 COUNT DISTINCT, derived table, HAVING with a computed threshold
 */


/* Q01. Top 10 titles by distinct viewers in the last 30 days. */
SELECT t.title_id,
       t.title_name,
       t.title_type,
       COUNT(DISTINCT (wh.user_id, wh.profile_num)) AS viewer_tally,
       COUNT(*)                                       AS session_tally
  FROM watch_history AS wh
       LEFT JOIN movies AS m
       ON m.content_id = wh.content_id

       LEFT JOIN episodes AS e
       ON e.content_id = wh.content_id

       INNER JOIN titles AS t
       ON t.title_id = COALESCE(m.title_id, e.title_id)
 WHERE wh.started_at >= CURRENT_DATE - 30
 GROUP BY t.title_id,
          t.title_name,
          t.title_type
 ORDER BY viewer_tally DESC,
          session_tally DESC,
          t.title_name
 LIMIT 10;


/* Q02. Net revenue per month and plan: successful payments minus refunds. */
SELECT date_trunc('month', pm.paid_at)::DATE AS revenue_month,
       pl.plan_name,
       SUM(CASE pm.payment_status
               WHEN 'SUCCESS'  THEN pm.amount
               WHEN 'REFUNDED' THEN -pm.amount
               ELSE 0
           END)                                AS net_revenue_total,
       COUNT(*) FILTER (WHERE pm.payment_status = 'FAILED') AS failed_tally
  FROM payments AS pm
       INNER JOIN subscriptions AS s
       ON s.subscription_id = pm.subscription_id

       INNER JOIN plans AS pl
       ON pl.plan_id = s.plan_id
 GROUP BY revenue_month,
          pl.plan_name
 ORDER BY revenue_month,
          pl.plan_name;


/* Q03. Paying users with no viewing in the last 14 days (churn risk). */
SELECT cs.user_id,
       cs.username,
       cs.plan_name,
       cs.end_date
  FROM current_subscriptions AS cs
 WHERE NOT EXISTS (
           SELECT 1
             FROM watch_history AS wh
            WHERE wh.user_id = cs.user_id
              AND wh.started_at >= CURRENT_DATE - 14
       )
 ORDER BY cs.end_date;


/* Q04. "Continue watching": latest unfinished video of every profile. */
WITH ranked_sessions AS (
    SELECT wp.user_id,
           wp.profile_num,
           wp.content_id,
           wp.last_watched_at,
           wp.progress_percent,
           ROW_NUMBER() OVER (
               PARTITION BY wp.user_id, wp.profile_num
               ORDER BY wp.last_watched_at DESC
           ) AS recency_num
      FROM watch_progress AS wp
     WHERE NOT wp.is_finished
)
SELECT p.user_id,
       p.profile_name,
       cc.title_name,
       cc.season_num,
       cc.episode_num,
       rs.progress_percent,
       rs.last_watched_at
  FROM ranked_sessions AS rs
       INNER JOIN profiles AS p
       ON p.user_id = rs.user_id
      AND p.profile_num = rs.profile_num

       INNER JOIN content_catalog AS cc
       ON cc.content_id = rs.content_id
 WHERE rs.recency_num = 1
 ORDER BY rs.last_watched_at DESC;


/* Q05. Next episode to watch for each profile and series it has started. */
SELECT p.user_id,
       p.profile_name,
       t.title_name,
       nxt.season_num,
       nxt.episode_num
  FROM (
           SELECT DISTINCT wh.user_id,
                  wh.profile_num,
                  e.title_id
             FROM watch_history AS wh
                  INNER JOIN episodes AS e
                  ON e.content_id = wh.content_id
       ) AS started
       INNER JOIN profiles AS p
       ON p.user_id = started.user_id
      AND p.profile_num = started.profile_num

       INNER JOIN titles AS t
       ON t.title_id = started.title_id

       LEFT JOIN episodes AS nxt
       ON nxt.title_id = started.title_id
      AND (nxt.season_num, nxt.episode_num) = (
              /* First episode after the furthest one this profile has watched. */
              SELECT e2.season_num,
                     e2.episode_num
                FROM episodes AS e2
               WHERE e2.title_id = started.title_id
                 AND (e2.season_num, e2.episode_num) > (
                         SELECT e3.season_num,
                                e3.episode_num
                           FROM watch_history AS wh3
                                INNER JOIN episodes AS e3
                                ON e3.content_id = wh3.content_id
                          WHERE wh3.user_id = started.user_id
                            AND wh3.profile_num = started.profile_num
                            AND e3.title_id = started.title_id
                          ORDER BY e3.season_num DESC,
                                   e3.episode_num DESC
                          LIMIT 1
                     )
               ORDER BY e2.season_num,
                        e2.episode_num
               LIMIT 1
          )
 ORDER BY p.user_id,
          p.profile_name,
          t.title_name;


/* Q06. Favourite genre of each profile (ties share rank 1). */
WITH genre_views AS (
    SELECT wh.user_id,
           wh.profile_num,
           g.genre_name,
           COUNT(*) AS session_tally
      FROM watch_history AS wh
           INNER JOIN content_catalog AS cc
           ON cc.content_id = wh.content_id

           INNER JOIN title_genres AS tg
           ON tg.title_id = cc.title_id

           INNER JOIN genres AS g
           ON g.genre_id = tg.genre_id
     GROUP BY wh.user_id,
              wh.profile_num,
              g.genre_name
),
ranked_genres AS (
    SELECT gv.*,
           RANK() OVER (
               PARTITION BY gv.user_id, gv.profile_num
               ORDER BY gv.session_tally DESC
           ) AS genre_rank
      FROM genre_views AS gv
)
SELECT p.user_id,
       p.profile_name,
       rg.genre_name,
       rg.session_tally
  FROM ranked_genres AS rg
       INNER JOIN profiles AS p
       ON p.user_id = rg.user_id
      AND p.profile_num = rg.profile_num
 WHERE rg.genre_rank = 1
 ORDER BY p.user_id,
          p.profile_num,
          rg.genre_name;


/* Q07. Completion rate per title, for titles with at least 5 sessions. */
SELECT cc.title_name,
       COUNT(*)                                              AS session_tally,
       COUNT(*) FILTER (WHERE wp.is_finished)                AS finished_tally,
       ROUND(100.0 * COUNT(*) FILTER (WHERE wp.is_finished) / COUNT(*), 1) AS completion_percent
  FROM watch_progress AS wp
       INNER JOIN content_catalog AS cc
       ON cc.content_id = wp.content_id
 GROUP BY cc.title_name
HAVING COUNT(*) >= 5
 ORDER BY completion_percent DESC,
          session_tally DESC;


/* Q08. Plan usage: subscribers, average profiles used and share of slots filled. */
SELECT cs.plan_name,
       cs.max_profiles,
       COUNT(*)                              AS subscriber_tally,
       ROUND(AVG(pc.profile_tally), 2)       AS avg_profile_tally,
       ROUND(100.0 * SUM(pc.profile_tally) / SUM(cs.max_profiles), 1) AS slot_used_percent
  FROM current_subscriptions AS cs
       INNER JOIN (
           SELECT user_id,
                  COUNT(*) AS profile_tally
             FROM profiles
            GROUP BY user_id
       ) AS pc
       ON pc.user_id = cs.user_id
 GROUP BY cs.plan_name,
          cs.max_profiles
 ORDER BY cs.max_profiles;


/* Q09. Actors in the most titles, with the total sessions of those titles. */
SELECT pe.full_name,
       COUNT(*) AS title_tally,
       SUM((
           SELECT COUNT(*)
             FROM watch_history AS wh
                  INNER JOIN content_catalog AS cc
                  ON cc.content_id = wh.content_id
            WHERE cc.title_id = tc.title_id
       ))       AS session_total
  FROM title_credits AS tc
       INNER JOIN people AS pe
       ON pe.person_id = tc.person_id
 WHERE tc.credit_role = 'ACTOR'
 GROUP BY pe.person_id,
          pe.full_name
HAVING COUNT(*) >= (
           SELECT MAX(actor_titles.title_tally) - 1
             FROM (
                      SELECT COUNT(*) AS title_tally
                        FROM title_credits
                       WHERE credit_role = 'ACTOR'
                       GROUP BY person_id
                  ) AS actor_titles
       )
 ORDER BY title_tally DESC,
          session_total DESC;


/* Q10. Users who changed plan at renewal, and whether it was an upgrade. */
WITH plan_history AS (
    SELECT s.user_id,
           s.start_date,
           pl.plan_name,
           pl.monthly_price,
           LAG(pl.plan_name)     OVER w AS previous_plan_name,
           LAG(pl.monthly_price) OVER w AS previous_price
      FROM subscriptions AS s
           INNER JOIN plans AS pl
           ON pl.plan_id = s.plan_id
     WHERE s.subscription_status <> 'CANCELLED'
    WINDOW w AS (PARTITION BY s.user_id ORDER BY s.start_date)
)
SELECT ph.user_id,
       ph.start_date AS changed_on,
       ph.previous_plan_name,
       ph.plan_name,
       CASE
           WHEN ph.monthly_price > ph.previous_price THEN 'UPGRADE'
           ELSE 'DOWNGRADE'
       END AS change_type
  FROM plan_history AS ph
 WHERE ph.previous_plan_name IS NOT NULL
   AND ph.previous_plan_name <> ph.plan_name
 ORDER BY ph.start_date;


/* Q11. Watchlist titles a profile has saved but never started. */
SELECT p.user_id,
       p.profile_name,
       t.title_name,
       wi.added_at
  FROM watchlist_items AS wi
       INNER JOIN profiles AS p
       ON p.user_id = wi.user_id
      AND p.profile_num = wi.profile_num

       INNER JOIN titles AS t
       ON t.title_id = wi.title_id
 WHERE NOT EXISTS (
           SELECT 1
             FROM watch_history AS wh
                  LEFT JOIN movies AS m
                  ON m.content_id = wh.content_id

                  LEFT JOIN episodes AS e
                  ON e.content_id = wh.content_id
            WHERE wh.user_id = wi.user_id
              AND wh.profile_num = wi.profile_num
              AND COALESCE(m.title_id, e.title_id) = wi.title_id
       )
 ORDER BY wi.added_at DESC
 LIMIT 20;


/* Q12. Renewal reminders: subscriptions ending in the next 30 days, with contact email. */
SELECT u.user_id,
       u.username,
       u.email,
       cs.plan_name,
       cs.end_date,
       cs.end_date - CURRENT_DATE AS days_left_num
  FROM users AS u
       INNER JOIN current_subscriptions AS cs
       ON cs.user_id = u.user_id
 WHERE cs.end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30
   AND u.user_id IN (
           SELECT user_id
             FROM payments AS pm
                  INNER JOIN subscriptions AS s
                  ON s.subscription_id = pm.subscription_id
            WHERE pm.payment_status = 'SUCCESS'
       )
 ORDER BY cs.end_date;


/* Q13. Viewing sessions by time of day, split by kids and adult profiles. */
SELECT CASE
           WHEN EXTRACT(HOUR FROM wh.started_at) BETWEEN 5 AND 11  THEN '1. Sáng'
           WHEN EXTRACT(HOUR FROM wh.started_at) BETWEEN 12 AND 17 THEN '2. Chiều'
           WHEN EXTRACT(HOUR FROM wh.started_at) BETWEEN 18 AND 21 THEN '3. Tối'
           ELSE '4. Khuya'
       END                                              AS time_slot_name,
       COUNT(*) FILTER (WHERE p.is_kids)                AS kids_session_tally,
       COUNT(*) FILTER (WHERE NOT p.is_kids)            AS adult_session_tally,
       ROUND(AVG(wh.position_seconds) / 60.0, 1)        AS avg_minutes_watched
  FROM watch_history AS wh
       INNER JOIN profiles AS p
       ON p.user_id = wh.user_id
      AND p.profile_num = wh.profile_num
 GROUP BY time_slot_name
 ORDER BY time_slot_name;


/*
 * Q14. Series progress: profiles that have opened at least 30% of a
 * series' episodes, compared with the series' total episode count.
 */
SELECT p.user_id,
       p.profile_name,
       t.title_name,
       COUNT(DISTINCT wh.content_id) AS watched_episode_tally,
       ep.episode_tally,
       ROUND(100.0 * COUNT(DISTINCT wh.content_id) / ep.episode_tally, 1) AS progress_percent
  FROM watch_history AS wh
       INNER JOIN episodes AS e
       ON e.content_id = wh.content_id

       INNER JOIN titles AS t
       ON t.title_id = e.title_id

       INNER JOIN profiles AS p
       ON p.user_id = wh.user_id
      AND p.profile_num = wh.profile_num

       INNER JOIN (
           SELECT title_id,
                  COUNT(*) AS episode_tally
             FROM episodes
            GROUP BY title_id
       ) AS ep
       ON ep.title_id = e.title_id
 GROUP BY p.user_id,
          p.profile_name,
          t.title_name,
          ep.episode_tally
HAVING COUNT(DISTINCT wh.content_id) >= 0.3 * ep.episode_tally
 ORDER BY progress_percent DESC,
          p.user_id;
