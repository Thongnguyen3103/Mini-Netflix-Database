CREATE VIEW content_catalog AS
SELECT c.content_id,
       c.content_type,
       t.title_id,
       t.title_name,
       e.season_num,
       e.episode_num,
       e.episode_name,
       c.duration_seconds,
       c.video_url,
       t.age_rating
  FROM contents AS c
       LEFT JOIN movies AS m
       ON m.content_id = c.content_id

       LEFT JOIN episodes AS e
       ON e.content_id = c.content_id

       INNER JOIN titles AS t
       ON t.title_id = COALESCE(m.title_id, e.title_id);


/* The subscription each user holds today. */
CREATE VIEW current_subscriptions AS
SELECT s.subscription_id,
       s.user_id,
       u.username,
       p.plan_id,
       p.plan_name,
       p.max_profiles,
       p.video_quality,
       s.start_date,
       s.end_date
  FROM subscriptions AS s
       INNER JOIN users AS u
       ON u.user_id = s.user_id

       INNER JOIN plans AS p
       ON p.plan_id = s.plan_id
 WHERE s.subscription_status = 'ACTIVE'
   AND CURRENT_DATE >= s.start_date
   AND CURRENT_DATE < s.end_date;


/*
 * Latest session per profile and content. A video counts as finished from
 * 90% watched; this is derived here rather than stored in watch_history.
 */
CREATE VIEW watch_progress AS
SELECT DISTINCT ON (w.user_id, w.profile_num, w.content_id)
       w.user_id,
       w.profile_num,
       w.content_id,
       w.started_at AS last_watched_at,
       w.position_seconds,
       c.duration_seconds,
       ROUND(100.0 * w.position_seconds / c.duration_seconds, 1) AS progress_percent,
       w.position_seconds >= 0.9 * c.duration_seconds AS is_finished
  FROM watch_history AS w
       INNER JOIN contents AS c
       ON c.content_id = w.content_id
 ORDER BY w.user_id,
          w.profile_num,
          w.content_id,
          w.started_at DESC;
