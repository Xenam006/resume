-- ============================================================
--  Кейс 4. Источники данных для тайлов дашборда
-- ============================================================
--  Запросы считаются на схеме из кейса 3
--  (project-3-sql-analysis/sql/01_schema.sql + 02_seed.sql).
--  В BI-системе каждый запрос становится источником для тайла.
--  Выручка — по заказам со статусом 'delivered'.
-- ============================================================


-- --- KPI-строка: выручка за месяц, AOV, ARPU, повторные, отток ---

-- Выручка за последний месяц данных (North Star)
SELECT date_trunc('month', max(order_date))::date AS month,
       SUM(oi.quantity * oi.item_price)            AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status = 'delivered'
  AND date_trunc('month', o.order_date) = (
      SELECT date_trunc('month', max(order_date)) FROM orders);

-- Средний чек (AOV) и выручка на клиента (ARPU)
WITH order_totals AS (
    SELECT o.order_id, o.customer_id,
           SUM(oi.quantity * oi.item_price) AS order_total
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY o.order_id, o.customer_id
)
SELECT ROUND(AVG(order_total), 0)                               AS aov,
       ROUND(SUM(order_total) / COUNT(DISTINCT customer_id), 0) AS arpu
FROM order_totals;

-- Доля повторных покупателей
WITH per_customer AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM orders WHERE status = 'delivered'
    GROUP BY customer_id
)
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE orders > 1) / COUNT(*), 0) AS repeat_rate_pct
FROM per_customer;

-- Отток: нет заказов > 90 дней от последней даты
WITH last_order AS (
    SELECT customer_id, MAX(order_date) AS last_date
    FROM orders WHERE status = 'delivered'
    GROUP BY customer_id
),
ref AS (SELECT MAX(order_date) AS max_date FROM orders)
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE last_date < max_date - INTERVAL '90 days')
             / COUNT(*), 0) AS churn_rate_pct
FROM last_order, ref;


-- --- Тайл: выручка по категориям ---
SELECT p.category,
       SUM(oi.quantity * oi.item_price) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id  = o.order_id
JOIN products    p  ON p.product_id = oi.product_id
WHERE o.status = 'delivered'
GROUP BY p.category
ORDER BY revenue DESC;


-- --- Тайл: помесячная динамика выручки ---
SELECT date_trunc('month', o.order_date)::date AS month,
       SUM(oi.quantity * oi.item_price)        AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status = 'delivered'
GROUP BY 1
ORDER BY 1;


-- --- Тайл: выручка по городам (через домашний город клиента) ---
SELECT c.city,
       SUM(oi.quantity * oi.item_price)                                  AS revenue,
       ROUND(100.0 * SUM(oi.quantity * oi.item_price)
             / SUM(SUM(oi.quantity * oi.item_price)) OVER (), 1)         AS share_pct
FROM orders o
JOIN order_items oi ON oi.order_id  = o.order_id
JOIN customers   c  ON c.customer_id = o.customer_id
WHERE o.status = 'delivered'
GROUP BY c.city
ORDER BY revenue DESC;


-- --- Тайл: RFM-сегменты (доля клиентов по сегментам) ---
WITH ref AS (SELECT MAX(order_date) AS max_date FROM orders),
base AS (
    SELECT o.customer_id,
           (SELECT max_date FROM ref) - MAX(o.order_date) AS recency_days,
           COUNT(DISTINCT o.order_id)                     AS frequency,
           SUM(oi.quantity * oi.item_price)               AS monetary
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
),
scored AS (
    SELECT customer_id,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r,
           NTILE(5) OVER (ORDER BY frequency ASC)     AS f,
           NTILE(5) OVER (ORDER BY monetary ASC)      AS m
    FROM base
),
segmented AS (
    SELECT CASE
             WHEN r >= 4 AND f >= 4            THEN 'Чемпионы'
             WHEN r >= 3 AND f >= 3            THEN 'Лояльные'
             WHEN r <= 2 AND f >= 3            THEN 'Под угрозой'
             WHEN r >= 4 AND f <= 2            THEN 'Новички'
             ELSE 'Спящие'
           END AS segment
    FROM scored
)
SELECT segment,
       COUNT(*)                                        AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 0) AS share_pct
FROM segmented
GROUP BY segment
ORDER BY customers DESC;
