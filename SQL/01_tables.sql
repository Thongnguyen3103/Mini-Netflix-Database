CREATE EXTENSION IF NOT EXISTS btree_gist;


/* ---------- Accounts and profiles ---------- */

CREATE TABLE account_types (
    PRIMARY KEY (account_type_code),
    account_type_code CHAR(3)      NOT NULL,
    account_type_name VARCHAR(50)  NOT NULL UNIQUE,
    description       VARCHAR(255),
    is_active         BOOLEAN      DEFAULT TRUE              NOT NULL,
    created_at        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE users (
    PRIMARY KEY (user_id),
    user_id           CHAR(7)      NOT NULL,
    username          VARCHAR(50)  NOT NULL UNIQUE,
    email             VARCHAR(100) NOT NULL UNIQUE,
                      CONSTRAINT email_format
                      CHECK (email LIKE '%_@_%'),
    password_hash     VARCHAR(255) NOT NULL,
    gender            VARCHAR(10),
    account_type_code CHAR(3)      DEFAULT 'USR'             NOT NULL,
    created_at        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL,

    FOREIGN KEY (account_type_code)
        REFERENCES account_types (account_type_code)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

/* Weak entity of users. */
CREATE TABLE profiles (
    PRIMARY KEY (user_id, profile_num),
    user_id      CHAR(7)     NOT NULL,
    profile_num  SMALLINT    NOT NULL,
                 CONSTRAINT profile_num_positive
                 CHECK (profile_num > 0),
    profile_name VARCHAR(50) NOT NULL,
    is_kids      BOOLEAN     DEFAULT FALSE NOT NULL,

    UNIQUE (user_id, profile_name),
    FOREIGN KEY (user_id)
        REFERENCES users (user_id)
        ON DELETE CASCADE
);


/* ---------- Plans and payments ---------- */

CREATE TABLE plans (
    PRIMARY KEY (plan_id),
    plan_id       SMALLINT      GENERATED ALWAYS AS IDENTITY,
    plan_name     VARCHAR(50)   NOT NULL UNIQUE,
    monthly_price NUMERIC(10,0) NOT NULL,   /* VND */
                  CONSTRAINT monthly_price_not_negative
                  CHECK (monthly_price >= 0),
    max_profiles  SMALLINT      NOT NULL,
                  CONSTRAINT max_profiles_positive
                  CHECK (max_profiles > 0),
    video_quality VARCHAR(10)   NOT NULL,   /* HD, FHD, 4K */
    is_active     BOOLEAN       DEFAULT TRUE NOT NULL
);

CREATE TABLE subscriptions (
    PRIMARY KEY (subscription_id),
    subscription_id     BIGINT      GENERATED ALWAYS AS IDENTITY,
    user_id             CHAR(7)     NOT NULL,
    plan_id             SMALLINT    NOT NULL,
    start_date          DATE        NOT NULL,
    end_date            DATE        NOT NULL,
    subscription_status VARCHAR(10) NOT NULL,
                        CONSTRAINT subscription_status_value
                        CHECK (subscription_status IN ('ACTIVE', 'EXPIRED', 'CANCELLED')),

    FOREIGN KEY (user_id)
        REFERENCES users (user_id)
        ON DELETE RESTRICT,
    FOREIGN KEY (plan_id)
        REFERENCES plans (plan_id)
        ON DELETE RESTRICT,

    CONSTRAINT subscription_date_order
    CHECK (end_date > start_date),

    /* A user cannot hold two subscriptions for the same day. */
    CONSTRAINT subscription_no_overlap
    EXCLUDE USING gist (
        user_id                        WITH =,
        daterange(start_date, end_date) WITH &&
    )
    WHERE (subscription_status <> 'CANCELLED')
);

CREATE TABLE payments (
    PRIMARY KEY (payment_id),
    payment_id      BIGINT        GENERATED ALWAYS AS IDENTITY,
    subscription_id BIGINT        NOT NULL,
    amount          NUMERIC(10,0) NOT NULL,   /* Price actually paid, in VND. */
                    CONSTRAINT amount_not_negative
                    CHECK (amount >= 0),
    payment_method  VARCHAR(20)   NOT NULL,
    paid_at         TIMESTAMP     DEFAULT CURRENT_TIMESTAMP NOT NULL,
    payment_status  VARCHAR(10)   NOT NULL,
                    CONSTRAINT payment_status_value
                    CHECK (payment_status IN ('SUCCESS', 'FAILED', 'REFUNDED')),

    FOREIGN KEY (subscription_id)
        REFERENCES subscriptions (subscription_id)
        ON DELETE RESTRICT
);


/* ---------- Titles: EER specialization into movies and series (disjoint, total) ---------- */

CREATE TABLE titles (
    PRIMARY KEY (title_id),
    title_id     INTEGER      GENERATED ALWAYS AS IDENTITY,
    title_type   CHAR(2)      NOT NULL,
                 CONSTRAINT title_type_value
                 CHECK (title_type IN ('MV', 'SR')),
    title_name   VARCHAR(200) NOT NULL,
    description  TEXT,
    release_year SMALLINT,
                 CONSTRAINT title_release_year_range
                 CHECK (release_year >= 1888),
    age_rating   SMALLINT     DEFAULT 0 NOT NULL,
                 CONSTRAINT age_rating_not_negative
                 CHECK (age_rating >= 0),

    /* Target of the (title_id, title_type) foreign keys in subclasses. */
    UNIQUE (title_id, title_type)
);

CREATE TABLE series (
    PRIMARY KEY (title_id),
    title_id    INTEGER NOT NULL,
    title_type  CHAR(2) DEFAULT 'SR'  NOT NULL,
                CONSTRAINT series_title_type
                CHECK (title_type = 'SR'),
    is_finished BOOLEAN DEFAULT FALSE NOT NULL,

    FOREIGN KEY (title_id, title_type)
        REFERENCES titles (title_id, title_type)
        ON DELETE CASCADE
);

/* Weak entity of series. */
CREATE TABLE seasons (
    PRIMARY KEY (title_id, season_num),
    title_id     INTEGER  NOT NULL,
    season_num   SMALLINT NOT NULL,
                 CONSTRAINT season_num_positive
                 CHECK (season_num > 0),
    season_name  VARCHAR(100),
    release_year SMALLINT,
                 CONSTRAINT season_release_year_range
                 CHECK (release_year >= 1888),

    FOREIGN KEY (title_id)
        REFERENCES series (title_id)
        ON DELETE CASCADE
);


/* ---------- Contents: EER specialization (disjoint, total) ---------- */

CREATE TABLE contents (
    PRIMARY KEY (content_id),
    content_id       BIGINT       GENERATED ALWAYS AS IDENTITY,
    content_type     CHAR(2)      NOT NULL,
                     CONSTRAINT content_type_value
                     CHECK (content_type IN ('MV', 'EP')),
    duration_seconds INTEGER      NOT NULL,
                     CONSTRAINT duration_positive
                     CHECK (duration_seconds > 0),
    video_url        VARCHAR(500) NOT NULL,
    release_date     DATE,

    /* Target of the (content_id, content_type) foreign keys in subclasses. */
    UNIQUE (content_id, content_type)
);

CREATE TABLE movies (
    PRIMARY KEY (content_id),
    content_id   BIGINT  NOT NULL,
    content_type CHAR(2) DEFAULT 'MV' NOT NULL,
                 CONSTRAINT movie_content_type
                 CHECK (content_type = 'MV'),
    title_id     INTEGER NOT NULL UNIQUE,
    title_type   CHAR(2) DEFAULT 'MV' NOT NULL,
                 CONSTRAINT movie_title_type
                 CHECK (title_type = 'MV'),

    FOREIGN KEY (content_id, content_type)
        REFERENCES contents (content_id, content_type)
        ON DELETE CASCADE,
    FOREIGN KEY (title_id, title_type)
        REFERENCES titles (title_id, title_type)
        ON DELETE CASCADE
);

CREATE TABLE episodes (
    PRIMARY KEY (content_id),
    content_id   BIGINT   NOT NULL,
    content_type CHAR(2)  DEFAULT 'EP' NOT NULL,
                 CONSTRAINT episode_content_type
                 CHECK (content_type = 'EP'),
    title_id     INTEGER  NOT NULL,
    season_num   SMALLINT NOT NULL,
    episode_num  SMALLINT NOT NULL,
                 CONSTRAINT episode_num_positive
                 CHECK (episode_num > 0),
    episode_name VARCHAR(200),

    UNIQUE (title_id, season_num, episode_num),
    FOREIGN KEY (content_id, content_type)
        REFERENCES contents (content_id, content_type)
        ON DELETE CASCADE,
    FOREIGN KEY (title_id, season_num)
        REFERENCES seasons (title_id, season_num)
        ON DELETE RESTRICT
);


/* ---------- Genres and people ---------- */

CREATE TABLE genres (
    PRIMARY KEY (genre_id),
    genre_id   SMALLINT    GENERATED ALWAYS AS IDENTITY,
    genre_name VARCHAR(50) NOT NULL UNIQUE
);

/* N:M between titles and genres. */
CREATE TABLE title_genres (
    PRIMARY KEY (title_id, genre_id),
    title_id INTEGER  NOT NULL,
    genre_id SMALLINT NOT NULL,

    FOREIGN KEY (title_id)
        REFERENCES titles (title_id)
        ON DELETE CASCADE,
    FOREIGN KEY (genre_id)
        REFERENCES genres (genre_id)
        ON DELETE RESTRICT
);

CREATE TABLE people (
    PRIMARY KEY (person_id),
    person_id   INTEGER      GENERATED ALWAYS AS IDENTITY,
    full_name   VARCHAR(100) NOT NULL,
    birth_date  DATE,
    nationality VARCHAR(50)
);

/* N:M between titles and people. */
CREATE TABLE title_credits (
    PRIMARY KEY (title_id, person_id, credit_role),
    title_id       INTEGER     NOT NULL,
    person_id      INTEGER     NOT NULL,
    credit_role    VARCHAR(10) NOT NULL,
                   CONSTRAINT credit_role_value
                   CHECK (credit_role IN ('DIRECTOR', 'ACTOR')),
    character_name VARCHAR(100),

    FOREIGN KEY (title_id)
        REFERENCES titles (title_id)
        ON DELETE CASCADE,
    FOREIGN KEY (person_id)
        REFERENCES people (person_id)
        ON DELETE RESTRICT
);


/* ---------- Watch history and watchlist ---------- */

/* N:M between profiles and contents; one row per viewing session. */
CREATE TABLE watch_history (
    PRIMARY KEY (user_id, profile_num, content_id, started_at),
    user_id          CHAR(7)   NOT NULL,
    profile_num      SMALLINT  NOT NULL,
    content_id       BIGINT    NOT NULL,
    started_at       TIMESTAMP NOT NULL,
    ended_at         TIMESTAMP,
    position_seconds INTEGER   DEFAULT 0 NOT NULL,
                     CONSTRAINT position_not_negative
                     CHECK (position_seconds >= 0),

    FOREIGN KEY (user_id, profile_num)
        REFERENCES profiles (user_id, profile_num)
        ON DELETE CASCADE,
    FOREIGN KEY (content_id)
        REFERENCES contents (content_id)
        ON DELETE RESTRICT,

    CONSTRAINT watch_time_order
    CHECK (ended_at >= started_at)
);

/* N:M between profiles and titles. */
CREATE TABLE watchlist_items (
    PRIMARY KEY (user_id, profile_num, title_id),
    user_id     CHAR(7)   NOT NULL,
    profile_num SMALLINT  NOT NULL,
    title_id    INTEGER   NOT NULL,
    added_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,

    FOREIGN KEY (user_id, profile_num)
        REFERENCES profiles (user_id, profile_num)
        ON DELETE CASCADE,
    FOREIGN KEY (title_id)
        REFERENCES titles (title_id)
        ON DELETE CASCADE
);
