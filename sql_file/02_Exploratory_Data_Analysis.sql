-- EXPLORATORY DATA ANALYSIS
/* Geographic Insights
Focus: Where demand comes from
Key questions:
Which cities/states generate most orders?
Which regions generate most revenue?
*/

-- No of customers segregated per state and from each city
SELECT customer_state, customer_city, COUNT(*) AS customer_count
FROM customers
GROUP BY customer_state, customer_city
ORDER BY customer_state;

-- No of orders per state that has been ordered
SELECT c.customer_state, COUNT(DISTINCT o.order_id) AS no_of_orders 
FROM orders_clean o 
JOIN customers c
ON o.customer_id=c.customer_id
AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_state
ORDER BY no_of_orders DESC;

-- No of orders per city that has been ordered
SELECT c.customer_city, COUNT(DISTINCT o.order_id) AS no_of_orders 
FROM orders_clean o 
JOIN customers c
ON o.customer_id=c.customer_id
AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_city
ORDER BY no_of_orders DESC;

-- Now we are going to find amount spent on orders
-- state-wise and city-wise extending from above queries
SELECT c.customer_state, COUNT(DISTINCT o.order_id) AS no_of_orders, ROUND(SUM(order_total), 2) AS total_amount
FROM customers c
JOIN orders_clean o ON c.customer_id = o.customer_id
JOIN (
    SELECT order_id, SUM(payment_value) AS order_total
    FROM payments
    GROUP BY order_id
) p 
ON o.order_id = p.order_id
AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_state
ORDER BY total_amount DESC;

SELECT c.customer_city, COUNT(DISTINCT o.order_id) AS no_of_orders, ROUND(SUM(order_total), 2) AS total_amount
FROM customers c
JOIN orders_clean o ON c.customer_id = o.customer_id
JOIN (
    SELECT order_id, SUM(payment_value) AS order_total
    FROM payments
    GROUP BY order_id
) p ON o.order_id = p.order_id
AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_city
ORDER BY total_amount DESC;

/*
Customer Analysis
Focus: Who are your customers?
Key questions:
How many unique customers?
How frequently do customers order?
Are customers one-time or repeat?
*/

-- No of Orders per customer
SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS no_of_orders
FROM customers c
JOIN orders_clean o
ON c.customer_id=o.customer_id
AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_unique_id
ORDER BY no_of_orders DESC;

-- No of customers who bought again and 
-- first time customers
-- i.e, Repeat vs One-Time Customer
SELECT
CASE
	WHEN no_of_orders=1 THEN 'One-time'
    WHEN no_of_orders>1 THEN 'Repeat'
END AS customer_type, 
COUNT(*) AS no_of_customers
FROM (
	SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS no_of_orders
	FROM customers c
	JOIN orders_clean o
	ON c.customer_id=o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
	GROUP BY c.customer_unique_id
) t
GROUP BY customer_type;

-- Amount spent by customer
SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS no_of_orders, ROUND(SUM(order_total), 2) AS amount_spent
FROM customers c
LEFT JOIN orders_clean o
ON c.customer_id = o.customer_id
LEFT JOIN (
    SELECT order_id, SUM(payment_value) AS order_total
    FROM payments
    GROUP BY order_id
) p 
ON p.order_id = o.order_id
AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_unique_id
ORDER BY amount_spent DESC, no_of_orders DESC;

/*
Order & Sales
Focus: Volume, revenue, trends
Key questions:
How many orders are placed over time?
What is total revenue?
What is the average order value (AOV)?
Are orders growing or declining?
*/

-- Yearly orders
SELECT YEAR(DATE(order_purchase_timestamp)) AS order_year, COUNT(*) AS no_of_orders
FROM orders_clean
WHERE order_status NOT IN ('canceled', 'unavailable')
GROUP BY YEAR(DATE(order_purchase_timestamp))
ORDER BY order_year;

