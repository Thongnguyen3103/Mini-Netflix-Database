# 3. Từ điển dữ liệu (Data Dictionary)

Tài liệu mô tả siêu dữ liệu của 18 bảng theo nguyên tắc của ISO/IEC 11179: mỗi thuộc tính có tên, kiểu dữ liệu, loại khóa, khả năng NULL, giá trị mặc định và quy tắc nghiệp vụ.

Kiểu dữ liệu, khóa, NULL và giá trị mặc định được trích tự động từ CSDL PostgreSQL 18 sau khi chạy `SQL/01_tables.sql`, nên khớp với DDL tại thời điểm tạo tài liệu. Riêng cột Business Rules / Constraints do nhóm viết.

**Quy ước cột Key Type:** `PK` khóa chính, `FK` khóa ngoại, `UK` khóa duy nhất một cột, `UK ghép` thuộc một ràng buộc UNIQUE nhiều cột, `None` không phải khóa.

## 3.1. `account_types`

Danh mục loại tài khoản, quyết định quyền của người dùng trong hệ thống.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `account_type_code` | CHAR(3) | PK | No | None | Mã 3 ký tự: ADM (quản trị viên), MOD (kiểm duyệt viên), USR (người dùng). |
| `account_type_name` | VARCHAR(50) | UK | No | None | Tên loại tài khoản, không trùng. |
| `description` | VARCHAR(255) | None | Yes | NULL | Mô tả quyền hạn của loại tài khoản. |
| `is_active` | BOOLEAN | None | No | true | FALSE khi loại tài khoản ngừng được dùng. |
| `created_at` | TIMESTAMP | None | No | CURRENT_TIMESTAMP | Thời điểm tạo bản ghi. |

## 3.2. `users`

Tài khoản đăng nhập. Mỗi tài khoản thuộc đúng một loại tài khoản.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `user_id` | CHAR(7) | PK | No | None | Mã tài khoản 7 ký tự, ví dụ U000001. |
| `username` | VARCHAR(50) | UK | No | None | Tên đăng nhập, không trùng. |
| `email` | VARCHAR(100) | UK | No | None | Không trùng. Phải có dạng x@y (CHECK email_format). |
| `password_hash` | VARCHAR(255) | None | No | None | Chỉ lưu mã băm bcrypt, không lưu mật khẩu gốc. |
| `gender` | VARCHAR(10) | None | Yes | NULL | Không bắt buộc. Dữ liệu mẫu dùng MALE, FEMALE; chưa có CHECK giới hạn giá trị. |
| `account_type_code` | CHAR(3) | FK | No | 'USR' | Tham chiếu account_types(account_type_code); ON DELETE RESTRICT, ON UPDATE CASCADE. |
| `created_at` | TIMESTAMP | None | No | CURRENT_TIMESTAMP | Thời điểm tạo tài khoản. |

## 3.3. `profiles`

Hồ sơ xem trong một tài khoản (thực thể yếu của users).

Ràng buộc UNIQUE nhiều cột: (user_id, profile_name).

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `user_id` | CHAR(7) | PK, FK, UK ghép | No | None | Tham chiếu users(user_id); ON DELETE CASCADE. |
| `profile_num` | SMALLINT | PK | No | None | Khóa riêng phần, > 0. Số hồ sơ của tài khoản không vượt plans.max_profiles của gói đang hiệu lực; phải có gói đang hiệu lực mới tạo được hồ sơ (trigger profiles_enforce_limit). |
| `profile_name` | VARCHAR(50) | UK ghép | No | None | Không trùng trong cùng một tài khoản (UNIQUE (user_id, profile_name)). |
| `is_kids` | BOOLEAN | None | No | false | TRUE nếu là hồ sơ trẻ em. Hồ sơ trẻ em chỉ xem được nội dung có age_rating ≤ 12 (trigger watch_history_enforce_access). |

## 3.4. `plans`

Gói dịch vụ: giá theo tháng, số hồ sơ tối đa và chất lượng video.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `plan_id` | SMALLINT | PK | No | IDENTITY | Mã gói, hệ thống tự sinh. |
| `plan_name` | VARCHAR(50) | UK | No | None | Tên gói, không trùng. |
| `monthly_price` | NUMERIC(10,0) | None | No | None | Giá theo tháng, đơn vị VND, ≥ 0. |
| `max_profiles` | SMALLINT | None | No | None | Số hồ sơ tối đa của một tài khoản dùng gói này, > 0. |
| `video_quality` | VARCHAR(10) | None | No | None | Chất lượng video: HD, FHD hoặc 4K; chưa có CHECK giới hạn giá trị. |
| `is_active` | BOOLEAN | None | No | true | FALSE khi gói ngừng bán; đăng ký cũ vẫn giữ tham chiếu. |

