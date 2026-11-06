-- 1. Bảng loại tài khoản
CREATE TABLE loai_tai_khoan (
    ma_loai     CHAR(3) PRIMARY KEY,                -- VD: 'ADM', 'USR', 'MOD'
    ten_loai    VARCHAR(50) NOT NULL UNIQUE,        -- VD: 'Quản trị viên'
    mo_ta       VARCHAR(255),
    trang_thai  BOOLEAN NOT NULL DEFAULT TRUE,      -- loại này còn dùng hay không
    ngay_tao    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. Dữ liệu mẫu (thêm trước khi gán cho users)
INSERT INTO loai_tai_khoan (ma_loai, ten_loai, mo_ta) VALUES
    ('ADM', 'Quản trị viên', 'Toàn quyền quản trị hệ thống'),
    ('MOD', 'Kiểm duyệt viên', 'Quản lý nội dung, không quản lý hệ thống'),
    ('USR', 'Người dùng',     'Tài khoản thường');

-- 3. Nối vào bảng users
ALTER TABLE users
    ADD COLUMN loai_tk CHAR(3) NOT NULL DEFAULT 'USR';

ALTER TABLE users
    ADD CONSTRAINT fk_users_loai_tk
    FOREIGN KEY (loai_tk) REFERENCES loai_tai_khoan (ma_loai)
    ON UPDATE CASCADE
    ON DELETE RESTRICT;

CREATE INDEX idx_users_loai_tk ON users (loai_tk);