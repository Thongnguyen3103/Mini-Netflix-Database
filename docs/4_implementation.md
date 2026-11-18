# 4. Cài đặt CSDL (Database Implementation)

Cơ sở dữ liệu được cài đặt trên PostgreSQL 18. Các script trong thư mục [SQL/](../SQL) chạy theo thứ tự số:

| File | Nội dung |
|---|---|
| [01_tables.sql](../SQL/01_tables.sql) | 18 bảng, khóa chính, khóa ngoại, `CHECK`, `UNIQUE`, `EXCLUDE` |
| [02_indexes.sql](../SQL/02_indexes.sql) | 11 chỉ mục |
| [03_triggers.sql](../SQL/03_triggers.sql) | 6 hàm trigger, 12 trigger |
| [04_views.sql](../SQL/04_views.sql) | 3 view |
| [05_seed_users.sql](../SQL/05_seed_users.sql) | Loại tài khoản và 5 tài khoản mẫu |
| [06_seed_sample_data.sql](../SQL/06_seed_sample_data.sql) | Dữ liệu mẫu tiếng Việt |
| [07_queries.sql](../SQL/07_queries.sql) | 14 truy vấn nâng cao (chỉ đọc) |
| [08_roles.sql](../SQL/08_roles.sql) | Phân quyền theo vai trò (mục 5.2) |

## 4.1. Các đối tượng đã cài đặt

### Bảng và ràng buộc

18 bảng được mô tả đầy đủ trong [Từ điển dữ liệu](3_data_dictionary.md). Ngoài khóa chính và 19 khóa ngoại, lược đồ dùng các loại ràng buộc khai báo sau:

| Loại | Ví dụ | Mục đích |
|---|---|---|
| `CHECK` miền giá trị | `subscription_status IN ('ACTIVE', 'EXPIRED', 'CANCELLED')` | Chặn giá trị trạng thái không hợp lệ |
| `CHECK` khoảng | `monthly_price >= 0`, `end_date > start_date` | Chặn số âm, khoảng ngày ngược |
| `CHECK` định dạng | `email LIKE '%_@_%'` | Chặn email sai dạng |
| `UNIQUE` | `(title_id, season_num, episode_num)` | Không trùng số tập trong một mùa |
| `EXCLUDE USING gist` | `subscription_no_overlap` | Một tài khoản không có hai gói chưa hủy trùng ngày |

### Chỉ mục

PostgreSQL tự tạo chỉ mục cho khóa chính và `UNIQUE`. 11 chỉ mục bổ sung phục vụ khóa ngoại và các truy vấn thường dùng:

| Chỉ mục | Phục vụ |
|---|---|
| `titles_name_trgm_idx` (GIN, `pg_trgm`) | Tìm phim theo từ khóa `ILIKE '%...%'` |
| `watch_history_recent_idx` | "Tiếp tục xem": các lượt xem gần nhất của một hồ sơ |
| `watch_history_content_idx` | Thống kê lượt xem của một nội dung |
| `subscriptions_user_dates_idx` | Tìm gói đang hiệu lực của tài khoản (trigger, view) |
| `payments_paid_at_idx` | Thống kê doanh thu theo thời gian |
| 6 chỉ mục trên khóa ngoại còn lại | Phép nối và kiểm tra khóa ngoại khi xóa |

### Trigger

| Trigger | Bảng | Quy tắc |
|---|---|---|
| `profiles_enforce_limit` | `profiles` | Số hồ sơ không vượt `max_profiles` của gói đang hiệu lực |
| `watch_history_enforce_access` | `watch_history` | Phải có gói bao trùm ngày xem; hồ sơ trẻ em chỉ xem nội dung `age_rating ≤ 12` |
| `watch_history_enforce_position` | `watch_history` | Vị trí xem không vượt thời lượng video |
| `contents_require_subclass` và 2 trigger khi xóa lớp con | `contents`, `movies`, `episodes` | Mỗi nội dung có đúng một dòng lớp con (phân cấp toàn phần) |
| `titles_require_subclass` và 2 trigger khi xóa lớp con | `titles`, `movies`, `series` | Mỗi tác phẩm có đúng một dòng lớp con |
| `movies_check_release_year` và 2 trigger khi sửa | `movies`, `titles`, `contents` | Năm của ngày phát hành phim lẻ bằng năm phát hành tác phẩm |

Các trigger kiểm tra phân cấp và năm phát hành là constraint trigger `DEFERRABLE INITIALLY DEFERRED`, chạy lúc `COMMIT`, để lớp cha và lớp con được thêm trong cùng một giao dịch.

### View

| View | Nội dung |
|---|---|
| `content_catalog` | Mọi video kèm thông tin tác phẩm, gộp phim lẻ và tập phim |
| `current_subscriptions` | Gói đang hiệu lực của từng tài khoản tại ngày hiện tại |
| `watch_progress` | Lượt xem gần nhất theo hồ sơ và nội dung, kèm % đã xem và cờ xem hết (≥ 90%) |

## 4.2. Truy vấn nâng cao và kiểm tra hiệu năng

### Truy vấn nâng cao

[SQL/07_queries.sql](../SQL/07_queries.sql) có 14 truy vấn, mỗi truy vấn trả lời một câu hỏi nghiệp vụ. Cột "Số dòng" là kết quả khi chạy trên dữ liệu mẫu của `05` và `06` (chưa có `09`) ngày 13/11/2026. Dữ liệu mẫu tính ngày theo `CURRENT_DATE`, nên số dòng có thể khác khi chạy vào ngày khác.

