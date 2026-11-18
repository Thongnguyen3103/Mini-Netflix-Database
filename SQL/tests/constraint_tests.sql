/*
 * Mini-Netflix database: integrity tests (report section 5.1).
 * Shows that constraints and triggers accept valid data and reject invalid
 * data. Run as a superuser on a database loaded with 01-06. Everything runs
 * in one transaction that is rolled back, so the data is left unchanged.
 * Each line prints PASS when the outcome matches the expectation.
 */

\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

BEGIN;

/* ---------- Fixture: own rows, independent of the sample data ---------- */

CREATE TEMP TABLE fx (
    plan_id       SMALLINT,
    movie_title   INTEGER,
    movie_content BIGINT,
    series_title  INTEGER,
    ep1_content   BIGINT
) ON COMMIT DROP;

INSERT INTO plans (plan_name, monthly_price, max_profiles, video_quality)
VALUES ('TEST 2 hồ sơ', 50000, 2, 'HD');

INSERT INTO users (user_id, username, email, password_hash, account_type_code)
VALUES ('T000001', 'test_an',   'test.an@example.com',   'x', 'USR'),
       ('T000002', 'test_binh', 'test.binh@example.com', 'x', 'USR');

INSERT INTO subscriptions (user_id, plan_id, start_date, end_date, subscription_status)
SELECT 'T000001', plan_id, CURRENT_DATE - 30, CURRENT_DATE + 30, 'ACTIVE'
  FROM plans
 WHERE plan_name = 'TEST 2 hồ sơ';

INSERT INTO profiles (user_id, profile_num, profile_name, is_kids)
VALUES ('T000001', 1, 'Người lớn', FALSE),
       ('T000001', 2, 'Trẻ em',    TRUE);

INSERT INTO titles (title_type, title_name, release_year, age_rating)
VALUES ('MV', 'TEST Phim 18+', 2024, 18),
       ('SR', 'TEST Phim bộ',  2024, 0);
INSERT INTO contents (content_type, duration_seconds, video_url, release_date)
VALUES ('MV', 6000, 'test-movie', DATE '2024-03-01'),
       ('EP', 1500, 'test-ep1',   DATE '2024-05-01');

INSERT INTO fx
SELECT (SELECT plan_id FROM plans WHERE plan_name = 'TEST 2 hồ sơ'),
       (SELECT title_id FROM titles WHERE title_name = 'TEST Phim 18+'),
       (SELECT content_id FROM contents WHERE video_url = 'test-movie'),
       (SELECT title_id FROM titles WHERE title_name = 'TEST Phim bộ'),
       (SELECT content_id FROM contents WHERE video_url = 'test-ep1');

INSERT INTO movies (content_id, title_id)
SELECT movie_content, movie_title FROM fx;
INSERT INTO series (title_id)
SELECT series_title FROM fx;
INSERT INTO seasons (title_id, season_num)
SELECT series_title, 1 FROM fx;
INSERT INTO episodes (content_id, title_id, season_num, episode_num)
SELECT ep1_content, series_title, 1, 1 FROM fx;

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO watch_history (user_id, profile_num, content_id, started_at, position_seconds)
SELECT 'T000001', 2, ep1_content, CURRENT_TIMESTAMP - INTERVAL '1 hour', 100 FROM fx;

SELECT 'OK    fixture loaded: 1 plan, 2 users, 2 profiles, 1 movie, 1 series with 1 episode';


/* ---------- Test harness ---------- */

CREATE FUNCTION pg_temp.expect(label TEXT, stmt TEXT, should_fail BOOLEAN)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
    BEGIN
        /* Deferred checks run at the end, like a real COMMIT. */
        EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
        EXECUTE stmt;
        EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '__accepted__';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = '__accepted__' THEN
                RETURN CASE WHEN should_fail THEN 'FAIL  ' ELSE 'PASS  ' END
                       || rpad(label, 50) || 'accepted';
            END IF;
            RETURN CASE WHEN should_fail THEN 'PASS  ' ELSE 'FAIL  ' END
                   || rpad(label, 50) || 'rejected [' || SQLSTATE || '] ' || SQLERRM;
    END;
END;
$$;


/* ---------- Domain and CHECK constraints ---------- */

