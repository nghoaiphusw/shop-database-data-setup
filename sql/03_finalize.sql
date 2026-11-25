\echo '>>> 03 finalize'
SET search_path = shop;
SET maintenance_work_mem = '512MB';

-- Ràng buộc thêm SAU khi nạp dữ liệu (nhanh hơn nhiều so với kiểm tra từng dòng).
-- UNIQUE tự tạo index; FOREIGN KEY thì KHÔNG -> cột khóa ngoại chưa có index (cố ý).
ALTER TABLE customers   ADD CONSTRAINT customers_email_key UNIQUE (email);
ALTER TABLE products    ADD CONSTRAINT products_sku_key    UNIQUE (sku);
ALTER TABLE customers   ADD FOREIGN KEY (country_code) REFERENCES countries(code);
ALTER TABLE products    ADD FOREIGN KEY (category_id)  REFERENCES categories(id);
ALTER TABLE orders      ADD FOREIGN KEY (customer_id)  REFERENCES customers(id);
ALTER TABLE order_items ADD FOREIGN KEY (order_id)     REFERENCES orders(id);
ALTER TABLE order_items ADD FOREIGN KEY (product_id)   REFERENCES products(id);
ALTER TABLE reviews     ADD FOREIGN KEY (product_id)   REFERENCES products(id);
ALTER TABLE reviews     ADD FOREIGN KEY (customer_id)  REFERENCES customers(id);
ALTER TABLE events      ADD FOREIGN KEY (customer_id)  REFERENCES customers(id);
ALTER TABLE events      ADD FOREIGN KEY (product_id)   REFERENCES products(id);

\echo '... vacuum analyze'
VACUUM (ANALYZE) countries, categories, customers, products, orders, order_items, reviews, events;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA public;
SELECT format('ALTER DATABASE %I SET search_path = shop, public', current_database()) \gexec

\echo '>>> Xong. Kích thước các bảng:'
SELECT c.relname                                   AS "table",
       to_char(c.reltuples::bigint, 'FM999,999,999') AS "rows (est)",
       pg_size_pretty(pg_table_size(c.oid))         AS "data",
       pg_size_pretty(pg_indexes_size(c.oid))       AS "indexes"
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'shop' AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;
