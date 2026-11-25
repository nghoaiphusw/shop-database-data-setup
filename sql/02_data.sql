\echo '>>> 02 data'
SET search_path = shop;
SET max_parallel_workers_per_gather = 0;   -- để setseed cho kết quả lặp lại được
SET work_mem = '256MB';
SET synchronous_commit = off;
SELECT setseed(0.42);

SELECT greatest(1000,  (1000000  * :scale)::int) AS n_customers,
       greatest(500,   (100000   * :scale)::int) AS n_products,
       greatest(5000,  (5000000  * :scale)::int) AS n_orders,
       greatest(2000,  (2000000  * :scale)::int) AS n_reviews,
       greatest(20000, (20000000 * :scale)::int) AS n_events,
       date_trunc('day', now()) AS anchor
\gset

-- ---------------------------------------------------------------- countries
\echo '... countries'
CREATE TEMP TABLE country_pick (code char(2), lo float8, hi float8, cities text[]);
INSERT INTO country_pick VALUES   -- phân phối lệch: VN 40%, US 15%, ...
 ('VN',0.00,0.40, ARRAY['Ha Noi','Ho Chi Minh','Da Nang','Hai Phong','Can Tho','Hue','Nha Trang']),
 ('US',0.40,0.55, ARRAY['New York','Los Angeles','Chicago','Houston','Seattle']),
 ('JP',0.55,0.63, ARRAY['Tokyo','Osaka','Nagoya','Fukuoka']),
 ('KR',0.63,0.69, ARRAY['Seoul','Busan','Incheon']),
 ('SG',0.69,0.73, ARRAY['Singapore']),
 ('TH',0.73,0.78, ARRAY['Bangkok','Chiang Mai','Phuket']),
 ('DE',0.78,0.83, ARRAY['Berlin','Munich','Hamburg']),
 ('FR',0.83,0.87, ARRAY['Paris','Lyon','Marseille']),
 ('GB',0.87,0.91, ARRAY['London','Manchester','Birmingham']),
 ('AU',0.91,0.94, ARRAY['Sydney','Melbourne','Brisbane']),
 ('IN',0.94,0.98, ARRAY['Mumbai','Delhi','Bangalore']),
 ('BR',0.98,1.01, ARRAY['Sao Paulo','Rio de Janeiro']);

INSERT INTO countries VALUES
 ('VN','Viet Nam','Asia'), ('US','United States','Americas'), ('JP','Japan','Asia'),
 ('KR','South Korea','Asia'), ('SG','Singapore','Asia'), ('TH','Thailand','Asia'),
 ('DE','Germany','Europe'), ('FR','France','Europe'), ('GB','United Kingdom','Europe'),
 ('AU','Australia','Oceania'), ('IN','India','Asia'), ('BR','Brazil','Americas');

-- ---------------------------------------------------------------- customers
\echo '... customers'
INSERT INTO customers (id, email, full_name, country_code, city, segment, birth_date, status, created_at)
SELECT s.id,
       lower(s.first_name) || '.' || lower(s.last_name) || s.id || '@' ||
         (ARRAY['gmail.com','yahoo.com','outlook.com','example.vn','company.com'])[1 + s.id % 5],
       s.first_name || ' ' || s.last_name,
       cp.code,
       cp.cities[1 + floor(s.r_city * cardinality(cp.cities))::int],
       CASE WHEN s.r_seg < 0.70 THEN 'regular' WHEN s.r_seg < 0.90 THEN 'silver'
            WHEN s.r_seg < 0.98 THEN 'gold' ELSE 'vip' END,
       CASE WHEN s.r_bd < 0.10 THEN NULL ELSE date '1955-01-01' + floor(s.r_bd * 18000)::int END,
       CASE WHEN s.r_st < 0.92 THEN 'active' WHEN s.r_st < 0.99 THEN 'inactive' ELSE 'banned' END,
       :'anchor'::timestamptz - power(s.r_ts, 1.7) * interval '1825 days'   -- lệch về gần đây
