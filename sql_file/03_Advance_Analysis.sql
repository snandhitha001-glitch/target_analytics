-- Cohort Analysis 
-- How well do customers return after their first purchase? (Customer Retention)

-- Finding the first purchased date for each customer
-- Mapping each order from first_purchase to orders_clean
-- i.e., from the cohort data to the order data and finding the number of customers
WITH first_purchase AS(
	SELECT c.customer_unique_id, MIN(DATE(order_purchase_timestamp)) AS first_purchase_date
	FROM orders_clean o 
    JOIN customers c 
    ON o.customer_id=c.customer_id
	WHERE order_status NOT IN ('canceled', 'unavailable')
	GROUP BY c.customer_unique_id
),

cohort_data AS(
	SELECT c.customer_unique_id,
		DATE_FORMAT(fp.first_purchase_date, '%Y-%m') AS cohort_month,
		DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS ordered_month
	FROM orders_clean o
    JOIN customers c
    ON o.customer_id=c.customer_id
    JOIN first_purchase fp 
    ON c.customer_unique_id=fp.customer_unique_id
    WHERE order_status NOT IN ('canceled', 'unavailable') 
)

SELECT cohort_month, ordered_month, COUNT(DISTINCT customer_unique_id) AS no_of_customers 
FROM cohort_data
GROUP BY cohort_month, ordered_month
ORDER BY cohort_month, ordered_month;

-- Cohort Retention Rate %
-- What % of customers return after their first purchase?
WITH first_purchase AS (
    SELECT 
        c.customer_unique_id,
        MIN(DATE(o.order_purchase_timestamp)) AS first_purchase_date
    FROM orders_clean o
    JOIN customers c 
        ON o.customer_id = c.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
),

cohort_data AS (
    SELECT 
        c.customer_unique_id,
        DATE_FORMAT(fp.first_purchase_date, '%Y-%m') AS cohort_month,

        -- Month difference from first purchase
        PERIOD_DIFF(
            DATE_FORMAT(o.order_purchase_timestamp, '%Y%m'),
            DATE_FORMAT(fp.first_purchase_date, '%Y%m')
        ) AS month_number

    FROM orders_clean o
    JOIN customers c 
        ON o.customer_id = c.customer_id
    JOIN first_purchase fp 
        ON c.customer_unique_id = fp.customer_unique_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),

cohort_counts AS (
    SELECT 
        cohort_month,
        month_number,
        COUNT(DISTINCT customer_unique_id) AS customers
    FROM cohort_data
    GROUP BY cohort_month, month_number
)

SELECT 
    c1.cohort_month,
    c1.month_number,
    c1.customers,

    -- Retention % = customers in month / customers in month 0
    ROUND(
        c1.customers * 100.0 / c0.customers, 
        2
    ) AS retention_rate

FROM cohort_counts c1

-- Join with base cohort size (month 0)
JOIN cohort_counts c0 
    ON c1.cohort_month = c0.cohort_month 
    AND c0.month_number = 0
ORDER BY c1.cohort_month, c1.month_number;

-- RFM Analysis
-- Segment customers based on 
-- Recency -> last purchase, 
-- Frequency -> number of orders, and 
-- Monetary -> total spend value
-- How can we segment customers based on behavior?

SELECT 
    c.customer_unique_id,

    -- Recency: days since last purchase
    DATEDIFF(
    (SELECT MAX(order_purchase_timestamp) 
     FROM orders_clean 
     WHERE order_status NOT IN ('canceled', 'unavailable')),
    MAX(o.order_purchase_timestamp)
	) AS recency,

    -- Frequency: number of orders
    COUNT(DISTINCT o.order_id) AS frequency,

    -- Monetary: total spend
    ROUND(SUM(p.order_total), 2) AS monetary

FROM customers c
JOIN orders_clean o 
    ON c.customer_id = o.customer_id
JOIN (
    SELECT order_id, SUM(payment_value) AS order_total
    FROM payments
    GROUP BY order_id
) p 
    ON o.order_id = p.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_unique_id;

-- Customer Lifetime Value Trend (Cohort-Based Cumulative Revenue)
-- How much revenue each cohort generates over time
-- Helps answer:
-- 	Do customers spend more over time?
-- 	Which cohorts are more valuable?

WITH first_purchase AS (
    -- Identify first purchase per real customer
    SELECT 
        c.customer_unique_id,
        MIN(DATE(o.order_purchase_timestamp)) AS first_purchase_date
    FROM orders_clean o
    JOIN customers c 
        ON o.customer_id = c.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
),

cohort_data AS (
    -- Map each order to cohort + month offset
    SELECT 
        c.customer_unique_id,
        DATE_FORMAT(fp.first_purchase_date, '%Y-%m') AS cohort_month,

        PERIOD_DIFF(
            DATE_FORMAT(o.order_purchase_timestamp, '%Y%m'),
            DATE_FORMAT(fp.first_purchase_date, '%Y%m')
        ) AS month_number,

        p.order_total

    FROM orders_clean o
    JOIN customers c 
        ON o.customer_id = c.customer_id
    JOIN first_purchase fp 
        ON c.customer_unique_id = fp.customer_unique_id
    JOIN (
        SELECT order_id, SUM(payment_value) AS order_total
        FROM payments
        GROUP BY order_id
    ) p 
        ON o.order_id = p.order_id

    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),

cohort_revenue AS (
    -- Revenue per cohort per month
    SELECT 
        cohort_month,
        month_number,
        SUM(order_total) AS revenue
    FROM cohort_data
    GROUP BY cohort_month, month_number
),

cumulative_revenue AS (
    -- Running total (CLV trend)
    SELECT 
        cohort_month,
        month_number,
        SUM(revenue) OVER (
            PARTITION BY cohort_month 
            ORDER BY month_number
        ) AS cumulative_clv
    FROM cohort_revenue
)

SELECT cohort_month, month_number, ROUND(cumulative_clv, 2)
FROM cumulative_revenue
ORDER BY cohort_month, month_number;
