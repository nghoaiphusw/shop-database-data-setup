\echo '>>> 01 schema'
DROP SCHEMA IF EXISTS shop CASCADE;
CREATE SCHEMA shop;
SET search_path = shop;

-- Cố ý: chỉ có PRIMARY KEY. Không có index trên khóa ngoại, ngày tháng, status...
-- để bạn tự đo, tự thêm index ở giai đoạn sau.

CREATE TABLE countries (
  code   char(2) PRIMARY KEY,
  name   text NOT NULL,
  region text NOT NULL
);

CREATE TABLE categories (            -- cây 3 cấp: dùng cho recursive CTE
  id        int PRIMARY KEY,
  parent_id int REFERENCES categories(id),
  name      text NOT NULL
);

CREATE TABLE customers (
  id           bigint PRIMARY KEY,
  email        text NOT NULL,
  full_name    text NOT NULL,
  country_code char(2) NOT NULL,
  city         text NOT NULL,        -- tương quan với country_code
  segment      text NOT NULL CHECK (segment IN ('regular','silver','gold','vip')),
  birth_date   date,                 -- ~10% NULL
  status       text NOT NULL CHECK (status IN ('active','inactive','banned')),
  created_at   timestamptz NOT NULL
);

CREATE TABLE products (
  id          bigint PRIMARY KEY,
  category_id int NOT NULL,
  sku         text NOT NULL,
  name        text NOT NULL,
  brand       text NOT NULL,
  price       numeric(12,2) NOT NULL CHECK (price >= 0),
  is_active   boolean NOT NULL,
  attributes  jsonb NOT NULL,
  created_at  timestamptz NOT NULL
);

CREATE TABLE orders (
  id               bigint PRIMARY KEY, -- tăng dần theo created_at (như hệ thống thật)
  customer_id      bigint NOT NULL,
  status           text NOT NULL CHECK (status IN ('pending','paid','shipped','delivered','cancelled','returned')),
  payment_method   text NOT NULL,
  shipping_country char(2) NOT NULL,
  item_count       int NOT NULL,
  total_amount     numeric(14,2) NOT NULL,
  created_at       timestamptz NOT NULL,
  shipped_at       timestamptz,
  delivered_at     timestamptz
);

CREATE TABLE order_items (
  order_id     bigint NOT NULL,
  line_no      smallint NOT NULL,
  product_id   bigint NOT NULL,
  quantity     int NOT NULL CHECK (quantity > 0),
  unit_price   numeric(12,2) NOT NULL,
  discount_pct numeric(5,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (order_id, line_no)
);

CREATE TABLE reviews (
  id          bigint PRIMARY KEY,
  product_id  bigint NOT NULL,
  customer_id bigint NOT NULL,
  rating      smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title       text,                  -- ~30% NULL
  body        text NOT NULL,         -- dùng cho full-text search
  created_at  timestamptz NOT NULL
);

CREATE TABLE events (                -- bảng lớn nhất, ghi theo thứ tự thời gian
  id          bigint PRIMARY KEY,
  customer_id bigint,                -- NULL = khách vãng lai (~35%)
  session_id  bigint NOT NULL,
  event_type  text NOT NULL,
  product_id  bigint,
  page        text NOT NULL,
  created_at  timestamptz NOT NULL
);