FROM (
  SELECT g AS id,
         n.f[1 + floor(random() * cardinality(n.f))::int] AS first_name,
         n.l[1 + floor(power(random(), 2) * cardinality(n.l))::int] AS last_name,
         random() AS r_country, random() AS r_city, random() AS r_seg,
         random() AS r_bd, random() AS r_st, random() AS r_ts
  FROM generate_series(1, :n_customers) g,
       (SELECT ARRAY['An','Binh','Chi','Dung','Giang','Ha','Hieu','Hoa','Hung','Khanh','Lan','Linh',
                     'Long','Mai','Minh','Nam','Ngoc','Phuong','Quang','Son','Thao','Trang','Tuan','Vy',
                     'John','Emma','Liam','Olivia','Noah','Ava','Yuki','Hana','Min','Ji','Arjun','Lucas'] AS f,
               ARRAY['Nguyen','Tran','Le','Pham','Hoang','Phan','Vu','Dang','Bui','Do','Ho','Ngo',
                     'Smith','Johnson','Brown','Tanaka','Sato','Kim','Lee','Park','Muller','Martin',
                     'Sharma','Silva'] AS l) n
) s
JOIN country_pick cp ON s.r_country >= cp.lo AND s.r_country < cp.hi
ORDER BY s.id;

-- ---------------------------------------------------------------- categories (10 > 50 > 200)
\echo '... categories'
INSERT INTO categories
SELECT r, NULL, (ARRAY['Electronics','Fashion','Home','Beauty','Sports','Books',
                       'Toys','Grocery','Automotive','Health'])[r]
FROM generate_series(1, 10) r;

INSERT INTO categories
SELECT 10 + (r - 1) * 5 + c, r, (SELECT name FROM categories WHERE id = r) || ' > Group ' || c
FROM generate_series(1, 10) r, generate_series(1, 5) c;

INSERT INTO categories
SELECT 60 + (p - 11) * 4 + l, p, (SELECT name FROM categories WHERE id = p) || ' > Type ' || l
FROM generate_series(11, 60) p, generate_series(1, 4) l;

-- ---------------------------------------------------------------- products (chỉ ở category lá 61..260)
\echo '... products'
INSERT INTO products (id, category_id, sku, name, brand, price, is_active, attributes, created_at)
SELECT s.id,
       61 + floor(power(s.r_cat, 1.3) * 200)::int,
       'SKU-' || lpad(s.id::text, 8, '0'),
       s.brand || ' ' || s.adj || ' ' || s.noun || ' ' || s.id,
       s.brand,
       round((4.99 + exp(s.r_price * 8))::numeric, 2),          -- phân phối giá lệch phải
       s.r_active < 0.95,
       jsonb_strip_nulls(jsonb_build_object(
         'color', s.color,
         'weight_g', 50 + floor(s.r_w * 5000)::int,
         'warranty_months', CASE WHEN s.r_w < 0.3 THEN 12 WHEN s.r_w < 0.4 THEN 24 END,
         'tags', jsonb_build_array(s.tag1, s.tag2))),
       :'anchor'::timestamptz - s.r_ts * interval '1825 days'
FROM (
  SELECT g AS id,
         a.brands[1 + floor(power(random(), 1.5) * cardinality(a.brands))::int] AS brand,
         a.adjs[1 + floor(random() * cardinality(a.adjs))::int]   AS adj,
         a.nouns[1 + floor(random() * cardinality(a.nouns))::int] AS noun,
         a.colors[1 + floor(random() * cardinality(a.colors))::int] AS color,
         a.tags[1 + floor(random() * cardinality(a.tags))::int] AS tag1,
         a.tags[1 + floor(random() * cardinality(a.tags))::int] AS tag2,
         random() AS r_cat, random() AS r_price, random() AS r_active,
         random() AS r_w, random() AS r_ts
  FROM generate_series(1, :n_products) g,
       (SELECT ARRAY['Acme','Zenith','Nova','Orbit','Lotus','Sakura','Titan','Vertex','Aurora','Bamboo',
                     'Cobalt','Delta','Echo','Falcon','Granite','Helix','Iris','Jade','Krypton','Lumen'] AS brands,
               ARRAY['Pro','Mini','Max','Ultra','Classic','Smart','Eco','Lite','Plus','Prime'] AS adjs,
               ARRAY['Phone','Laptop','Shirt','Lamp','Chair','Cream','Ball','Novel','Puzzle','Coffee',
                     'Tyre','Vitamin','Watch','Bag','Shoes','Kettle'] AS nouns,
               ARRAY['black','white','red','blue','green','silver','gold','pink'] AS colors,
               ARRAY['new','sale','bestseller','eco','imported','limited','gift','premium'] AS tags) a
) s
ORDER BY s.id;

