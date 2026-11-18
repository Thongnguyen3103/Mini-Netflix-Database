/*
 * Mini-Netflix database: role-based access control (report section 5.2).
 * Run as a superuser, after 01-04. Roles are cluster-wide, so the script
 * creates each role only if it does not exist yet and can be re-run.
 *
 * Group roles (NOLOGIN) hold the privileges:
 *   netflix_admin      full control of every table
 *   netflix_moderator  manages the catalogue; reads viewing statistics
 *   netflix_app        the web backend: accounts, profiles, viewing, payments
 *   netflix_analyst    read-only reporting, without contact or password data
 *
 * Login roles (one per person or service) only inherit from a group role.
 * They are created without a password; set one with \password <role_name>.
 */

/* ---------- Group and login roles ---------- */

DO $$
DECLARE
    role_name TEXT;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['netflix_admin', 'netflix_moderator', 'netflix_app', 'netflix_analyst']
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', role_name);
        END IF;
    END LOOP;
END;
$$;

DO $$
DECLARE
    login_role RECORD;
BEGIN
    FOR login_role IN
        SELECT *
          FROM (VALUES ('admin_login',     'netflix_admin'),
                       ('moderator_login', 'netflix_moderator'),
                       ('webapp_login',    'netflix_app'),
                       ('analyst_login',   'netflix_analyst')) AS v (login_name, group_name)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = login_role.login_name) THEN
            EXECUTE format('CREATE ROLE %I LOGIN IN ROLE %I', login_role.login_name, login_role.group_name);
        END IF;
    END LOOP;
END;
$$;


/* ---------- Start from no privileges ---------- */

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT USAGE
   ON SCHEMA public
   TO netflix_admin, netflix_moderator, netflix_app, netflix_analyst;


/* ---------- netflix_admin ---------- */

GRANT ALL PRIVILEGES
   ON ALL TABLES IN SCHEMA public
   TO netflix_admin;


/* ---------- netflix_moderator: catalogue management ---------- */

GRANT SELECT, INSERT, UPDATE, DELETE
   ON titles, series, seasons, contents, movies, episodes,
      genres, title_genres, people, title_credits
   TO netflix_moderator;

GRANT SELECT
   ON content_catalog, watch_progress
   TO netflix_moderator;


/* ---------- netflix_app: the web backend ---------- */

GRANT SELECT
   ON account_types, plans,
      titles, series, seasons, contents, movies, episodes,
      genres, title_genres, people, title_credits,
      content_catalog, current_subscriptions, watch_progress
   TO netflix_app;

/* Accounts: sign-up and profile edits, but never deletion or role changes. */
GRANT SELECT, INSERT
   ON users
   TO netflix_app;

GRANT UPDATE (username, email, password_hash, gender)
   ON users
   TO netflix_app;

GRANT SELECT, INSERT, UPDATE, DELETE
   ON profiles, watchlist_items
   TO netflix_app;

/* Billing history is append-only for the application. */
GRANT SELECT, INSERT
   ON subscriptions, payments
   TO netflix_app;

GRANT UPDATE (subscription_status)
   ON subscriptions
   TO netflix_app;

/* Viewing: a session can be extended, never rewritten or deleted. */
GRANT SELECT, INSERT
   ON watch_history
   TO netflix_app;

GRANT UPDATE (ended_at, position_seconds)
   ON watch_history
   TO netflix_app;


/* ---------- netflix_analyst: read-only reporting ---------- */

GRANT SELECT
   ON ALL TABLES IN SCHEMA public
   TO netflix_analyst;

/* No contact details or password hashes: keep only the non-personal columns. */
REVOKE SELECT
    ON users
  FROM netflix_analyst;

GRANT SELECT (user_id, username, gender, account_type_code, created_at)
   ON users
   TO netflix_analyst;


/*
 * ---------- Trigger functions run with the owner's rights ----------
 * The business-rule triggers read tables the caller may not see (for
 * example profiles_enforce_limit locks users and reads plans). SECURITY
 * DEFINER lets them check the rule without granting those tables to every
 * role; the fixed search_path stops a caller from substituting objects.
 */

ALTER FUNCTION check_profile_limit()        SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION check_watch_access()         SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION check_watch_position()       SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION check_content_has_subclass() SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION check_title_has_subclass()   SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION check_movie_release_year()   SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE
    ON FUNCTION check_profile_limit(), check_watch_access(), check_watch_position(),
                check_content_has_subclass(), check_title_has_subclass(), check_movie_release_year()
  FROM PUBLIC;
