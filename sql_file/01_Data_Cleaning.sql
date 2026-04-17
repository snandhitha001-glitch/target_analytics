SHOW TABLES;

-- 1. customers table
DESC customers;
SELECT * FROM customers;

-- CHECKING FOR NULL VALUES
SELECT * FROM customers 
WHERE customer_id IS NULL OR customer_id="";

SELECT * FROM customers 
WHERE customer_unique_id IS NULL OR customer_unique_id="";

SELECT * FROM customers 
WHERE customer_zip_code_prefix IS NULL OR customer_zip_code_prefix="";

SELECT * FROM customers 
WHERE customer_city IS NULL OR customer_city="";

SELECT * FROM customers 
WHERE customer_state IS NULL OR customer_state="";

-- 2. order_items table
DESC order_items; ## shipping_limit_date is Text!
SELECT * FROM order_items; ## shipping_limit_date should be DateTime and not Text

-- UPDATING TYPE
ALTER TABLE order_items
MODIFY COLUMN shipping_limit_date DATETIME;

-- VERIFICATION
DESC order_items;
SELECT * FROM order_items;

-- CHECKING NULL VALUES
SELECT * FROM order_items 
WHERE order_id IS NULL OR order_id="";

SELECT * FROM order_items 
WHERE order_item_id IS NULL;

SELECT * FROM order_items 
WHERE product_id IS NULL OR product_id="";

SELECT * FROM order_items 
WHERE seller_id IS NULL OR seller_id="";

SELECT * FROM order_items 
WHERE shipping_limit_date IS NULL;

SELECT * FROM order_items 
WHERE price IS NULL;

SELECT * FROM order_items 
WHERE freight_value IS NULL;

-- 3. orders table
DESC orders; 
SELECT * FROM orders;
## order_purchase_timestamp, 
## order_approved_at, 
## order_delivered_carrier_date, 
## order_delivered_customer_date are all as TEXT!

## order_approved_at,
## order_delivered_carrier_date, 
## order_delivered_customer_date have empty values!

-- UPDATING COLUMNS TO DATETIME
ALTER TABLE orders
MODIFY order_purchase_timestamp DATETIME;

-- UPDATING EMPTY VALUES WITH NULL
UPDATE orders
SET order_approved_at = NULL
WHERE order_approved_at = '';

UPDATE orders
SET order_delivered_carrier_date = NULL
WHERE order_delivered_carrier_date = '';

UPDATE orders
SET order_delivered_customer_date = NULL
WHERE order_delivered_customer_date = '';

-- UPDATING COLUMNS TO DATETIME
ALTER TABLE orders
MODIFY order_approved_at DATETIME,
MODIFY order_delivered_carrier_date DATETIME,
MODIFY order_delivered_customer_date DATETIME;

ALTER TABLE orders
MODIFY order_estimated_delivery_date DATETIME;

-- VERIFICATION
DESC orders; 
SELECT * FROM orders;

-- CHECKING NULL VALUES
SELECT * FROM orders 
WHERE order_id IS NULL OR order_id="";

SELECT * FROM orders 
WHERE customer_id IS NULL OR customer_id="";

SELECT * FROM orders 
WHERE order_status IS NULL OR order_status="";

-- empty values were converted to NULL before updating to DATETIME
SELECT * FROM orders 
WHERE order_purchase_timestamp IS NULL; 

SELECT * FROM orders 
WHERE order_approved_at IS NULL; -- ISSUE!

SELECT * FROM orders 
WHERE order_delivered_carrier_date IS NULL; -- ISSUE!

SELECT * FROM orders 
WHERE order_delivered_customer_date IS NULL; -- ISSUE!

SELECT * FROM orders
WHERE order_estimated_delivery_date IS NULL;

SELECT DISTINCT(order_status) FROM orders; -- delivered, invoiced, shipped, processing, unavailable, canceled, created, approved