-- Monthly orders
SELECT order_date, COUNT(*) AS no_of_orders
FROM (
SELECT order_status, DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_date
FROM orders_clean
) t
WHERE order_status NOT IN ('canceled', 'unavailable')
GROUP BY order_date
ORDER BY order_date;

-- Total revenue generated per year
SELECT YEAR(DATE(o.order_purchase_timestamp)) AS order_year, ROUND(SUM(order_total), 2) AS revenue
FROM orders_clean o
JOIN (
    SELECT order_id, SUM(payment_value) AS order_total
    FROM payments
    GROUP BY order_id
) p 
ON o.order_id = p.order_id
AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY order_year
ORDER BY order_year;

-- Total revenue generated per year-month
SELECT DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_date, ROUND(SUM(order_total), 2) AS revenue
FROM orders_clean o
JOIN (
    SELECT order_id, SUM(payment_value) AS order_total
    FROM payments
    GROUP BY order_id
) p 
ON o.order_id = p.order_id
AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY order_date
ORDER BY order_date;

-- Average Order Value per year
SELECT YEAR(DATE(o.order_purchase_timestamp)) AS order_year, ROUND(AVG(order_total), 2) AS avg_order_value
FROM orders_clean o
JOIN (
    SELECT order_id, SUM(payment_value) AS order_total
    FROM payments
    GROUP BY order_id
) p ON o.order_id = p.order_id
AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY order_year;

-- Average Order Value per year-month
SELECT DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_date, ROUND(AVG(order_total), 2) AS avg_order_value
FROM orders_clean o
JOIN (
    SELECT order_id, SUM(payment_value) AS order_total
    FROM payments
    GROUP BY order_id
) p ON o.order_id = p.order_id
AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY order_date;

-- Order Status
SELECT order_status, COUNT(*) AS total_orders
FROM orders_clean
GROUP BY order_status;

/*
Payment Behavior
Focus: How customers pay
Key questions:
Most popular payment types?
Do customers use installments?
*/

-- Payment type distribution
SELECT payment_type, COUNT(*) AS usage_count
FROM payments
GROUP BY payment_type
ORDER BY usage_count DESC;

-- Installment behavior
SELECT payment_installments, COUNT(*) AS total_transactions
FROM payments
GROUP BY payment_installments
ORDER BY payment_installments;

/*
Time-Based Behavior
Focus: Customer behavior patterns
Key questions:
What time of day do people order?
Which days are busiest?
*/

-- Orders by hour
SELECT HOUR(order_purchase_timestamp) AS hour, COUNT(*) AS total_orders
FROM orders_clean
GROUP BY hour
ORDER BY total_orders DESC;

-- Going to take one step ahead sort the time and
-- find when is the peak time 
/*
■ 0-6 hrs : Dawn
■ 7-12 hrs : Mornings
■ 13-18 hrs : Afternoon
■ 19-23 hrs : Night
*/
SELECT
CASE
    WHEN HOUR(order_purchase_timestamp) BETWEEN 0 AND 6 THEN 'Dawn'
    WHEN HOUR(order_purchase_timestamp) BETWEEN 7 AND 12 THEN 'Morning'
    WHEN HOUR(order_purchase_timestamp) BETWEEN 13 AND 18 THEN 'Afternoon'
    ELSE 'Night'
END AS day_time,
COUNT(*) AS total_orders
FROM orders_clean
GROUP BY day_time
ORDER BY total_orders DESC;

-- Orders by day
SELECT DAYNAME(order_purchase_timestamp) AS day, COUNT(*) AS total_orders
FROM orders_clean
GROUP BY day
ORDER BY total_orders DESC;

-- Average delivery time
SELECT AVG(delivery_time_days) AS avg_delivery_time
FROM orders_clean
WHERE is_delivered=1 AND is_timestamp_anomaly = 0;

-- Delivery status
SELECT 
    CASE 
        WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 'On Time'
        ELSE 'Delayed'
    END AS delivery_status,
    COUNT(*) AS total_orders
FROM orders_clean
WHERE is_delivered = 1 AND is_timestamp_anomaly = 0
GROUP BY delivery_status;