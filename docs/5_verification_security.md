# 5. Kiểm tra và An toàn (Verification & Security)

## 5.1. Các bài kiểm tra

[SQL/tests/constraint_tests.sql](../SQL/tests/constraint_tests.sql) chứng minh các ràng buộc và trigger chấp nhận dữ liệu hợp lệ và chặn dữ liệu không hợp lệ.

**Cách thực hiện:**
1. Nạp các file `01` đến `06` vào CSDL, rồi chạy script bằng `psql` với quyền superuser.
2. Script tạo bộ dữ liệu riêng (tài khoản `T000001`, `T000002`, một gói 2 hồ sơ, một phim lẻ 18+, một phim bộ), nên không phụ thuộc dữ liệu mẫu.
3. Mỗi ca chạy trong một giao dịch con. Ràng buộc trì hoãn được ép kiểm tra ngay (`SET CONSTRAINTS ALL IMMEDIATE`), giống như khi `COMMIT`.
4. Toàn bộ được hoàn tác ở cuối, nên dữ liệu không đổi.

Mỗi dòng kết quả ghi `PASS` khi kết quả khớp kỳ vọng, kèm mã lỗi PostgreSQL.

**Kết quả:** 32/32 ca `PASS`, chạy ngày 13/11/2026.

| Nhóm | Ca kiểm tra | Kỳ vọng | Bị chặn bởi |
|---|---|---|---|
| Miền giá trị | Email không có `@` | Chặn | `CHECK email_format` |
| | Trùng tên đăng nhập | Chặn | `UNIQUE users_username_key` |
| | Giá gói âm | Chặn | `CHECK monthly_price_not_negative` |
| | Số tiền thanh toán âm | Chặn | `CHECK amount_not_negative` |
| | Trạng thái thanh toán lạ (`PENDING`) | Chặn | `CHECK payment_status_value` |
| | Thời lượng video bằng 0 | Chặn | `CHECK duration_positive` |
| | Kết thúc xem trước khi bắt đầu | Chặn | `CHECK watch_time_order` |
| Đăng ký gói | Ngày kết thúc trước ngày bắt đầu | Chặn | `CHECK subscription_date_order` |
| | Hai gói chưa hủy trùng ngày | Chặn | `EXCLUDE subscription_no_overlap` |
| | Gói trùng ngày nhưng đã hủy | Cho phép | |
| | Gói nối tiếp ngay sau gói hiện tại | Cho phép | |
| Hồ sơ | Hồ sơ thứ 3 trên gói 2 hồ sơ | Chặn | Trigger `profiles_enforce_limit` |
| | Tạo hồ sơ khi không có gói | Chặn | Trigger `profiles_enforce_limit` |
| | Trùng tên hồ sơ trong một tài khoản | Chặn | `UNIQUE (user_id, profile_name)` |
| Phân cấp EER | Nội dung không có lớp con | Chặn | Constraint trigger `contents_require_subclass` |
| | Tác phẩm không có lớp con | Chặn | Constraint trigger `titles_require_subclass` |
| | Chỉ xóa dòng `movies`, giữ lớp cha | Chặn | Constraint trigger `movies_keep_content_subclass` |
| | Dùng video phim lẻ làm tập phim | Chặn | Khóa ngoại ghép `(content_id, content_type)` |
| | Dùng video tập phim làm phim lẻ | Chặn | Khóa ngoại ghép `(content_id, content_type)` |
| | Gắn `series` vào tác phẩm loại phim lẻ | Chặn | Khóa ngoại ghép `(title_id, title_type)` |
| | Đổi loại của nội dung đã có lớp con | Chặn | Khóa ngoại ghép |
| | Trùng số tập trong một mùa | Chặn | `UNIQUE (title_id, season_num, episode_num)` |
| | Thêm trọn một phim lẻ trong một giao dịch | Cho phép | |
| | Xóa trọn một phim lẻ trong một giao dịch | Cho phép | |
| Năm phát hành | Ngày phát hành lệch năm của tác phẩm | Chặn | Constraint trigger `contents_check_movie_release_year` |
| | Sửa cả năm và ngày trong một giao dịch | Cho phép | |
| Lịch sử xem | Vị trí xem vượt thời lượng | Chặn | Trigger `watch_history_enforce_position` |
| | Hồ sơ trẻ em xem phim 18+ | Chặn | Trigger `watch_history_enforce_access` |
| | Hồ sơ người lớn xem phim 18+ | Cho phép | |
| | Xem ngoài thời hạn gói | Chặn | Trigger `watch_history_enforce_access` |
| Xóa dữ liệu | Xóa nội dung đã có lịch sử xem | Chặn | Khóa ngoại `RESTRICT` |
| | Xóa tài khoản đã có đăng ký | Chặn | Khóa ngoại `RESTRICT` |

Mỗi ca bị chặn đều do đúng ràng buộc cần kiểm tra, được xác nhận qua tên ràng buộc trong thông báo lỗi. Ví dụ, ca trùng tên hồ sơ được thiết kế để không vướng giới hạn số hồ sơ trước.

## 5.2. Phân quyền theo vai trò (RBAC)

