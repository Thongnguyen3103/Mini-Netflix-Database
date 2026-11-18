/*
 * Mini-Netflix database: RBAC tests for 08_roles.sql (report section 5.2).
 * Run as a superuser on a database loaded with 01-06 and 08. Every action
 * runs inside a rolled-back subtransaction, so the data is left unchanged.
 * Each line prints PASS when the outcome matches the expectation.
 */

\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

CREATE FUNCTION pg_temp.check_access(role_name TEXT, label TEXT, stmt TEXT, should_succeed BOOLEAN)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    outcome TEXT;
BEGIN
    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', role_name);
        EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
        EXECUTE stmt;
        EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
        outcome := 'allowed';
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'rollback test action';
    EXCEPTION
        WHEN insufficient_privilege THEN
            outcome := 'denied';
        WHEN raise_exception THEN
            IF outcome IS NULL THEN
                outcome := 'error: ' || SQLERRM;
            END IF;
        WHEN OTHERS THEN
            outcome := 'error: ' || SQLERRM;
    END;
    RESET ROLE;

    RETURN CASE
               WHEN (outcome = 'allowed') = should_succeed
                AND outcome IN ('allowed', 'denied') THEN 'PASS  '
               ELSE 'FAIL  '
           END
           || rpad(role_name, 18) || rpad(label, 52) || outcome;
END;
$$;

BEGIN;

/* netflix_app: the web backend */
SELECT pg_temp.check_access('netflix_app', 'read the catalogue view',
       $q$SELECT COUNT(*) FROM content_catalog$q$, TRUE);
SELECT pg_temp.check_access('netflix_app', 'sign up a new user',
       $q$INSERT INTO users (user_id, username, email, password_hash) VALUES ('U009999', 'test_rbac', 'rbac@example.com', 'x')$q$, TRUE);
SELECT pg_temp.check_access('netflix_app', 'change own email',
       $q$UPDATE users SET email = 'new.mail@example.com' WHERE user_id = 'U000006'$q$, TRUE);
SELECT pg_temp.check_access('netflix_app', 'promote a user to admin',
       $q$UPDATE users SET account_type_code = 'ADM' WHERE user_id = 'U000006'$q$, FALSE);
SELECT pg_temp.check_access('netflix_app', 'delete a user',
       $q$DELETE FROM users WHERE user_id = 'U000030'$q$, FALSE);
SELECT pg_temp.check_access('netflix_app', 'create a profile (trigger reads plans)',
       $q$INSERT INTO profiles (user_id, profile_num, profile_name)
          SELECT cs.user_id, 9, 'RBAC test'
            FROM current_subscriptions AS cs
           WHERE cs.max_profiles = 4
             AND (SELECT COUNT(*) FROM profiles AS p WHERE p.user_id = cs.user_id) < 4
           LIMIT 1$q$, TRUE);
SELECT pg_temp.check_access('netflix_app', 'record a viewing session',
       $q$INSERT INTO watch_history (user_id, profile_num, content_id, started_at, position_seconds)
          SELECT p.user_id, p.profile_num, 2, CURRENT_TIMESTAMP, 60
            FROM profiles AS p
                 INNER JOIN current_subscriptions AS cs
                 ON cs.user_id = p.user_id
           WHERE NOT p.is_kids
           LIMIT 1$q$, TRUE);
SELECT pg_temp.check_access('netflix_app', 'update viewing position',
       $q$UPDATE watch_history SET position_seconds = 0 WHERE user_id = 'U000006'$q$, TRUE);
SELECT pg_temp.check_access('netflix_app', 'rewrite which content was watched',
       $q$UPDATE watch_history SET content_id = 1 WHERE user_id = 'U000006'$q$, FALSE);
SELECT pg_temp.check_access('netflix_app', 'delete viewing history',
       $q$DELETE FROM watch_history WHERE user_id = 'U000006'$q$, FALSE);
SELECT pg_temp.check_access('netflix_app', 'record a payment',
       $q$INSERT INTO payments (subscription_id, amount, payment_method, payment_status) VALUES (1, 69000, 'VNPay', 'SUCCESS')$q$, TRUE);
SELECT pg_temp.check_access('netflix_app', 'change a payment amount',
       $q$UPDATE payments SET amount = 0 WHERE payment_id = 1$q$, FALSE);
SELECT pg_temp.check_access('netflix_app', 'add a title to the catalogue',
       $q$INSERT INTO titles (title_type, title_name) VALUES ('SR', 'Nope')$q$, FALSE);
SELECT pg_temp.check_access('netflix_app', 'change a plan price',
       $q$UPDATE plans SET monthly_price = 0$q$, FALSE);

/* netflix_moderator: catalogue management */
SELECT pg_temp.check_access('netflix_moderator', 'add a series with a season',
       $q$WITH t AS (INSERT INTO titles (title_type, title_name, age_rating) VALUES ('SR', 'Phim thử', 0) RETURNING title_id),
               s AS (INSERT INTO series (title_id) SELECT title_id FROM t RETURNING title_id)
          INSERT INTO seasons (title_id, season_num) SELECT title_id, 1 FROM s$q$, TRUE);
SELECT pg_temp.check_access('netflix_moderator', 'edit a title description',
       $q$UPDATE titles SET description = 'Mô tả mới' WHERE title_id = 1$q$, TRUE);
SELECT pg_temp.check_access('netflix_moderator', 'read viewing statistics view',
       $q$SELECT COUNT(*) FROM watch_progress$q$, TRUE);
SELECT pg_temp.check_access('netflix_moderator', 'read user emails',
       $q$SELECT email FROM users$q$, FALSE);
SELECT pg_temp.check_access('netflix_moderator', 'read payments',
       $q$SELECT * FROM payments$q$, FALSE);

/* netflix_analyst: read-only reporting */
SELECT pg_temp.check_access('netflix_analyst', 'read watch history',
       $q$SELECT COUNT(*) FROM watch_history$q$, TRUE);
SELECT pg_temp.check_access('netflix_analyst', 'read non-personal user columns',
       $q$SELECT user_id, username, gender FROM users$q$, TRUE);
SELECT pg_temp.check_access('netflix_analyst', 'read user emails',
       $q$SELECT email FROM users$q$, FALSE);
SELECT pg_temp.check_access('netflix_analyst', 'read password hashes',
       $q$SELECT password_hash FROM users$q$, FALSE);
SELECT pg_temp.check_access('netflix_analyst', 'modify any data',
       $q$UPDATE titles SET age_rating = 0$q$, FALSE);

/* netflix_admin */
SELECT pg_temp.check_access('netflix_admin', 'delete a payment',
       $q$DELETE FROM payments WHERE payment_id = 1$q$, TRUE);
SELECT pg_temp.check_access('netflix_admin', 'change a plan price',
       $q$UPDATE plans SET monthly_price = 79000 WHERE plan_id = 1$q$, TRUE);

/* Login roles inherit from their group */
SELECT pg_temp.check_access('webapp_login', 'login role inherits app read access',
       $q$SELECT COUNT(*) FROM titles$q$, TRUE);
SELECT pg_temp.check_access('analyst_login', 'login role inherits analyst limits',
       $q$SELECT email FROM users$q$, FALSE);

ROLLBACK;
