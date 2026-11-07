CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX users_account_type_idx
    ON users (account_type_code);

CREATE INDEX subscriptions_plan_idx
    ON subscriptions (plan_id);

CREATE INDEX subscriptions_user_dates_idx
    ON subscriptions (user_id, start_date, end_date);

CREATE INDEX payments_subscription_idx
    ON payments (subscription_id);

CREATE INDEX payments_paid_at_idx
    ON payments (paid_at);

CREATE INDEX titles_name_trgm_idx
    ON titles USING gin (title_name gin_trgm_ops);

CREATE INDEX title_genres_genre_idx
    ON title_genres (genre_id);

CREATE INDEX title_credits_person_idx
    ON title_credits (person_id);

CREATE INDEX watch_history_content_idx
    ON watch_history (content_id);

/* Most recent sessions of a profile. */
CREATE INDEX watch_history_recent_idx
    ON watch_history (user_id, profile_num, started_at DESC);

CREATE INDEX watchlist_items_title_idx
    ON watchlist_items (title_id);