SELECT pg_temp.expect('email without @',
       $q$INSERT INTO users (user_id, username, email, password_hash) VALUES ('T000009', 'z', 'no-at-sign', 'x')$q$, TRUE);
SELECT pg_temp.expect('duplicate username',
       $q$INSERT INTO users (user_id, username, email, password_hash) VALUES ('T000009', 'test_an', 'other@example.com', 'x')$q$, TRUE);
SELECT pg_temp.expect('negative plan price',
       $q$INSERT INTO plans (plan_name, monthly_price, max_profiles, video_quality) VALUES ('Bad', -1, 1, 'HD')$q$, TRUE);
SELECT pg_temp.expect('negative payment amount',
       $q$INSERT INTO payments (subscription_id, amount, payment_method, payment_status)
          SELECT subscription_id, -5, 'VNPay', 'SUCCESS' FROM subscriptions WHERE user_id = 'T000001'$q$, TRUE);
SELECT pg_temp.expect('unknown payment status',
       $q$INSERT INTO payments (subscription_id, amount, payment_method, payment_status)
          SELECT subscription_id, 5, 'VNPay', 'PENDING' FROM subscriptions WHERE user_id = 'T000001'$q$, TRUE);
SELECT pg_temp.expect('non-positive duration',
       $q$INSERT INTO contents (content_type, duration_seconds, video_url) VALUES ('EP', 0, 'x')$q$, TRUE);
SELECT pg_temp.expect('watch ended before it started',
       $q$INSERT INTO watch_history (user_id, profile_num, content_id, started_at, ended_at)
          SELECT 'T000001', 1, ep1_content, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP - INTERVAL '1 hour' FROM fx$q$, TRUE);

/* ---------- Subscriptions ---------- */

SELECT pg_temp.expect('subscription ends before it starts',
       $q$INSERT INTO subscriptions (user_id, plan_id, start_date, end_date, subscription_status)
          SELECT 'T000002', plan_id, CURRENT_DATE, CURRENT_DATE - 1, 'ACTIVE' FROM fx$q$, TRUE);
SELECT pg_temp.expect('overlapping subscription',
       $q$INSERT INTO subscriptions (user_id, plan_id, start_date, end_date, subscription_status)
          SELECT 'T000001', plan_id, CURRENT_DATE, CURRENT_DATE + 10, 'ACTIVE' FROM fx$q$, TRUE);
SELECT pg_temp.expect('overlapping but cancelled subscription',
       $q$INSERT INTO subscriptions (user_id, plan_id, start_date, end_date, subscription_status)
          SELECT 'T000001', plan_id, CURRENT_DATE, CURRENT_DATE + 10, 'CANCELLED' FROM fx$q$, FALSE);
SELECT pg_temp.expect('subscription right after the current one',
       $q$INSERT INTO subscriptions (user_id, plan_id, start_date, end_date, subscription_status)
          SELECT 'T000001', plan_id, CURRENT_DATE + 30, CURRENT_DATE + 60, 'ACTIVE' FROM fx$q$, FALSE);

/* ---------- Profiles ---------- */

SELECT pg_temp.expect('third profile on a 2-profile plan',
       $q$INSERT INTO profiles (user_id, profile_num, profile_name) VALUES ('T000001', 3, 'Thứ ba')$q$, TRUE);
SELECT pg_temp.expect('profile without an active subscription',
       $q$INSERT INTO profiles (user_id, profile_num, profile_name) VALUES ('T000002', 1, 'Bình')$q$, TRUE);
SELECT pg_temp.expect('duplicate profile name in one account',
       $q$UPDATE profiles SET profile_name = 'Trẻ em' WHERE user_id = 'T000001' AND profile_num = 1$q$, TRUE);

/* ---------- EER specialization: disjoint and total ---------- */

SELECT pg_temp.expect('content without a subclass row',
       $q$INSERT INTO contents (content_type, duration_seconds, video_url) VALUES ('MV', 10, 'orphan')$q$, TRUE);
SELECT pg_temp.expect('title without a subclass row',
       $q$INSERT INTO titles (title_type, title_name) VALUES ('SR', 'Orphan')$q$, TRUE);
SELECT pg_temp.expect('delete only the movie subclass row',
       $q$DELETE FROM movies WHERE content_id = (SELECT movie_content FROM fx)$q$, TRUE);