| # | Câu hỏi nghiệp vụ | Kỹ thuật | Số dòng |
|---|---|---|---|
| Q01 | 10 tác phẩm có nhiều người xem nhất 30 ngày qua | JOIN nhiều bảng qua hai lớp con, `COUNT(DISTINCT)`, `GROUP BY` | 10 |
| Q02 | Doanh thu thuần theo tháng và gói | `SUM(CASE ...)`, `FILTER`, `date_trunc` | 18 |
| Q03 | Người đang trả phí nhưng 14 ngày chưa xem gì | `NOT EXISTS` trên view | 14 |
| Q04 | "Tiếp tục xem" của từng hồ sơ | CTE, `ROW_NUMBER() OVER` | 25 |
| Q05 | Tập tiếp theo cần xem của từng phim bộ đang xem | Subquery tương quan, so sánh bộ giá trị, `LEFT JOIN` | 55 |
| Q06 | Thể loại yêu thích của từng hồ sơ | Hai CTE, `RANK() OVER` trên kết quả gộp | 76 |
| Q07 | Tỷ lệ xem hết theo tác phẩm (từ 5 lượt) | `HAVING`, `FILTER` | 15 |
| Q08 | Mức dùng hồ sơ theo gói | Bảng dẫn xuất, `AVG` trên số đếm | 3 |
| Q09 | Diễn viên tham gia nhiều tác phẩm nhất | Subquery vô hướng trong `SUM`, `HAVING` với subquery | 6 |
| Q10 | Người đổi gói khi gia hạn: nâng hay hạ cấp | `LAG() OVER`, mệnh đề `WINDOW`, `CASE` | 5 |
| Q11 | Tác phẩm đã lưu nhưng chưa từng xem | `NOT EXISTS` qua hai lớp con | 20 |
| Q12 | Gói sắp hết hạn trong 30 ngày, kèm email | `BETWEEN`, subquery `IN` | 8 |
| Q13 | Lượt xem theo khung giờ, tách trẻ em và người lớn | `CASE` trên `EXTRACT(HOUR)`, `FILTER` | 4 |
| Q14 | Tiến độ xem phim bộ từ 30% trở lên | `COUNT(DISTINCT)`, bảng dẫn xuất, `HAVING` theo ngưỡng tính toán | 9 |

### Kiểm tra hiệu năng

[SQL/tests/performance_tests.sql](../SQL/tests/performance_tests.sql) chạy trên một bản sao CSDL thử:
1. Thêm 50 000 phim lẻ và 420 000 lượt xem, nên dữ liệu có 50 030 tác phẩm và 420 200 lượt xem.
2. Chạy mỗi truy vấn với và không có chỉ mục cần đo (xóa chỉ mục tạm thời trong `SAVEPOINT`).
3. Hoàn tác toàn bộ (`ROLLBACK`) sau khi đo.

Cả script chạy trong khoảng 20 giây.

**Kết quả đo:** PostgreSQL 18, locale `C`, máy cá nhân, thời gian `Execution Time` của `EXPLAIN ANALYZE`, hai lần chạy.

| Ca | Truy vấn | Có chỉ mục | Không có chỉ mục | Kế hoạch thực thi |
|---|---|---|---|---|
| P1 | Tìm tác phẩm `ILIKE '%tinh%'` | 0,5 – 4,2 ms | 11,6 – 12,0 ms | Bitmap Index Scan trên `titles_name_trgm_idx` thay cho Seq Scan |
| P2 | Đếm lượt xem của một nội dung | 1,9 ms | 1,3 – 1,9 ms | Lần chạy thứ hai không dùng chỉ mục: planner chọn quét khóa chính |
| P3 | 20 lượt xem gần nhất của một hồ sơ | 0,03 – 0,06 ms | 2,8 – 4,3 ms | Index Scan theo thứ tự thay cho quét 12 000 dòng rồi sắp xếp |

**Nhận xét:**
- **P1, yêu cầu phi chức năng "tìm kiếm dưới 200 ms":** đạt ở cả hai trường hợp với 50 000 tác phẩm. Chỉ mục trigram nhanh hơn khoảng 3 đến 20 lần. Khoảng cách này lớn dần theo số tác phẩm, vì quét tuần tự tăng tuyến tính.
- **P3:** chỉ mục `watch_history_recent_idx` nhanh hơn khoảng 50 đến 100 lần, vì nó trả 20 dòng mới nhất mà không phải đọc và sắp xếp toàn bộ lịch sử của hồ sơ.
- **P2:** chỉ mục `watch_history_content_idx` không mang lại lợi ích rõ ràng. PostgreSQL 18 quét được chỉ mục khóa chính `(user_id, profile_num, content_id, started_at)` kể cả khi điều kiện không nằm ở cột đầu, nên nhanh tương đương. Nhóm có thể cân nhắc bỏ chỉ mục này, nhưng cần đo thêm thao tác xóa nội dung, vì khóa ngoại `RESTRICT` cũng tra theo `content_id`.

**Giới hạn của phép đo:**
- Thời gian thay đổi giữa các lần chạy, nên bảng ghi khoảng giá trị thay vì một con số.
- Chỉ mục trigram tách từ theo locale của cơ sở dữ liệu. Phép đo dùng từ khóa không dấu `tinh`. Với từ khóa có dấu, kết quả có thể khác trên server dùng locale khác `C`.
