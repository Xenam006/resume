-- ============================================================
--  Кейс 3. SQL-анализ продаж маркетплейса
--  Файл 2/3: генерация синтетических данных (PostgreSQL)
-- ============================================================
--  Данные генерируются процедурно через generate_series, поэтому
--  скрипт самодостаточен и не требует внешних файлов.
--  setseed фиксирует случайность — результат воспроизводим.
-- ============================================================

SELECT setseed(0.42);

-- --- Клиенты: 2000 человек, регистрация в течение ~2 лет ---
INSERT INTO customers (city, signup_date)
SELECT
    (ARRAY['Москва','Санкт-Петербург','Новосибирск','Екатеринбург',
           'Казань','Нижний Новгород','Краснодар','Самара'])[1 + floor(random()*8)::int],
    DATE '2023-01-01' + (floor(random()*700))::int
FROM generate_series(1, 2000);

-- --- Товары: 300 позиций в 10 категориях ---
INSERT INTO products (category, price)
SELECT
    (ARRAY['Электроника','Одежда','Дом и сад','Красота','Спорт',
           'Детские товары','Книги','Авто','Продукты','Зоотовары'])[1 + floor(random()*10)::int],
    round((50 + random()*9950)::numeric, 2)
FROM generate_series(1, 300);

-- --- Заказы: у каждого клиента 1..8 заказов после даты регистрации ---
INSERT INTO orders (customer_id, order_date, status)
SELECT
    c.customer_id,
    c.signup_date + (floor(random() * GREATEST(1, DATE '2024-12-31' - c.signup_date)))::int,
    -- ~67% delivered, остальное cancelled / returned
    (ARRAY['delivered','delivered','delivered','delivered',
           'cancelled','returned'])[1 + floor(random()*6)::int]
FROM customers c
CROSS JOIN LATERAL generate_series(1, (1 + floor(random()*8)::int)) AS g;

-- --- Позиции заказа: 1..5 уникальных товаров на заказ ---
INSERT INTO order_items (order_id, product_id, quantity, item_price)
SELECT
    o.order_id,
    p.product_id,
    1 + floor(random()*3)::int,
    p.price
FROM orders o
CROSS JOIN LATERAL (
    SELECT product_id, price
    FROM products
    ORDER BY random()
    LIMIT (1 + floor(random()*5)::int)
) AS p;

-- --- Проверка объёмов ---
SELECT 'customers'   AS table, COUNT(*) FROM customers
UNION ALL SELECT 'products',   COUNT(*) FROM products
UNION ALL SELECT 'orders',     COUNT(*) FROM orders
UNION ALL SELECT 'order_items',COUNT(*) FROM order_items;
