# Mini-Netflix

Đồ án cơ sở dữ liệu — hệ thống quản lý phim trực tuyến.

## Công nghệ

- PostgreSQL 18

## Sơ đồ CSDL

```mermaid
erDiagram
    LOAI_TAI_KHOAN ||--o{ USERS : "phan loai"
    LOAI_TAI_KHOAN {
        char(3) ma_loai PK
        varchar ten_loai UK
        varchar mo_ta
        boolean trang_thai
        timestamp ngay_tao
    }
    USERS {
        char(7) id PK
        varchar username UK
        varchar email UK
        varchar gioi_tinh
        char(3) loai_tk FK
        timestamp ngay_tao
    }
```

### Mô tả các bảng

| Bảng | Mô tả |
|---|---|
| `loai_tai_khoan` | Danh mục loại tài khoản (quản trị viên, kiểm duyệt viên, người dùng) |
| `users` | Tài khoản người dùng, mỗi tài khoản thuộc đúng một loại |

Quan hệ: một loại tài khoản có nhiều users (1–N), nối qua `users.loai_tk → loai_tai_khoan.ma_loai`.

## Cài đặt

```bash
createdb Mini-Netflix
psql -d Mini-Netflix -f schema.sql
```

## Cấu trúc thư mục

```
schema.sql     Script tạo bảng (nguồn chân lý của CSDL)
docs/
  erd.png      Sơ đồ ERD xuất từ pgAdmin (dùng cho báo cáo)
  erd.pgerd    File gốc, mở lại bằng pgAdmin ERD Tool
```
