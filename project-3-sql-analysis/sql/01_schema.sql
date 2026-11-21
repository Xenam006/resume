-- ============================================================
--  Кейс 3. SQL-анализ продаж маркетплейса
--  Файл 1/3: схема данных (PostgreSQL)
-- ============================================================
--  Модель: клиенты -> заказы -> позиции заказа -> товары
--  Запускать по порядку: 01_schema.sql -> 02_seed.sql -> 03_analysis.sql
-- ============================================================

DROP TABLE IF EXISTS order_items, orders, products, customers CASCADE;

-- Клиенты маркетплейса
CREATE TABLE customers (
    customer_id  SERIAL PRIMARY KEY,
    city         TEXT NOT NULL,
    signup_date  DATE NOT NULL
);

-- Товары с категорией и ценой
CREATE TABLE products (
    product_id   SERIAL PRIMARY KEY,
    category     TEXT NOT NULL,
    price        NUMERIC(10,2) NOT NULL CHECK (price > 0)
);

-- Заказы. status: delivered / cancelled / returned
CREATE TABLE orders (
    order_id     SERIAL PRIMARY KEY,
    customer_id  INT  NOT NULL REFERENCES customers(customer_id),
    order_date   DATE NOT NULL,
    status       TEXT NOT NULL
);

-- Позиции заказа (строки чека). item_price — цена на момент покупки
CREATE TABLE order_items (
    order_id     INT NOT NULL REFERENCES orders(order_id),
    product_id   INT NOT NULL REFERENCES products(product_id),
    quantity     INT NOT NULL CHECK (quantity > 0),
    item_price   NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, product_id)
);

-- Индексы под аналитические запросы
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_date     ON orders(order_date);
CREATE INDEX idx_items_product   ON order_items(product_id);