[SQL/08_roles.sql](../SQL/08_roles.sql) tạo 4 vai trò nhóm (`NOLOGIN`) giữ quyền, và 4 vai trò đăng nhập chỉ kế thừa từ vai trò nhóm. Script chạy lại được nhiều lần. Vai trò đăng nhập được tạo không có mật khẩu, nên quản trị viên cần đặt bằng `\password <tên>`.

| Vai trò nhóm | Vai trò đăng nhập | Dành cho |
|---|---|---|
| `netflix_admin` | `admin_login` | Quản trị viên |
| `netflix_moderator` | `moderator_login` | Kiểm duyệt viên quản lý danh mục phim |
| `netflix_app` | `webapp_login` | Backend của ứng dụng web |
| `netflix_analyst` | `analyst_login` | Người làm báo cáo, thống kê |

### Ma trận quyền

`S` SELECT, `I` INSERT, `U` UPDATE, `D` DELETE, `—` không có quyền.

| Đối tượng | admin | moderator | app | analyst |
|---|---|---|---|---|
| Danh mục phim: `titles`, `series`, `seasons`, `contents`, `movies`, `episodes`, `genres`, `title_genres`, `people`, `title_credits` | SIUD | SIUD | S | S |
| `users` | SIUD | — | S, I, U (`username`, `email`, `password_hash`, `gender`) | S (`user_id`, `username`, `gender`, `account_type_code`, `created_at`) |
| `profiles`, `watchlist_items` | SIUD | — | SIUD | S |
| `subscriptions` | SIUD | — | S, I, U (`subscription_status`) | S |
| `payments` | SIUD | — | S, I | S |
| `watch_history` | SIUD | — | S, I, U (`ended_at`, `position_seconds`) | S |
| `account_types`, `plans` | SIUD | — | S | S |
| View `content_catalog`, `watch_progress` | S | S | S | S |
| View `current_subscriptions` | S | — | S | S |

### Các lệnh GRANT/REVOKE chính

```sql
-- Bắt đầu từ trạng thái không có quyền.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Ứng dụng chỉ được sửa một số cột: không tự nâng quyền tài khoản.
GRANT UPDATE (username, email, password_hash, gender) ON users TO netflix_app;

-- Lịch sử thanh toán chỉ được thêm, không sửa hay xóa.
GRANT SELECT, INSERT ON subscriptions, payments TO netflix_app;

-- Người phân tích không đọc được email và mật khẩu.
REVOKE SELECT ON users FROM netflix_analyst;
GRANT SELECT (user_id, username, gender, account_type_code, created_at) ON users TO netflix_analyst;
```

### Nguyên tắc thiết kế

- **Quyền tối thiểu:** mỗi vai trò chỉ có quyền cần cho công việc của nó.
  - Ứng dụng web không xóa được tài khoản, thanh toán hay lịch sử xem.
  - Ứng dụng web không đổi được `account_type_code`, nên người dùng không tự nâng mình thành quản trị viên.
- **Phân quyền theo cột:** áp dụng ở `users`, `subscriptions`, `watch_history`, để giới hạn những gì được sửa và những gì được đọc.
- **Trigger chạy với quyền của chủ sở hữu:** 6 hàm trigger là `SECURITY DEFINER` với `search_path` cố định.
  - Lý do: trigger cần đọc các bảng mà vai trò gọi không được thấy. Ví dụ, khi ứng dụng thêm hồ sơ, trigger phải khóa dòng `users` và đọc `plans`.
  - `search_path` cố định ngăn người gọi chèn đối tượng giả mạo vào đường tìm kiếm.
  - Quyền `EXECUTE` trực tiếp trên các hàm này bị thu hồi khỏi `PUBLIC`.

### Kiểm tra phân quyền

[SQL/tests/rbac_tests.sql](../SQL/tests/rbac_tests.sql) chuyển sang từng vai trò (`SET LOCAL ROLE`), thử thao tác, rồi hoàn tác. Script được chạy sau `08_roles.sql`.

**Kết quả:** 28/28 ca `PASS`, chạy ngày 13/11/2026.

| Vai trò | Được phép (đã kiểm tra) | Bị từ chối (đã kiểm tra) |
|---|---|---|
| `netflix_app` | Đọc danh mục; đăng ký tài khoản; đổi email; tạo hồ sơ (qua trigger giới hạn); ghi lượt xem; cập nhật vị trí xem; ghi thanh toán | Tự nâng lên ADM; xóa tài khoản; đổi nội dung đã xem; xóa lịch sử xem; sửa số tiền thanh toán; thêm phim; đổi giá gói |
| `netflix_moderator` | Thêm phim bộ kèm mùa; sửa mô tả phim; đọc view thống kê | Đọc email người dùng; đọc thanh toán |
| `netflix_analyst` | Đọc lịch sử xem; đọc cột không nhạy cảm của `users` | Đọc email; đọc mã băm mật khẩu; sửa dữ liệu |
| `netflix_admin` | Xóa thanh toán; đổi giá gói | |
| `webapp_login`, `analyst_login` | Kế thừa đúng quyền của vai trò nhóm | Kế thừa đúng giới hạn của vai trò nhóm |

Hai ca "tạo hồ sơ" và "ghi lượt xem" của `netflix_app` đã được xác nhận là thêm được đúng 1 dòng, tức trigger thực sự chạy dưới vai trò này chứ không phải câu lệnh không thêm dòng nào.