-- ---------------------------------------------------------------- orders (khung, id tăng theo thời gian)
\echo '... orders (staging)'
CREATE TEMP TABLE tmp_orders AS
SELECT row_number() OVER (ORDER BY x.created_at) AS id, x.*
FROM (
  SELECT c.id AS customer_id,
         CASE WHEN o.r_ctry < 0.97 THEN c.country_code
              ELSE ((ARRAY['VN','US','JP','SG','DE'])[1 + floor(o.r_ctry2 * 5)::int])::char(2) END AS shipping_country,
         c.created_at + o.r_ts * (:'anchor'::timestamptz - c.created_at) AS created_at,
         least(10, 1 + floor(-ln(1 - o.r_items) * 1.5)::int) AS n_items
  FROM (
    SELECT g,
           -- khách hàng lệch kiểu power-law (một nhóm nhỏ mua rất nhiều), xáo id bằng số nguyên tố
           (floor(power(random(), 2) * :n_customers)::bigint * 104729) % :n_customers + 1 AS customer_id,
           random() AS r_ts, random() AS r_ctry, random() AS r_ctry2, random() AS r_items
    FROM generate_series(1, :n_orders) g
  ) o
  JOIN customers c ON c.id = o.customer_id
) x;

-- ---------------------------------------------------------------- order_items
\echo '... order_items'
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price, discount_pct)
SELECT li.order_id, li.line_no, p.id, li.quantity, p.price, li.discount_pct
FROM (
  SELECT o.id AS order_id, l AS line_no,
         -- sản phẩm "hot" chiếm phần lớn lượt mua
         (floor(power(random(), 2.5) * :n_products)::bigint * 7919) % :n_products + 1 AS product_id,
         1 + floor(power(random(), 3) * 5)::int AS quantity,
         CASE WHEN random() < 0.7 THEN 0
              ELSE (ARRAY[5,10,15,20,30])[1 + floor(random() * 5)::int] END AS discount_pct
  FROM tmp_orders o
  CROSS JOIN LATERAL generate_series(1, o.n_items) l
) li
JOIN products p ON p.id = li.product_id
ORDER BY li.order_id, li.line_no;

-- ---------------------------------------------------------------- orders
\echo '... orders'
INSERT INTO orders (id, customer_id, status, payment_method, shipping_country, item_count,
                    total_amount, created_at, shipped_at, delivered_at)
SELECT id, customer_id, status, payment_method, shipping_country, item_count, total_amount, created_at,
       CASE WHEN status IN ('shipped','delivered','returned') THEN least(ship_ts, :'anchor'::timestamptz) END,
       CASE WHEN status IN ('delivered','returned')
            THEN least(ship_ts + (1 + r_dl * 6) * interval '1 day', :'anchor'::timestamptz) END
FROM (
  SELECT o.*,
         o.created_at + (2 + o.r_ship * 70) * interval '1 hour' AS ship_ts,
         CASE
           WHEN o.created_at > :'anchor'::timestamptz - interval '2 days'
             THEN CASE WHEN o.r_st < 0.5 THEN 'pending' ELSE 'paid' END
           WHEN o.created_at > :'anchor'::timestamptz - interval '7 days'
             THEN CASE WHEN o.r_st < 0.6 THEN 'shipped' WHEN o.r_st < 0.9 THEN 'delivered' ELSE 'cancelled' END
           ELSE CASE WHEN o.r_st < 0.90 THEN 'delivered' WHEN o.r_st < 0.97 THEN 'cancelled' ELSE 'returned' END
         END AS status,
         CASE WHEN o.r_pay < 0.45 THEN 'card' WHEN o.r_pay < 0.75 THEN 'cod'
              WHEN o.r_pay < 0.95 THEN 'ewallet' ELSE 'bank_transfer' END AS payment_method
  FROM (
    SELECT t.id, t.customer_id, t.shipping_country, t.created_at,
           a.item_count, a.total_amount,
           random() AS r_st, random() AS r_pay, random() AS r_ship, random() AS r_dl
    FROM tmp_orders t
    JOIN (SELECT order_id, count(*)::int AS item_count,
                 round(sum(quantity * unit_price * (1 - discount_pct / 100)), 2) AS total_amount
          FROM order_items GROUP BY order_id) a ON a.order_id = t.id
  ) o
) f
ORDER BY id;