SELECT pg_temp.expect('movie content reused as an episode',
       $q$INSERT INTO episodes (content_id, title_id, season_num, episode_num)
          SELECT movie_content, series_title, 1, 2 FROM fx$q$, TRUE);
SELECT pg_temp.expect('episode content reused as a movie',
       $q$WITH t AS (INSERT INTO titles (title_type, title_name) VALUES ('MV', 'TEST Chưa có video') RETURNING title_id)
          INSERT INTO movies (content_id, title_id) SELECT fx.ep1_content, t.title_id FROM fx, t$q$, TRUE);
SELECT pg_temp.expect('series row on a movie title',
       $q$INSERT INTO series (title_id) SELECT movie_title FROM fx$q$, TRUE);
SELECT pg_temp.expect('change type of a content with a subclass',
       $q$UPDATE contents SET content_type = 'EP' WHERE content_id = (SELECT movie_content FROM fx)$q$, TRUE);
SELECT pg_temp.expect('duplicate episode number in a season',
       $q$WITH c AS (INSERT INTO contents (content_type, duration_seconds, video_url) VALUES ('EP', 10, 'dup') RETURNING content_id)
          INSERT INTO episodes (content_id, title_id, season_num, episode_num)
          SELECT c.content_id, fx.series_title, 1, 1 FROM c, fx$q$, TRUE);
SELECT pg_temp.expect('complete new movie in one transaction',
       $q$WITH t AS (INSERT INTO titles (title_type, title_name, release_year) VALUES ('MV', 'TEST Mới', 2025) RETURNING title_id),
               c AS (INSERT INTO contents (content_type, duration_seconds, video_url, release_date) VALUES ('MV', 10, 'new', DATE '2025-01-01') RETURNING content_id)
          INSERT INTO movies (content_id, title_id) SELECT c.content_id, t.title_id FROM t, c$q$, FALSE);
SELECT pg_temp.expect('delete a whole movie (content, then title)',
       $q$DELETE FROM contents WHERE content_id = (SELECT movie_content FROM fx);
          DELETE FROM titles WHERE title_id = (SELECT movie_title FROM fx)$q$, FALSE);

/* ---------- Movie release year ---------- */

SELECT pg_temp.expect('movie release date outside its year',
       $q$UPDATE contents SET release_date = DATE '2020-01-01' WHERE content_id = (SELECT movie_content FROM fx)$q$, TRUE);
SELECT pg_temp.expect('change movie year and date together',
       $q$UPDATE titles SET release_year = 2020 WHERE title_id = (SELECT movie_title FROM fx);
          UPDATE contents SET release_date = DATE '2020-01-01' WHERE content_id = (SELECT movie_content FROM fx)$q$, FALSE);

/* ---------- Watch history ---------- */

SELECT pg_temp.expect('position beyond the video length',
       $q$INSERT INTO watch_history (user_id, profile_num, content_id, started_at, position_seconds)
          SELECT 'T000001', 1, ep1_content, CURRENT_TIMESTAMP, 99999 FROM fx$q$, TRUE);
SELECT pg_temp.expect('kids profile watching an 18+ movie',
       $q$INSERT INTO watch_history (user_id, profile_num, content_id, started_at)
          SELECT 'T000001', 2, movie_content, CURRENT_TIMESTAMP FROM fx$q$, TRUE);
SELECT pg_temp.expect('adult profile watching an 18+ movie',
       $q$INSERT INTO watch_history (user_id, profile_num, content_id, started_at)
          SELECT 'T000001', 1, movie_content, CURRENT_TIMESTAMP FROM fx$q$, FALSE);
SELECT pg_temp.expect('watching outside the subscription dates',
       $q$INSERT INTO watch_history (user_id, profile_num, content_id, started_at)
          SELECT 'T000001', 1, ep1_content, CURRENT_TIMESTAMP - INTERVAL '1 year' FROM fx$q$, TRUE);
SELECT pg_temp.expect('delete a content that has viewing history',
       $q$DELETE FROM contents WHERE content_id = (SELECT ep1_content FROM fx)$q$, TRUE);
SELECT pg_temp.expect('delete a user who has subscriptions',
       $q$DELETE FROM users WHERE user_id = 'T000001'$q$, TRUE);

ROLLBACK;