## 3.5. `subscriptions`

Một lần đăng ký gói của tài khoản, trong một khoảng ngày.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `subscription_id` | BIGINT | PK | No | IDENTITY | Mã đăng ký, hệ thống tự sinh. |
| `user_id` | CHAR(7) | FK | No | None | Tham chiếu users(user_id); ON DELETE RESTRICT để giữ lịch sử tài chính. |
| `plan_id` | SMALLINT | FK | No | None | Tham chiếu plans(plan_id); ON DELETE RESTRICT. |
| `start_date` | DATE | None | No | None | Ngày bắt đầu hiệu lực (tính cả ngày này). |
| `end_date` | DATE | None | No | None | Ngày hết hiệu lực (không tính ngày này), > start_date. Khoảng [start_date, end_date) không được trùng với đăng ký chưa hủy khác của cùng tài khoản (EXCLUDE subscription_no_overlap). |
| `subscription_status` | VARCHAR(10) | None | No | None | ACTIVE, EXPIRED hoặc CANCELLED. Đăng ký CANCELLED không tính vào ràng buộc trùng ngày. |

## 3.6. `payments`

Một giao dịch thanh toán cho một lần đăng ký.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `payment_id` | BIGINT | PK | No | IDENTITY | Mã giao dịch, hệ thống tự sinh. |
| `subscription_id` | BIGINT | FK | No | None | Tham chiếu subscriptions(subscription_id); ON DELETE RESTRICT. |
| `amount` | NUMERIC(10,0) | None | No | None | Số tiền thực trả, đơn vị VND, ≥ 0. Giữ nguyên khi giá gói thay đổi về sau. |
| `payment_method` | VARCHAR(20) | None | No | None | Phương thức thanh toán, ví dụ Thẻ ngân hàng, Ví MoMo. |
| `paid_at` | TIMESTAMP | None | No | CURRENT_TIMESTAMP | Thời điểm thanh toán. |
| `payment_status` | VARCHAR(10) | None | No | None | SUCCESS, FAILED hoặc REFUNDED. |

## 3.7. `titles`

Tác phẩm hiển thị trong danh mục: phim lẻ hoặc phim bộ (lớp cha).

Ràng buộc UNIQUE nhiều cột: (title_id, title_type).

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `title_id` | INTEGER | PK, UK ghép | No | IDENTITY | Mã tác phẩm, hệ thống tự sinh. Cặp (title_id, title_type) là UNIQUE để làm đích khóa ngoại của lớp con. |
| `title_type` | CHAR(2) | UK ghép | No | None | Bộ phân biệt lớp con: MV (phim lẻ) hoặc SR (phim bộ). Mỗi tác phẩm phải có đúng một dòng ở lớp con tương ứng (constraint trigger titles_require_subclass). |
| `title_name` | VARCHAR(200) | None | No | None | Tên tác phẩm; được phép trùng (ví dụ phim làm lại). |
| `description` | TEXT | None | Yes | NULL | Tóm tắt nội dung. |
| `release_year` | SMALLINT | None | Yes | NULL | Năm phát hành, ≥ 1888. Với phim lẻ, phải bằng năm của contents.release_date khi cả hai có giá trị (constraint trigger titles_check_movie_release_year). |
| `age_rating` | SMALLINT | None | No | 0 | Độ tuổi tối thiểu được xem, ≥ 0; 0 là mọi lứa tuổi. Hồ sơ trẻ em chỉ xem được nội dung có age_rating ≤ 12 (trigger watch_history_enforce_access). |

## 3.8. `series`

Phim bộ (lớp con của titles).

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `title_id` | INTEGER | PK, FK | No | None | Tham chiếu titles(title_id, title_type) cùng title_type; ON DELETE CASCADE. |
| `title_type` | CHAR(2) | FK | No | 'SR' | Luôn là SR (CHECK series_title_type). Cột kỹ thuật để khóa ngoại ghép chỉ trỏ tới tác phẩm loại SR. |
| `is_finished` | BOOLEAN | None | No | false | TRUE khi phim bộ đã phát hành hết. |

## 3.9. `seasons`

Mùa của một phim bộ (thực thể yếu của series).

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `title_id` | INTEGER | PK, FK | No | None | Tham chiếu series(title_id); ON DELETE CASCADE. |
| `season_num` | SMALLINT | PK | No | None | Khóa riêng phần: số thứ tự mùa, > 0. |
| `season_name` | VARCHAR(100) | None | Yes | NULL | Tên mùa, ví dụ Mùa 1. |
| `release_year` | SMALLINT | None | Yes | NULL | Năm phát hành mùa, ≥ 1888. |

