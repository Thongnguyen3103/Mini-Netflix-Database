CREATE FUNCTION check_profile_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    plan_limit    SMALLINT;
    profile_tally INTEGER;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.user_id = OLD.user_id THEN
        RETURN NEW;
    END IF;

    /* Serialize concurrent inserts for the same user so both cannot pass. */
    PERFORM 1
       FROM users
      WHERE user_id = NEW.user_id
        FOR UPDATE;

    SELECT p.max_profiles
      INTO plan_limit
      FROM subscriptions AS s
           INNER JOIN plans AS p
           ON p.plan_id = s.plan_id
     WHERE s.user_id = NEW.user_id
       AND s.subscription_status = 'ACTIVE'
       AND CURRENT_DATE >= s.start_date
       AND CURRENT_DATE < s.end_date;

    IF plan_limit IS NULL THEN
        RAISE EXCEPTION 'User % has no active subscription', NEW.user_id
              USING ERRCODE = 'check_violation';
    END IF;

    SELECT COUNT(*)
      INTO profile_tally
      FROM profiles
     WHERE user_id = NEW.user_id;

    IF profile_tally >= plan_limit THEN
        RAISE EXCEPTION 'User % already has the maximum of % profiles',
                        NEW.user_id, plan_limit
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_enforce_limit
BEFORE INSERT OR UPDATE OF user_id ON profiles
FOR EACH ROW
EXECUTE FUNCTION check_profile_limit();


/* ---------- Rules: viewing needs a valid subscription and suitable age rating ---------- */

CREATE FUNCTION check_watch_access()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    /* Highest age rating a kids profile may watch. */
    kids_max_age_rating CONSTANT SMALLINT := 12;
    profile_is_kids     BOOLEAN;
    content_age_rating  SMALLINT;
BEGIN
    SELECT is_kids
      INTO profile_is_kids
      FROM profiles
     WHERE user_id = NEW.user_id
       AND profile_num = NEW.profile_num;

    /* Let the foreign key report a profile that does not exist. */
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    /* Compares with started_at, so past sessions of expired plans stay valid. */
    IF NOT EXISTS (
        SELECT 1
          FROM subscriptions
         WHERE user_id = NEW.user_id
           AND subscription_status <> 'CANCELLED'
           AND NEW.started_at::DATE >= start_date
           AND NEW.started_at::DATE < end_date
    ) THEN
        RAISE EXCEPTION 'User % has no valid subscription on %',
                        NEW.user_id, NEW.started_at::DATE
              USING ERRCODE = 'check_violation';
    END IF;

    IF profile_is_kids THEN
        SELECT t.age_rating
          INTO content_age_rating
          FROM titles AS t
         WHERE t.title_id = COALESCE(
                   (SELECT m.title_id FROM movies AS m WHERE m.content_id = NEW.content_id),
                   (SELECT e.title_id FROM episodes AS e WHERE e.content_id = NEW.content_id)
               );

        IF content_age_rating > kids_max_age_rating THEN
            RAISE EXCEPTION 'Content % is rated % and not allowed on a kids profile',
                            NEW.content_id, content_age_rating
                  USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER watch_history_enforce_access
BEFORE INSERT OR UPDATE OF user_id, profile_num, content_id, started_at ON watch_history
FOR EACH ROW
EXECUTE FUNCTION check_watch_access();


/* ---------- Rule: viewing position cannot pass the end of the video ---------- */

CREATE FUNCTION check_watch_position()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    content_duration INTEGER;
BEGIN
    SELECT duration_seconds
      INTO content_duration
      FROM contents
     WHERE content_id = NEW.content_id;

    IF NEW.position_seconds > content_duration THEN
        RAISE EXCEPTION 'Position % exceeds the % second duration of content %',
                        NEW.position_seconds, content_duration, NEW.content_id
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER watch_history_enforce_position
BEFORE INSERT OR UPDATE OF content_id, position_seconds ON watch_history
FOR EACH ROW
EXECUTE FUNCTION check_watch_position();


/*
 * ---------- Rule: total specialization ----------
 * Every contents row needs a subclass row, and so does every titles row.
 * Checks are deferred to COMMIT because parent and subclass rows are inserted
 * in one transaction. Disjointness is already enforced by the composite
 * foreign keys and the CHECK constraints on the type columns.
 */

