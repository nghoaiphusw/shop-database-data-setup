# Database học SQL & tối ưu PostgreSQL

Một database thương mại điện tử (`shop`) với hàng chục triệu dòng, được sinh bằng SQL thuần (`generate_series`). Dữ liệu được thiết kế để giống thực tế ở những điểm làm khó optimizer.

## Cài đặt

```bash
docker compose up -d
docker compose exec db psql -U postgres -d shop -v scale=1 -f /sql/setup.sql
docker compose exec db psql -U postgres -d shop      # bắt đầu học
```

| scale | Số dòng (orders / events) | Dung lượng | Thời gian nạp | Dùng khi |
|---|---|---|---|---|
| 0.1 | 500K / 2M | ~0.4 GB | < 30 giây | Học cú pháp SQL |
| 1 | 5M / 20M | ~4–5 GB | vài phút | **Khuyến nghị** – lớn hơn `shared_buffers` |
| 3 | 15M / 60M | ~13 GB | 10–20 phút | Học I/O, dữ liệu lớn hơn RAM |

Chạy lại `setup.sql` sẽ xoá và tạo lại toàn bộ schema `shop`. Kết quả lặp lại được, vì dùng `setseed`.

## Schema

```
countries ─< customers ─< orders ─< order_items >─ products >─ categories (cây 3 cấp)
                 │                                     │
                 ├──────────────< reviews >────────────┤
                 └──────────────< events  >────────────┘   (customer_id có thể NULL)
```

## Những "bẫy" được cài sẵn có chủ đích

| Đặc điểm | Dùng để học |
|---|---|
| Chỉ có PK và UNIQUE; **khóa ngoại không có index** | Tự đo trước và sau khi thêm index |
| Dữ liệu lệch: VN chiếm 40% khách; một nhóm nhỏ khách và sản phẩm "hot" chiếm phần lớn đơn | Selectivity, MCV, kế hoạch khác nhau theo tham số |
| `city` phụ thuộc `country_code` | Ước lượng sai khi lọc nhiều cột → `CREATE STATISTICS` |
| `orders.id` tăng theo `created_at`; `events` ghi theo thời gian | Correlation vật lý, BRIN, range scan |
| 90% đơn `delivered`, rất ít `pending`/`paid` | Partial index |
| NULL ở `birth_date`, `shipped_at`, `events.customer_id`, `reviews.title` | Logic ba giá trị, bẫy `NOT IN` |
| `products.attributes` (jsonb), `reviews.body` (văn bản) | GIN, full-text search |
| `orders.total_amount` là dữ liệu phi chuẩn hóa | Kiểm tra tính nhất quán, đánh đổi khi thiết kế |

## Quy trình đo chuẩn

```sql
\timing on
SELECT pg_stat_statements_reset();
EXPLAIN (ANALYZE, BUFFERS) <câu truy vấn>;   -- chạy 2–3 lần, so sánh lần đầu (cache lạnh) và các lần sau
SELECT query, calls, mean_exec_time, shared_blks_hit, shared_blks_read
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;
```

Khi đọc kế hoạch, luôn so sánh **rows ước tính** với **rows thực tế**, và xem **Buffers** ở node tốn kém nhất.

---

## Giai đoạn 1 — Câu lệnh SQL

1. Đếm số khách hàng theo từng quốc gia và tỉ lệ phần trăm (dùng window function `sum() OVER ()`).
2. Liệt kê 10 sản phẩm có doanh thu cao nhất trong 30 ngày gần nhất, chỉ tính đơn `delivered`.
3. Doanh thu theo tháng trong 12 tháng gần nhất, kèm tăng trưởng so với tháng trước (`lag`).
4. Với mỗi quốc gia, tìm 3 khách chi tiêu nhiều nhất (`row_number` / `dense_rank` theo partition).
5. Tìm khách đã đăng ký nhưng chưa từng đặt đơn. Viết bằng `LEFT JOIN … IS NULL`, `NOT EXISTS` và `NOT IN`.
6. Liệt kê toàn bộ cây danh mục kèm đường dẫn đầy đủ và độ sâu (`WITH RECURSIVE`).
7. Doanh thu theo danh mục **gốc**: kết hợp recursive CTE với join `order_items`.
8. Tỉ lệ chuyển đổi theo phễu `product_view → add_to_cart → checkout → purchase` trong `events`.
9. Cohort: khách đăng ký theo tháng, bao nhiêu % quay lại mua ở tháng thứ 1, 2, 3.
10. Đối soát `orders.total_amount` với tổng tính lại từ `order_items`.
11. Lọc sản phẩm theo `attributes`: màu `black`, có `warranty_months`, tag chứa `sale` (`->>`, `?`, `@>`).
12. Tìm review chứa cả "battery" và "amazing" bằng `to_tsvector` / `to_tsquery`. So sánh với `ILIKE`.
13. Viết câu `UPDATE … FROM` và `INSERT … ON CONFLICT` trong một transaction, sau đó `ROLLBACK`.