## 3.10. `contents`

Video xem được: một phim lẻ hoặc một tập phim (lớp cha).

Ràng buộc UNIQUE nhiều cột: (content_id, content_type).

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `content_id` | BIGINT | PK, UK ghép | No | IDENTITY | Mã nội dung, hệ thống tự sinh. Cặp (content_id, content_type) là UNIQUE để làm đích khóa ngoại của lớp con. |
| `content_type` | CHAR(2) | UK ghép | No | None | Bộ phân biệt lớp con: MV (phim lẻ) hoặc EP (tập phim). Mỗi nội dung phải có đúng một dòng ở lớp con tương ứng (constraint trigger contents_require_subclass). |
| `duration_seconds` | INTEGER | None | No | None | Thời lượng video, đơn vị giây, > 0. |
| `video_url` | VARCHAR(500) | None | No | None | Đường dẫn tệp video. |
| `release_date` | DATE | None | Yes | NULL | Ngày phát hành. Với phim lẻ, năm của ngày này phải bằng titles.release_year khi cả hai có giá trị (constraint trigger contents_check_movie_release_year). |

## 3.11. `movies`

Phim lẻ: lớp con dùng chung của titles và contents.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `content_id` | BIGINT | PK, FK | No | None | Tham chiếu contents(content_id, content_type) cùng content_type; ON DELETE CASCADE. |
| `content_type` | CHAR(2) | FK | No | 'MV' | Luôn là MV (CHECK movie_content_type). Cột kỹ thuật cho khóa ngoại ghép. |
| `title_id` | INTEGER | FK, UK | No | None | Khóa ứng viên: mỗi phim lẻ ứng với đúng một tác phẩm. Tham chiếu titles(title_id, title_type) cùng title_type; ON DELETE CASCADE. |
| `title_type` | CHAR(2) | FK | No | 'MV' | Luôn là MV (CHECK movie_title_type). Cột kỹ thuật cho khóa ngoại ghép. |

## 3.12. `episodes`

Tập phim thuộc một mùa (lớp con của contents).

Ràng buộc UNIQUE nhiều cột: (title_id, season_num, episode_num).

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `content_id` | BIGINT | PK, FK | No | None | Tham chiếu contents(content_id, content_type) cùng content_type; ON DELETE CASCADE. |
| `content_type` | CHAR(2) | FK | No | 'EP' | Luôn là EP (CHECK episode_content_type). Cột kỹ thuật cho khóa ngoại ghép. |
| `title_id` | INTEGER | FK, UK ghép | No | None | Cùng season_num tham chiếu seasons(title_id, season_num); ON DELETE RESTRICT. |
| `season_num` | SMALLINT | FK, UK ghép | No | None | Cùng title_id tham chiếu seasons(title_id, season_num). |
| `episode_num` | SMALLINT | UK ghép | No | None | Số thứ tự tập, > 0. (title_id, season_num, episode_num) là khóa ứng viên: không trùng số tập trong một mùa. |
| `episode_name` | VARCHAR(200) | None | Yes | NULL | Tên tập. |

## 3.13. `genres`

Danh mục thể loại.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `genre_id` | SMALLINT | PK | No | IDENTITY | Mã thể loại, hệ thống tự sinh. |
| `genre_name` | VARCHAR(50) | UK | No | None | Tên thể loại, không trùng. |

## 3.14. `title_genres`

Quan hệ nhiều-nhiều giữa tác phẩm và thể loại.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `title_id` | INTEGER | PK, FK | No | None | Tham chiếu titles(title_id); ON DELETE CASCADE. |
| `genre_id` | SMALLINT | PK, FK | No | None | Tham chiếu genres(genre_id); ON DELETE RESTRICT. |

## 3.15. `people`

Người tham gia làm phim: đạo diễn, diễn viên.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `person_id` | INTEGER | PK | No | IDENTITY | Mã người, hệ thống tự sinh. |
| `full_name` | VARCHAR(100) | None | No | None | Họ tên; được phép trùng giữa hai người khác nhau. |
| `birth_date` | DATE | None | Yes | NULL | Ngày sinh. |
| `nationality` | VARCHAR(50) | None | Yes | NULL | Quốc tịch. |

## 3.16. `title_credits`

Vai trò của một người trong một tác phẩm (quan hệ nhiều-nhiều).

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `title_id` | INTEGER | PK, FK | No | None | Tham chiếu titles(title_id); ON DELETE CASCADE. |
| `person_id` | INTEGER | PK, FK | No | None | Tham chiếu people(person_id); ON DELETE RESTRICT. |
| `credit_role` | VARCHAR(10) | PK | No | None | DIRECTOR hoặc ACTOR. Thuộc khóa chính để một người vừa đạo diễn vừa đóng trong cùng tác phẩm. |
| `character_name` | VARCHAR(100) | None | Yes | NULL | Tên nhân vật, chỉ dùng cho ACTOR. Mỗi diễn viên có một nhân vật trong một tác phẩm. |

