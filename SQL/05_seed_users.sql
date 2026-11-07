/*
 * Mini-Netflix database: account types and users seed data.
 * Run last, after 04_views.sql. The account_types and users tables, and the
 * foreign key between them, are created in 01_tables.sql.
 *
 * Test data only: every seeded user has the password 'demo123',
 * stored as a bcrypt hash.
 */

SET client_encoding = 'UTF8';

/* Provides crypt() and gen_salt() for the password hashes. */
CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO account_types (account_type_code, account_type_name, description)
VALUES ('ADM', 'Quản trị viên',   'Toàn quyền quản trị hệ thống'),
       ('MOD', 'Kiểm duyệt viên', 'Quản lý nội dung, không quản lý hệ thống'),
       ('USR', 'Người dùng',      'Tài khoản thường');

INSERT INTO users (user_id, username, email, password_hash, gender, account_type_code)
VALUES ('U000001', 'admin',     'admin@example.com',     crypt('demo123', gen_salt('bf')), NULL,     'ADM'),
       ('U000002', 'moderator', 'moderator@example.com', crypt('demo123', gen_salt('bf')), NULL,     'MOD'),
       ('U000003', 'minh_anh',  'minh.anh@example.com',  crypt('demo123', gen_salt('bf')), 'FEMALE', 'USR'),
       ('U000004', 'quoc_bao',  'quoc.bao@example.com',  crypt('demo123', gen_salt('bf')), 'MALE',   'USR'),
       ('U000005', 'thu_ha',    'thu.ha@example.com',    crypt('demo123', gen_salt('bf')), 'FEMALE', 'USR');