## Giai đoạn 2 — Tối ưu câu lệnh (chưa thêm index)

Mục tiêu: hiểu rằng **cách viết** câu lệnh thay đổi kế hoạch thực thi, ngay cả khi chưa có index.

1. Ở bài 5, so sánh ba cách viết. Thử `customer_id NOT IN (SELECT customer_id FROM events)` và giải thích vì sao kết quả là 0 dòng.
2. "Tổng chi tiêu của mỗi khách": so sánh subquery tương quan trong `SELECT` với `JOIN + GROUP BY`. Đọc `SubPlan` trong EXPLAIN.
3. `COUNT(DISTINCT customer_id)` so với `SELECT count(*) FROM (SELECT DISTINCT …)`.
4. Chạy bài 3 với `SET work_mem = '1MB'` rồi `'256MB'`. Quan sát `Sort Method: external merge` và số `Batches` của Hash.
5. Lọc `WHERE country_code = 'VN' AND city = 'Ha Noi'`. So sánh rows ước tính với thực tế, chạy `CREATE STATISTICS … (dependencies) ON country_code, city FROM customers; ANALYZE customers;` rồi so sánh lại.
6. CTE: so sánh `WITH x AS MATERIALIZED (…)` với `NOT MATERIALIZED` khi có điều kiện lọc bên ngoài.
7. Phân trang: `ORDER BY id OFFSET 4000000 LIMIT 20` so với keyset `WHERE id > :last ORDER BY id LIMIT 20`.
8. Điều kiện `OR` trên hai cột khác nhau, so với viết lại bằng `UNION ALL`.
9. Chỉ chọn các cột cần thiết thay cho `SELECT *` trên `reviews`. Xem độ rộng dòng (`width`) trong kế hoạch.

## Giai đoạn 3 — Index (sau này)

1. Thêm index cho `orders.customer_id` và `order_items.product_id`. Đo lại các bài ở giai đoạn 2.
2. Index ghép `(customer_id, created_at)` và `(created_at, customer_id)`: truy vấn nào dùng được index nào, vì sao?
3. Truy vấn `WHERE created_at::date = '…'` có dùng được index trên `created_at` không? Viết lại thành điều kiện khoảng.
4. Partial index `WHERE status IN ('pending','paid')`. So sánh kích thước với index đầy đủ.
5. Covering index `INCLUDE (total_amount)` → `Index Only Scan`. Quan sát `Heap Fetches` trước và sau `VACUUM`.
6. Expression index `lower(email)` cho tìm kiếm không phân biệt hoa thường.
7. Trên `events.created_at`: so sánh BRIN với B-tree về kích thước và tốc độ.
8. GIN cho `products.attributes` (`jsonb_path_ops` so với mặc định) và cho `to_tsvector(body)`.
9. Đo chi phí ghi: thời gian `INSERT` 100K dòng vào `orders` khi có 0, 3 và 8 index.
10. Tìm index không được dùng bằng `pg_stat_user_indexes` (`idx_scan = 0`).

## Mẹo

- Không chạy `EXPLAIN ANALYZE` trên `UPDATE`/`DELETE` ngoài transaction. Hãy dùng `BEGIN; EXPLAIN ANALYZE …; ROLLBACK;`.
- Làm mới thống kê sau khi thay đổi dữ liệu lớn: `ANALYZE tên_bảng;`.
- Xem các tham số đang dùng: `SHOW work_mem;`, `SHOW random_page_cost;`.
- Giao diện đồ hoạ: kết nối DBeaver hoặc pgAdmin tới `localhost:5432` (user/password: `postgres`/`postgres`).
