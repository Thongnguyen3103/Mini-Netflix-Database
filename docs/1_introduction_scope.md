# 1. Giới thiệu Đồ án và Phạm vi Đồ án (Introduction & Project Scope)

Mục này xác lập yêu cầu cho cơ sở dữ liệu của nền tảng phát trực tuyến theo yêu cầu **Mini-Netflix** (đề tài #2). Cấu trúc theo tiêu chuẩn đặc tả yêu cầu phần mềm ISO/IEC/IEEE 29148:
- Yêu cầu của người dùng (mục 1.2.2) được tách khỏi năng lực của hệ thống (mục 1.2.3).
- Yêu cầu phi chức năng được nêu ở mục 1.2.4.
- Quy tắc nghiệp vụ được liệt kê riêng, có mã số, ở mục 1.2.5.

## Bối cảnh và vấn đề cần giải quyết

Mini-Netflix cho người dùng đăng ký gói dịch vụ trả phí để xem phim lẻ và phim bộ. Một tài khoản dùng chung cho cả gia đình, chia thành nhiều hồ sơ xem; mỗi hồ sơ có lịch sử xem và danh sách theo dõi riêng.

Đề bài nêu hai khó khăn chính khi thiết kế cơ sở dữ liệu:

1. **Phân cấp nội dung:** phim lẻ và tập phim đều là video xem được, nhưng có thuộc tính khác nhau. Một tập phim còn thuộc một mùa của một phim bộ. Thiết kế phải dùng phân lớp (specialization) và tổng quát hóa (generalization) của mô hình EER.
2. **Quan hệ nhiều-nhiều của lịch sử xem và danh sách theo dõi:**
   - Một hồ sơ xem nhiều nội dung, và xem lại cùng một nội dung nhiều lần.
   - Một nội dung được nhiều hồ sơ xem.
   - Danh sách theo dõi lưu cả phim bộ, chứ không lưu từng tập.

## 1.1. Mục tiêu hệ thống (System Objectives)

| Mã | Mục tiêu |
|---|---|
| OBJ-01 | Lưu trữ nhất quán thông tin tài khoản, hồ sơ xem, gói dịch vụ, đăng ký và thanh toán. |
| OBJ-02 | Quản lý danh mục phim lẻ, phim bộ, mùa, tập theo một phân cấp EER rời nhau và toàn phần. |
| OBJ-03 | Ghi lại lịch sử xem theo từng hồ sơ, đủ để tiếp tục xem dở và thống kê mức độ xem. |
| OBJ-04 | Bắt buộc các quy tắc nghiệp vụ ngay ở tầng cơ sở dữ liệu, bằng ràng buộc và trigger, không phụ thuộc vào ứng dụng. |
| OBJ-05 | Phân quyền truy cập theo vai trò, theo nguyên tắc quyền tối thiểu. |
| OBJ-06 | Hỗ trợ các truy vấn báo cáo: doanh thu, tác phẩm được xem nhiều, người dùng có nguy cơ rời bỏ. |

### Phạm vi

| Trong phạm vi | Ngoài phạm vi |
|---|---|
| Lược đồ dữ liệu, ràng buộc, trigger, view, chỉ mục, phân quyền | Lưu trữ và truyền phát tệp video (chỉ lưu đường dẫn `video_url`) |
| Dữ liệu mẫu tiếng Việt và truy vấn báo cáo | Kết nối cổng thanh toán thật (chỉ ghi nhận kết quả giao dịch) |
| Ứng dụng demo đơn giản kết nối CSDL (giai đoạn 4) | Gợi ý phim tự động, phụ đề đa ngôn ngữ, quản lý thiết bị đăng nhập |

## 1.2. Các quy tắc và Ràng buộc Nghiệp vụ (Business Rules & Constraints)

Mục này gồm các bên liên quan (1.2.1), yêu cầu người dùng (1.2.2), yêu cầu chức năng (1.2.3), yêu cầu phi chức năng (1.2.4) và danh sách quy tắc nghiệp vụ có mã số (1.2.5). Mỗi quy tắc ghi rõ cách cơ sở dữ liệu bắt buộc nó, và bài kiểm thử chứng minh nó hoạt động.

### 1.2.1. Các bên liên quan (Stakeholders)

| Vai trò | Mô tả | Vai trò CSDL tương ứng |
|---|---|---|
| Người xem | Chủ tài khoản và các thành viên dùng hồ sơ xem | `netflix_app` (qua ứng dụng) |
| Kiểm duyệt viên | Quản lý danh mục phim | `netflix_moderator` |
| Quản trị viên | Quản lý toàn hệ thống, gói dịch vụ, xử lý sự cố | `netflix_admin` |
| Phân tích viên | Lập báo cáo kinh doanh, không được xem thông tin liên lạc | `netflix_analyst` |

### 1.2.2. Yêu cầu người dùng (User Requirements)

Phát biểu theo góc nhìn người dùng, chưa nói tới cách hệ thống thực hiện.

| Mã | Người dùng | Yêu cầu |
|---|---|---|
| UR-01 | Người xem | Tôi muốn đăng ký tài khoản bằng email và mật khẩu. |
| UR-02 | Người xem | Tôi muốn mua một gói dịch vụ và biết gói của tôi còn hạn đến ngày nào. |
| UR-03 | Người xem | Tôi muốn tạo hồ sơ riêng cho từng thành viên trong gia đình, kể cả hồ sơ cho trẻ em. |
| UR-04 | Người xem | Tôi muốn tìm phim theo tên và xem thông tin thể loại, diễn viên, đạo diễn. |
| UR-05 | Người xem | Tôi muốn xem tiếp từ chỗ đã dừng, và biết tập tiếp theo của phim bộ đang xem. |
| UR-06 | Người xem | Tôi muốn lưu phim lẻ hoặc cả bộ phim vào danh sách để xem sau. |
| UR-07 | Phụ huynh | Tôi muốn hồ sơ của con tôi không xem được phim không phù hợp lứa tuổi. |
| UR-08 | Kiểm duyệt viên | Tôi muốn thêm, sửa phim lẻ, phim bộ, mùa, tập và thông tin liên quan. |
| UR-09 | Quản trị viên | Tôi muốn quản lý gói dịch vụ và xem toàn bộ lịch sử thanh toán. |
| UR-10 | Phân tích viên | Tôi muốn thống kê doanh thu, mức độ xem và người dùng có nguy cơ rời bỏ. |

### 1.2.3. Yêu cầu chức năng của hệ thống (Functional Requirements)

Các thao tác hướng dữ liệu mà hệ thống phải cung cấp. Cột cuối ghi bảng dữ liệu và yêu cầu người dùng liên quan.

| Mã | Hệ thống phải… | Bảng | Từ |
|---|---|---|---|
| FR-01 | Cho phép tạo tài khoản với tên đăng nhập và email không trùng, mật khẩu lưu dạng băm. | `users` | UR-01 |
| FR-02 | Cho phép ghi một lần đăng ký gói trong một khoảng ngày và các giao dịch thanh toán của nó. | `subscriptions`, `payments` | UR-02 |
| FR-03 | Cho biết gói đang hiệu lực của một tài khoản tại ngày hiện tại. | View `current_subscriptions` | UR-02 |
| FR-04 | Cho phép tạo, đổi tên, xóa hồ sơ xem và đánh dấu hồ sơ trẻ em. | `profiles` | UR-03, UR-07 |
| FR-05 | Cho phép tìm tác phẩm theo từ khóa trong tên. | `titles` | UR-04 |
| FR-06 | Trả về thể loại, đạo diễn, diễn viên của một tác phẩm. | `title_genres`, `title_credits` | UR-04 |
| FR-07 | Ghi một lượt xem (hồ sơ, nội dung, thời điểm bắt đầu, kết thúc, vị trí) và cập nhật vị trí khi xem tiếp. | `watch_history` | UR-05 |
| FR-08 | Trả về các nội dung xem dở gần nhất và tập tiếp theo của mỗi phim bộ đang xem. | View `watch_progress`; Q04, Q05 | UR-05 |
| FR-09 | Cho phép thêm, xóa tác phẩm trong danh sách theo dõi của một hồ sơ. | `watchlist_items` | UR-06 |
| FR-10 | Cho phép kiểm duyệt viên thêm, sửa, xóa tác phẩm, mùa, tập, thể loại, người tham gia. | Nhóm bảng danh mục | UR-08 |
| FR-11 | Cho phép quản trị viên sửa gói dịch vụ và xem, sửa mọi dữ liệu. | Mọi bảng | UR-09 |
| FR-12 | Cung cấp truy vấn thống kê doanh thu, tác phẩm xem nhiều, tỷ lệ xem hết, người dùng ngừng xem. | Q01–Q14 trong `SQL/07_queries.sql` | UR-10 |

### 1.2.4. Yêu cầu phi chức năng (Non-Functional Requirements)

| Mã | Nhóm | Yêu cầu | Cách đáp ứng / bằng chứng | Trạng thái |
|---|---|---|---|---|
| NFR-01 | Hiệu năng | Tìm tác phẩm theo từ khóa trả kết quả dưới 200 ms với 50 000 tác phẩm. | Chỉ mục GIN `pg_trgm`; đo được 0,5–4,2 ms (`SQL/tests/performance_tests.sql`, P1) | Đạt |
| NFR-02 | Hiệu năng | Lấy 20 lượt xem gần nhất của một hồ sơ dưới 50 ms với 420 000 lượt xem. | Chỉ mục `watch_history_recent_idx`; đo được dưới 0,1 ms (P3) | Đạt |
| NFR-03 | Toàn vẹn | Mọi quy tắc nghiệp vụ ở mục 1.2.5 được bắt buộc trong CSDL, kể cả khi dữ liệu được ghi trực tiếp không qua ứng dụng. | Ràng buộc và trigger; 32 ca kiểm thử (`SQL/tests/constraint_tests.sql`) | Đạt |
| NFR-04 | Bảo mật | Không lưu mật khẩu gốc. | Cột `password_hash`; dữ liệu mẫu băm bằng bcrypt (`crypt`, `gen_salt('bf')`) | Đạt với dữ liệu mẫu; ứng dụng phải băm khi đăng ký |
| NFR-05 | Bảo mật | Mỗi vai trò chỉ có quyền tối thiểu. Ứng dụng không xóa được thanh toán, lịch sử xem; không tự nâng quyền tài khoản. | `SQL/08_roles.sql`; 28 ca kiểm thử (`SQL/tests/rbac_tests.sql`) | Đạt |
| NFR-06 | Bảo mật | Phân tích viên không đọc được email và mã băm mật khẩu. | Phân quyền theo cột trên `users` | Đạt |
| NFR-07 | Bảo mật | Dữ liệu được mã hóa khi lưu trữ (encryption at rest). | PostgreSQL bản cộng đồng không có sẵn; cần mã hóa ở mức ổ đĩa (ví dụ BitLocker) khi triển khai | Ngoài phạm vi cài đặt |
| NFR-08 | Sẵn sàng | Có thể khôi phục dữ liệu khi sự cố, mất tối đa dữ liệu của 1 ngày. | Sao lưu hằng ngày bằng `pg_dump` khi triển khai | Chưa cài đặt, chưa kiểm chứng |
| NFR-09 | Bảo trì | Script SQL theo một chuẩn trình bày công khai và chạy lại được từ đầu theo thứ tự đánh số. | SQLStyle.guide; `SQL/01`–`09` | Đạt |
| NFR-10 | Bản địa hóa | Lưu và hiển thị đúng tiếng Việt có dấu. | Mã hóa UTF-8; dữ liệu mẫu tiếng Việt | Đạt |

### 1.2.5. Danh sách quy tắc nghiệp vụ

| Mã | Quy tắc | Cách CSDL bắt buộc | Kiểm thử |
|---|---|---|---|
| **Tài khoản và hồ sơ** | | | |
| BR-01 | Mỗi tài khoản thuộc đúng một loại tài khoản: quản trị viên (ADM), kiểm duyệt viên (MOD) hoặc người dùng (USR). | Khóa ngoại `NOT NULL` `users.account_type_code` | — |
| BR-02 | Tên đăng nhập và email không trùng giữa các tài khoản; email có dạng `x@y`. | `UNIQUE`; `CHECK email_format` | Có |
| BR-03 | Một tài khoản có nhiều hồ sơ. Hồ sơ chỉ tồn tại khi tài khoản còn, và bị xóa theo tài khoản. | Thực thể yếu; `ON DELETE CASCADE` | — |
| BR-04 | Tên hồ sơ không trùng trong cùng một tài khoản. | `UNIQUE (user_id, profile_name)` | Có |
| BR-05 | Chỉ tạo được hồ sơ khi tài khoản có gói đang hiệu lực, và số hồ sơ không vượt số hồ sơ tối đa của gói đó. | Trigger `profiles_enforce_limit` | Có |
| **Gói, đăng ký, thanh toán** | | | |
| BR-06 | Mỗi gói có giá theo tháng ≥ 0, số hồ sơ tối đa > 0 và tên không trùng. | `CHECK`, `UNIQUE` | Có |
| BR-07 | Mỗi lần đăng ký thuộc một tài khoản và một gói. Lần đăng ký có hiệu lực từ ngày bắt đầu đến trước ngày kết thúc, và ngày kết thúc sau ngày bắt đầu. | Khóa ngoại; `CHECK subscription_date_order` | Có |
| BR-08 | Một tài khoản không có hai đăng ký chưa hủy trùng ngày nhau. Đăng ký đã hủy không bị tính. | `EXCLUDE subscription_no_overlap` | Có |
| BR-09 | Trạng thái đăng ký là ACTIVE, EXPIRED hoặc CANCELLED. Trạng thái thanh toán là SUCCESS, FAILED hoặc REFUNDED. | `CHECK` | Có |
| BR-10 | Mỗi giao dịch thanh toán thuộc một lần đăng ký. Số tiền ≥ 0 và là số tiền thực trả, giữ nguyên khi giá gói thay đổi về sau. | Khóa ngoại; `CHECK amount_not_negative` | Có |
| BR-11 | Lịch sử tài chính không bị xóa gián tiếp: không xóa được tài khoản đã có đăng ký, gói đã được dùng, đăng ký đã có thanh toán. | Khóa ngoại `ON DELETE RESTRICT` | Có |
| **Danh mục phim** | | | |
| BR-12 | Mỗi tác phẩm là đúng một trong hai: phim lẻ hoặc phim bộ. | Phân cấp rời nhau, toàn phần: khóa ngoại ghép + `CHECK` + constraint trigger | Có |
| BR-13 | Mỗi nội dung xem được là đúng một trong hai: phim lẻ hoặc tập phim. | Như BR-12, trên `contents` | Có |
| BR-14 | Mỗi phim lẻ vừa là một tác phẩm vừa là một nội dung xem được, và ứng với đúng một dòng ở mỗi bên. | Lớp con dùng chung `movies`: khóa chính `content_id`, `UNIQUE title_id` | Có |
| BR-15 | Chỉ phim bộ mới có mùa; mùa thuộc một phim bộ; tập thuộc một mùa; số tập không trùng trong một mùa. | Thực thể yếu `seasons`; khóa ngoại tới `series`; `UNIQUE (title_id, season_num, episode_num)` | Có |
| BR-16 | Với phim lẻ, năm của ngày phát hành video phải bằng năm phát hành tác phẩm. | Constraint trigger `*_check_movie_release_year` | Có |
| BR-17 | Một tác phẩm có nhiều thể loại, và một thể loại có nhiều tác phẩm. | Bảng liên kết `title_genres` | — |
| BR-18 | Một người có thể tham gia nhiều tác phẩm với vai trò đạo diễn hoặc diễn viên, và có thể vừa đạo diễn vừa đóng trong cùng tác phẩm. | `title_credits`, khóa chính gồm `credit_role` | — |
| BR-19 | Thời lượng video > 0. Năm phát hành ≥ 1888. Độ tuổi xem ≥ 0, trong đó 0 là mọi lứa tuổi. | `CHECK` | Có |
| **Xem phim** | | | |
| BR-20 | Một hồ sơ có thể xem cùng một nội dung nhiều lần; mỗi lần là một lượt xem riêng. | Khóa chính `watch_history` gồm `started_at` | — |
| BR-21 | Chỉ ghi được lượt xem khi tài khoản có đăng ký chưa hủy bao trùm ngày xem. | Trigger `watch_history_enforce_access` | Có |
| BR-22 | Hồ sơ trẻ em chỉ xem được nội dung có độ tuổi xem ≤ 12. | Trigger `watch_history_enforce_access` | Có |
| BR-23 | Vị trí xem nằm trong khoảng từ 0 đến thời lượng video; thời điểm kết thúc không trước thời điểm bắt đầu. | Trigger `watch_history_enforce_position`; `CHECK watch_time_order` | Có |
| BR-24 | Một lượt xem được tính là xem hết khi đạt từ 90% thời lượng. | Tính trong view `watch_progress`, không lưu | — |
| BR-25 | Không xóa được nội dung đã có lịch sử xem. | Khóa ngoại `ON DELETE RESTRICT` | Có |
| BR-26 | Danh sách theo dõi lưu tác phẩm (phim lẻ hoặc cả phim bộ), mỗi tác phẩm một lần cho mỗi hồ sơ. | Khóa chính `(user_id, profile_num, title_id)` | — |

**Về cột "Kiểm thử":**
- `Có` nghĩa là quy tắc có ít nhất một ca trong `SQL/tests/constraint_tests.sql` chứng minh dữ liệu vi phạm bị chặn.
- `—` là các quy tắc mang tính cấu trúc, được đảm bảo bởi cách tổ chức bảng và khóa, nên không có ca kiểm thử riêng.

**Ngưỡng do nhóm tự đặt:** đề bài không quy định các ngưỡng dưới đây, nên nhóm cần chốt trước khi nộp:
- Độ tuổi 12 cho hồ sơ trẻ em (BR-22).
- Mức 90% để tính là xem hết (BR-24).
- Khoảng ngày hiệu lực không tính ngày kết thúc (BR-07).