/* lifecycle of orders are usually such that:
-- created -> approved -> shipped to carrier -> delivered 
-- so NULL value expectation can be summarized as:
| order_status | approved NULL | carrier NULL | delivered NULL |
| ------------ | ------------- | ------------ | -------------- |
| created      | expected      | expected     | expected       |
| processing   | possible      | expected     | expected       |
| approved     | no            | expected     | expected       |
| shipped      | no            | no           | expected       |
| delivered    | anomaly       | anomaly      | no             |
| canceled     | expected      | expected     | expected       |
*/

/*
Created this VIEW (orders_clean) instead of modifying the raw orders table or creating a new physical table because:
1. Separation of concerns:
   - The raw orders table represents source transactional data.
   - This view adds analytical transformations (flags, derived metrics) without altering original data.
2. Data integrity:
   - Raw data remains unchanged and trustworthy.
   - Derived logic (e.g., is_delivered, delivery_time_days) can evolve without risk of corrupting historical data.
3. Flexibility:
   - Business definitions (e.g., what counts as "shipped" or "delivered") may change.
   - Using a view ensures changes propagate automatically without backfilling or rewriting data.
4. No data duplication:
   - A view does not store data physically, avoiding storage overhead and duplication.
5. Always up-to-date:
   - The view reflects the latest state of the raw orders table in real time.
6. Maintainability:
   - Centralizes business logic in one place, making queries simpler and more consistent across analyses.
Hence a VIEW is preferred here because this is a lightweight transformation layer for analytics, not a persistent data storage or aggregated reporting layer.
*/

CREATE VIEW orders_clean AS
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,

    -- Stage flags
    CASE WHEN order_approved_at IS NOT NULL THEN 1 ELSE 0 END AS is_approved,
    CASE WHEN order_delivered_carrier_date IS NOT NULL THEN 1 ELSE 0 END AS is_shipped,
    CASE WHEN order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END AS is_delivered,

    -- Delay metrics only when valid
    CASE 
        WHEN order_delivered_customer_date IS NOT NULL 
        THEN DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)
        ELSE NULL
    END AS delivery_time_days
    
FROM orders;

-- VERIFICATION
DESC orders_clean;

SELECT order_status, order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, is_approved, is_shipped, is_delivered
FROM orders_clean
WHERE order_approved_at IS NULL
OR order_delivered_carrier_date IS NULL
OR order_delivered_customer_date IS NULL; -- The columns where there were NULLs!

-- Delivered orders should always have delivery date
SELECT *
FROM orders_clean
WHERE is_delivered = 1
AND order_delivered_customer_date IS NULL;

-- Shipped should not happen before approval
SELECT *
FROM orders_clean
WHERE order_delivered_carrier_date < order_approved_at;

-- How many records were shipped before approval
SELECT COUNT(*) AS invalid_records
FROM orders_clean
WHERE order_delivered_carrier_date < order_approved_at;

SELECT COUNT(*) AS total_orders
FROM orders_clean;

-- UPDATING THE VIEW FLAGGING THE TIME ANOMALY
CREATE OR REPLACE VIEW orders_clean AS
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,

    CASE WHEN order_approved_at IS NOT NULL THEN 1 ELSE 0 END AS is_approved,
    CASE WHEN order_delivered_carrier_date IS NOT NULL THEN 1 ELSE 0 END AS is_shipped,
    CASE WHEN order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END AS is_delivered,

    CASE 
        WHEN order_delivered_customer_date IS NOT NULL 
        THEN DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)
    END AS delivery_time_days,

    -- ANOMALY FIX
    CASE 
        WHEN order_delivered_carrier_date < order_approved_at THEN 1
        ELSE 0
    END AS is_timestamp_anomaly

FROM orders;

-- VERIFICATION
-- verify the anomaly
SELECT is_timestamp_anomaly, COUNT(*) 
FROM orders_clean
GROUP BY is_timestamp_anomaly;

-- 4. payments table
DESC payments;
SELECT * FROM payments;

-- CHECKING NULL VALUES
SELECT * FROM payments 
WHERE order_id IS NULL OR order_id="";

SELECT * FROM payments 
WHERE payment_sequential IS NULL;

SELECT * FROM payments 
WHERE payment_type IS NULL OR payment_type="";

SELECT * FROM payments 
WHERE payment_installments IS NULL;

SELECT * FROM payments 
WHERE payment_value IS NULL;