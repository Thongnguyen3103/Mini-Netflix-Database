/*
 * Mini-Netflix database: performance tests (report section 4.2).
 * Run as a superuser on a TEST copy loaded with 01-06: the script adds about
 * 50 000 movies and 300 000 viewing sessions, and drops indexes temporarily,
 * which locks the tables while it runs. Everything is rolled back at the end.
 *
 * Each case runs the same query with and without the index under test and
 * prints the plan with its execution time. Timings depend on the machine.
 */

\set ON_ERROR_STOP on
\timing off

BEGIN;

SELECT setseed(0.42);


/* ---------- Bulk data ---------- */

/* 50 000 movies: title + content + movie row each. */
INSERT INTO titles (title_type, title_name, description, release_year, age_rating)
SELECT 'MV',
       'Phim thử nghiệm ' || n || ' ' || (ARRAY['mùa thu', 'thành phố', 'dòng sông', 'ngọn núi', 'biển xanh'])[1 + n % 5],
       'Dữ liệu sinh tự động cho test hiệu năng.',
       2000 + n % 25,
       (ARRAY[0, 13, 16, 18])[1 + n % 4]
  FROM generate_series(1, 50000) AS n;

INSERT INTO contents (content_type, duration_seconds, video_url, release_date)
SELECT 'MV',
       5400 + n % 3000,
       'perf-' || n,
       make_date(2000 + n % 25, 1 + n % 12, 1 + n % 28)
  FROM generate_series(1, 50000) AS n;

INSERT INTO movies (content_id, title_id)
SELECT c.content_id,
       t.title_id
  FROM contents AS c
       INNER JOIN titles AS t
       ON split_part(t.title_name, ' ', 4) = substring(c.video_url FROM 6)
 WHERE c.video_url LIKE 'perf-%'
   AND t.title_name LIKE 'Phim thử nghiệm %';

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

/* 12 000 sessions per adult profile with an active plan, inside its plan dates. */
INSERT INTO watch_history (user_id, profile_num, content_id, started_at, ended_at, position_seconds)
SELECT p.user_id,
       p.profile_num,
       1 + n % 125,
       cs.start_date + (n * 37 % ((CURRENT_DATE - cs.start_date) * 86400)) * INTERVAL '1 second',
       NULL,
       0
  FROM profiles AS p
       INNER JOIN current_subscriptions AS cs
       ON cs.user_id = p.user_id

       CROSS JOIN generate_series(1, 12000) AS n
 WHERE NOT p.is_kids;

ANALYZE titles;
ANALYZE contents;
ANALYZE movies;
ANALYZE watch_history;

SELECT 'titles=' || (SELECT COUNT(*) FROM titles)
       || ' contents=' || (SELECT COUNT(*) FROM contents)
       || ' watch_history=' || (SELECT COUNT(*) FROM watch_history) AS data_volume;


/* ---------- P1. Title search by keyword (NFR: under 200 ms) ---------- */

\echo '=== P1 with titles_name_trgm_idx'
SELECT COUNT(*) FROM titles WHERE title_name ILIKE '%tinh%';
EXPLAIN (ANALYZE, COSTS OFF)
SELECT title_id, title_name
  FROM titles
 WHERE title_name ILIKE '%tinh%';

SAVEPOINT no_trgm;
DROP INDEX titles_name_trgm_idx;
\echo '=== P1 without titles_name_trgm_idx'
SELECT COUNT(*) FROM titles WHERE title_name ILIKE '%tinh%';
EXPLAIN (ANALYZE, COSTS OFF)
SELECT title_id, title_name
  FROM titles
 WHERE title_name ILIKE '%tinh%';
ROLLBACK TO SAVEPOINT no_trgm;


/* ---------- P2. Sessions of one content (popularity statistics) ---------- */

\echo '=== P2 with watch_history_content_idx'
SELECT COUNT(*) FROM watch_history WHERE content_id = 42;
EXPLAIN (ANALYZE, COSTS OFF)
SELECT COUNT(*)
  FROM watch_history
 WHERE content_id = 42;

SAVEPOINT no_content_idx;
DROP INDEX watch_history_content_idx;
\echo '=== P2 without watch_history_content_idx'
SELECT COUNT(*) FROM watch_history WHERE content_id = 42;
EXPLAIN (ANALYZE, COSTS OFF)
SELECT COUNT(*)
  FROM watch_history
 WHERE content_id = 42;
ROLLBACK TO SAVEPOINT no_content_idx;


/* ---------- P3. "Continue watching": latest 20 sessions of one profile ---------- */

\echo '=== P3 with watch_history_recent_idx'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT content_id, started_at, position_seconds
  FROM watch_history
 WHERE user_id = 'U000003'
   AND profile_num = 1
 ORDER BY started_at DESC
 LIMIT 20;

SAVEPOINT no_recent_idx;
DROP INDEX watch_history_recent_idx;
\echo '=== P3 without watch_history_recent_idx (primary key index only)'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT content_id, started_at, position_seconds
  FROM watch_history
 WHERE user_id = 'U000003'
   AND profile_num = 1
 ORDER BY started_at DESC
 LIMIT 20;
ROLLBACK TO SAVEPOINT no_recent_idx;

ROLLBACK;