DROP TABLE tmp_orders;

-- ---------------------------------------------------------------- reviews
\echo '... reviews'
INSERT INTO reviews (id, product_id, customer_id, rating, title, body, created_at)
SELECT s.id, s.product_id, s.customer_id, s.rating,
       CASE WHEN s.r_title < 0.3 THEN NULL
            WHEN s.rating >= 4 THEN 'Great product' WHEN s.rating = 3 THEN 'It is okay'
            ELSE 'Disappointed' END,
       (SELECT string_agg(CASE WHEN s.rating >= 4 THEN ph.good[1 + floor(random() * cardinality(ph.good))::int]
                               WHEN s.rating <= 2 THEN ph.bad[1 + floor(random() * cardinality(ph.bad))::int]
                               ELSE ph.neutral[1 + floor(random() * cardinality(ph.neutral))::int] END, ' ' ORDER BY i)
        FROM generate_series(1, 2 + s.id % 6) i),
       s.created_at
FROM (
  SELECT g AS id,
         (floor(power(random(), 2.5) * :n_products)::bigint * 7919) % :n_products + 1 AS product_id,
         (floor(power(random(), 2) * :n_customers)::bigint * 104729) % :n_customers + 1 AS customer_id,
         CASE WHEN r < 0.45 THEN 5 WHEN r < 0.70 THEN 4 WHEN r < 0.82 THEN 3
              WHEN r < 0.90 THEN 2 ELSE 1 END::smallint AS rating,
         random() AS r_title,
         :'anchor'::timestamptz - power(random(), 1.5) * interval '1825 days' AS created_at
  FROM (SELECT g, random() AS r FROM generate_series(1, :n_reviews) g) x
) s,
(SELECT ARRAY['Excellent quality and fast delivery.','Works perfectly, highly recommended.',
              'Great value for the price.','Battery life is amazing.','Packaging was very careful.',
              'Exactly as described in the listing.','My family loves it.','Will definitely buy again.'] AS good,
        ARRAY['Arrived broken and support was slow.','Stopped working after one week.',
              'Much smaller than the pictures.','Terrible quality, requested a refund.',
              'Delivery was late by ten days.','The color is completely different.'] AS bad,
        ARRAY['Average product for the price.','Delivery took a while.','It does the job.',
              'Nothing special but acceptable.','Size runs a bit large.'] AS neutral) ph;

-- ---------------------------------------------------------------- events (theo thời gian, 180 ngày gần nhất)
\echo '... events (lâu nhất)'
INSERT INTO events (id, customer_id, session_id, event_type, product_id, page, created_at)
SELECT e.id,
       CASE WHEN e.session_id % 100 < 35 THEN NULL
            ELSE (e.session_id * 104729) % :n_customers + 1 END,
       e.session_id,
       e.event_type,
       CASE WHEN e.event_type IN ('product_view','add_to_cart','purchase') THEN e.product_id END,
       CASE e.event_type
         WHEN 'page_view'    THEN e.page
         WHEN 'search'       THEN '/search?q=' || e.term
         WHEN 'checkout'     THEN '/checkout'
         WHEN 'purchase'     THEN '/checkout/success'
         ELSE '/p/' || e.product_id END,
       e.created_at
FROM (
  SELECT g AS id,
         (g / 7)::bigint AS session_id,
         CASE WHEN r < 0.60 THEN 'page_view' WHEN r < 0.85 THEN 'product_view'
              WHEN r < 0.93 THEN 'add_to_cart' WHEN r < 0.98 THEN 'search'
              WHEN r < 0.995 THEN 'checkout' ELSE 'purchase' END AS event_type,
         (floor(power(random(), 2.5) * :n_products)::bigint * 7919) % :n_products + 1 AS product_id,
         a.pages[1 + floor(random() * cardinality(a.pages))::int] AS page,
         a.terms[1 + floor(random() * cardinality(a.terms))::int] AS term,
         :'anchor'::timestamptz - interval '180 days'
           + (g::float8 / :n_events) * interval '180 days'
           + random() * interval '60 seconds' AS created_at
  FROM (SELECT g, random() AS r FROM generate_series(1, :n_events) g) x,
       (SELECT ARRAY['/','/home','/deals','/cart','/account','/help','/category'] AS pages,
               ARRAY['phone','laptop','shoes','coffee','gift','watch','lamp'] AS terms) a
) e;