## 3.17. `watch_history`

Lịch sử xem: mỗi dòng là một lần một hồ sơ xem một nội dung.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `user_id` | CHAR(7) | PK, FK | No | None | Cùng profile_num tham chiếu profiles(user_id, profile_num); ON DELETE CASCADE. Tài khoản phải có đăng ký chưa hủy bao trùm ngày started_at (trigger watch_history_enforce_access). |
| `profile_num` | SMALLINT | PK, FK | No | None | Cùng user_id tham chiếu profiles(user_id, profile_num). |
| `content_id` | BIGINT | PK, FK | No | None | Tham chiếu contents(content_id); ON DELETE RESTRICT để giữ lịch sử. Hồ sơ trẻ em chỉ xem được nội dung có age_rating ≤ 12 (trigger watch_history_enforce_access). |
| `started_at` | TIMESTAMP | PK | No | None | Thời điểm bắt đầu xem; thuộc khóa chính để một hồ sơ xem lại cùng nội dung nhiều lần. |
| `ended_at` | TIMESTAMP | None | Yes | NULL | Thời điểm dừng xem, ≥ started_at (CHECK watch_time_order). NULL khi đang xem. |
| `position_seconds` | INTEGER | None | No | 0 | Vị trí đã xem tới, đơn vị giây, ≥ 0 và ≤ contents.duration_seconds (trigger watch_history_enforce_position). Xem hết khi đạt từ 90% thời lượng (tính trong view watch_progress). |

## 3.18. `watchlist_items`

Danh sách theo dõi: tác phẩm một hồ sơ lưu để xem sau.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `user_id` | CHAR(7) | PK, FK | No | None | Cùng profile_num tham chiếu profiles(user_id, profile_num); ON DELETE CASCADE. |
| `profile_num` | SMALLINT | PK, FK | No | None | Cùng user_id tham chiếu profiles(user_id, profile_num). |
| `title_id` | INTEGER | PK, FK | No | None | Tham chiếu titles(title_id); ON DELETE CASCADE. |
| `added_at` | TIMESTAMP | None | No | CURRENT_TIMESTAMP | Thời điểm thêm vào danh sách. |

## 3.19. Tổng hợp khóa ngoại

| Bảng | Cột | Tham chiếu | ON DELETE | ON UPDATE |
|---|---|---|---|---|
| `users` | (account_type_code) | `account_types` (account_type_code) | RESTRICT | CASCADE |
| `profiles` | (user_id) | `users` (user_id) | CASCADE | NO ACTION |
| `subscriptions` | (plan_id) | `plans` (plan_id) | RESTRICT | NO ACTION |
| `subscriptions` | (user_id) | `users` (user_id) | RESTRICT | NO ACTION |
| `payments` | (subscription_id) | `subscriptions` (subscription_id) | RESTRICT | NO ACTION |
| `series` | (title_id, title_type) | `titles` (title_id, title_type) | CASCADE | NO ACTION |
| `seasons` | (title_id) | `series` (title_id) | CASCADE | NO ACTION |
| `movies` | (content_id, content_type) | `contents` (content_id, content_type) | CASCADE | NO ACTION |
| `movies` | (title_id, title_type) | `titles` (title_id, title_type) | CASCADE | NO ACTION |
| `episodes` | (content_id, content_type) | `contents` (content_id, content_type) | CASCADE | NO ACTION |
| `episodes` | (title_id, season_num) | `seasons` (title_id, season_num) | RESTRICT | NO ACTION |
| `title_genres` | (genre_id) | `genres` (genre_id) | RESTRICT | NO ACTION |
| `title_genres` | (title_id) | `titles` (title_id) | CASCADE | NO ACTION |
| `title_credits` | (person_id) | `people` (person_id) | RESTRICT | NO ACTION |
| `title_credits` | (title_id) | `titles` (title_id) | CASCADE | NO ACTION |
| `watch_history` | (content_id) | `contents` (content_id) | RESTRICT | NO ACTION |
| `watch_history` | (user_id, profile_num) | `profiles` (user_id, profile_num) | CASCADE | NO ACTION |
| `watchlist_items` | (title_id) | `titles` (title_id) | CASCADE | NO ACTION |
| `watchlist_items` | (user_id, profile_num) | `profiles` (user_id, profile_num) | CASCADE | NO ACTION |
