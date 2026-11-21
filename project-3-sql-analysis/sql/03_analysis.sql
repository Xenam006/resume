-- ============================================================
--  Кейс 3. SQL-анализ продаж маркетплейса
--  Файл 3/3: аналитические запросы с бизнес-вопросами
-- ============================================================
--  Выручка считается только по заказам со статусом 'delivered'
--  (отменённые и возвращённые не приносят выручки).
-- ============================================================


-- ------------------------------------------------------------
-- Q1. Какие категории приносят больше всего выручки?
--     (JOIN трёх таблиц + агрегация)
-- ------------------------------------------------------------
SELECT
    p.category,
    COUNT(DISTINCT o.order_id)             AS orders,
    SUM(oi.quantity * oi.item_price)       AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id   = o.order_id
JOIN products    p  ON p.product_id  = oi.product_id
WHERE o.status = 'delivered'
GROUP BY p.category
ORDER BY revenue DESC;


-- ------------------------------------------------------------
-- Q2. Доля каждой категории в общей выручке и ранг
--     (оконная функция SUM() OVER () + RANK())
-- ------------------------------------------------------------
SELECT
    category,
    revenue,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 1) AS revenue_share_pct,
    RANK() OVER (ORDER BY revenue DESC)              AS rank
FROM (
    SELECT p.category, SUM(oi.quantity * oi.item_price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id  = o.order_id
    JOIN products    p  ON p.product_id = oi.product_id
    WHERE o.status = 'delivered'
    GROUP BY p.category
) t
ORDER BY revenue DESC;


-- ------------------------------------------------------------
-- Q3. Помесячная динамика выручки и прирост к прошлому месяцу
--     (CTE + LAG() для расчёта month-over-month)
-- ------------------------------------------------------------
WITH monthly AS (
    SELECT
        date_trunc('month', o.order_date)::date AS month,
        SUM(oi.quantity * oi.item_price)        AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY 1
)
SELECT
    month,
    revenue,
    revenue - LAG(revenue) OVER (ORDER BY month) AS mom_change,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
          / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 1) AS mom_pct
FROM monthly
ORDER BY month;


-- ------------------------------------------------------------
-- Q4. Какая доля клиентов делает повторные покупки?
--     (разовые vs повторные покупатели)
-- ------------------------------------------------------------
WITH per_customer AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM orders
    WHERE status = 'delivered'
    GROUP BY customer_id
)
SELECT
    COUNT(*) FILTER (WHERE orders = 1)  AS one_time_buyers,
    COUNT(*) FILTER (WHERE orders > 1)  AS repeat_buyers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE orders > 1) / COUNT(*), 1) AS repeat_rate_pct
FROM per_customer;


-- ------------------------------------------------------------
-- Q5. Когортный анализ удержания
--     Когорта = месяц первого заказа. Смотрим, сколько клиентов
--     когорты активны через N месяцев после первого заказа.
--     (CTE + расчёт номера месяца + COUNT DISTINCT)
-- ------------------------------------------------------------
WITH first_order AS (
    SELECT customer_id,
           date_trunc('month', MIN(order_date))::date AS cohort_month
    FROM orders
    WHERE status = 'delivered'
    GROUP BY customer_id
),
activity AS (
    SELECT customer_id,
           date_trunc('month', order_date)::date AS activity_month
    FROM orders
    WHERE status = 'delivered'
)
SELECT
    f.cohort_month,
    (EXTRACT(YEAR  FROM a.activity_month) - EXTRACT(YEAR  FROM f.cohort_month)) * 12
  + (EXTRACT(MONTH FROM a.activity_month) - EXTRACT(MONTH FROM f.cohort_month)) AS month_number,
    COUNT(DISTINCT a.customer_id) AS active_customers
FROM first_order f
JOIN activity a ON a.customer_id = f.customer_id
GROUP BY f.cohort_month, month_number
ORDER BY f.cohort_month, month_number;


-- ------------------------------------------------------------
-- Q6. Где теряются клиенты: уровень оттока (churn)
--     Клиент считается ушедшим, если не заказывал > 90 дней
--     от последней даты в данных.
-- ------------------------------------------------------------
WITH last_order AS (
    SELECT customer_id, MAX(order_date) AS last_date
    FROM orders
    WHERE status = 'delivered'
    GROUP BY customer_id
),
ref AS (SELECT MAX(order_date) AS max_date FROM orders)
SELECT
    COUNT(*) FILTER (WHERE last_date < max_date - INTERVAL '90 days') AS churned,
    COUNT(*)                                                          AS total_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE last_date < max_date - INTERVAL '90 days')
          / COUNT(*), 1)                                              AS churn_rate_pct
FROM last_order, ref;


-- ------------------------------------------------------------
-- Q7. RFM-сегментация клиентов
--     R (recency), F (frequency), M (monetary); 5 = лучший.
--     (NTILE(5) — оконное разбиение на квинтили)
-- ------------------------------------------------------------
WITH ref AS (SELECT MAX(order_date) AS max_date FROM orders),
base AS (
    SELECT
        o.customer_id,
        (SELECT max_date FROM ref) - MAX(o.order_date) AS recency_days,
        COUNT(DISTINCT o.order_id)                     AS frequency,
        SUM(oi.quantity * oi.item_price)               AS monetary
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
)
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score, -- меньше дней -> выше балл
    NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
    NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
FROM base
ORDER BY monetary DESC
LIMIT 50;


-- ------------------------------------------------------------
-- Q8. Средний чек (AOV) и выручка на клиента (ARPU)
-- ------------------------------------------------------------
WITH order_totals AS (
    SELECT o.order_id, o.customer_id,
           SUM(oi.quantity * oi.item_price) AS order_total
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY o.order_id, o.customer_id
)
SELECT
    ROUND(AVG(order_total), 2)                                   AS avg_order_value,
    ROUND(SUM(order_total) / COUNT(DISTINCT customer_id), 2)     AS arpu,
    COUNT(*)                                                     AS orders,
    COUNT(DISTINCT customer_id)                                  AS customers
FROM order_totals;