CREATE FUNCTION check_content_has_subclass()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    checked_id   BIGINT;
    checked_type CHAR(2);
BEGIN
    IF TG_TABLE_NAME = 'contents' THEN
        checked_id := NEW.content_id;
    ELSE
        checked_id := OLD.content_id;
    END IF;

    SELECT content_type
      INTO checked_type
      FROM contents
     WHERE content_id = checked_id;

    /* The parent was deleted as well, so nothing is left incomplete. */
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF (checked_type = 'MV'
        AND NOT EXISTS (SELECT 1 FROM movies WHERE content_id = checked_id))
    OR (checked_type = 'EP'
        AND NOT EXISTS (SELECT 1 FROM episodes WHERE content_id = checked_id))
    THEN
        RAISE EXCEPTION 'Content % of type % has no subclass row',
                        checked_id, checked_type
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER contents_require_subclass
AFTER INSERT ON contents
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION check_content_has_subclass();

CREATE CONSTRAINT TRIGGER movies_keep_content_subclass
AFTER DELETE OR UPDATE OF content_id ON movies
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION check_content_has_subclass();

CREATE CONSTRAINT TRIGGER episodes_keep_content_subclass
AFTER DELETE OR UPDATE OF content_id ON episodes
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION check_content_has_subclass();


CREATE FUNCTION check_title_has_subclass()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    checked_id   INTEGER;
    checked_type CHAR(2);
BEGIN
    IF TG_TABLE_NAME = 'titles' THEN
        checked_id := NEW.title_id;
    ELSE
        checked_id := OLD.title_id;
    END IF;

    SELECT title_type
      INTO checked_type
      FROM titles
     WHERE title_id = checked_id;

    /* The parent was deleted as well, so nothing is left incomplete. */
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF (checked_type = 'MV'
        AND NOT EXISTS (SELECT 1 FROM movies WHERE title_id = checked_id))
    OR (checked_type = 'SR'
        AND NOT EXISTS (SELECT 1 FROM series WHERE title_id = checked_id))
    THEN
        RAISE EXCEPTION 'Title % of type % has no subclass row',
                        checked_id, checked_type
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER titles_require_subclass
AFTER INSERT ON titles
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION check_title_has_subclass();

CREATE CONSTRAINT TRIGGER movies_keep_title_subclass
AFTER DELETE OR UPDATE OF title_id ON movies
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION check_title_has_subclass();

CREATE CONSTRAINT TRIGGER series_keep_title_subclass
AFTER DELETE OR UPDATE OF title_id ON series
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION check_title_has_subclass();


/*
 * ---------- Rule: a movie's release date falls in its title's release year ----------
 * A movie stores titles.release_year and contents.release_date. When both are
 * set, the year of release_date must equal release_year. Deferred to COMMIT so
 * both values can be changed in one transaction.
 */

CREATE FUNCTION check_movie_release_year()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    checked_title_id   INTEGER;
    checked_content_id BIGINT;
    mismatch           RECORD;
BEGIN
    /* Read only the key the firing table has; the other stays NULL. */
    IF TG_TABLE_NAME = 'titles' THEN
        checked_title_id := NEW.title_id;
    ELSE
        checked_content_id := NEW.content_id;
    END IF;

    SELECT m.content_id,
           t.release_year,
           c.release_date
      INTO mismatch
      FROM movies AS m
           INNER JOIN titles AS t
           ON t.title_id = m.title_id

           INNER JOIN contents AS c
           ON c.content_id = m.content_id
     WHERE (m.title_id = checked_title_id
            OR m.content_id = checked_content_id)
       AND t.release_year <> EXTRACT(YEAR FROM c.release_date);

    IF FOUND THEN
        RAISE EXCEPTION 'Movie % has release date % outside its release year %',
                        mismatch.content_id, mismatch.release_date, mismatch.release_year
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER movies_check_release_year
AFTER INSERT OR UPDATE ON movies
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION check_movie_release_year();

CREATE CONSTRAINT TRIGGER titles_check_movie_release_year
AFTER UPDATE OF release_year ON titles
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION check_movie_release_year();

CREATE CONSTRAINT TRIGGER contents_check_movie_release_year
AFTER UPDATE OF release_date ON contents
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION check_movie_release_year();
