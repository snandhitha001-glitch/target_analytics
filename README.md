# Decoding Target — SQL Analytics on Brazilian E-Commerce

> *99,441 orders. Four interconnected tables. One question: what does the data actually say about how customers shop, pay, and come back?*

---

## Project Overview

This project performs end-to-end SQL analysis on a real-world Brazilian e-commerce dataset — from raw, messy transactional data through to advanced retention and segmentation analytics. The work is structured across three progressive layers: **data cleaning**, **exploratory analysis**, and **strategic analytics**, each building on the last.

The goal isn't just to answer questions — it's to build an analytical foundation rigorous enough to trust, and insights sharp enough to act on.

---

## The Dataset

Four CSV files. ~415,000 rows of raw transactional data. Four different perspectives on a single customer journey.

| Table | Rows | What it captures |
|---|---|---|
| `customers.csv` | 99,441 | Customer identity, zip code, city, state |
| `orders.csv` | 99,441 | Order status, purchase timestamp, full fulfilment lifecycle |
| `order_items.csv` | 112,650 | Line items — product IDs, seller IDs, price, freight |
| `payments.csv` | 103,885 | Payment method, installment count, transaction value |

The dataset spans multiple years and covers customers across all Brazilian states, with orders ranging from single low-value purchases to multi-item, multi-installment transactions.

---

## Problem Statement

Raw transactional data rarely tells a clean story out of the box. Before any business question can be answered, three fundamental problems had to be resolved:

1. **Type integrity** — timestamp columns stored as plain text made any date arithmetic silently wrong
2. **Null semantics** — empty strings masquerading as `NULL` values broke standard null-handling logic
3. **Identity fragmentation** — the `customers` table assigns a new `customer_id` per order, not per person, which inflates customer counts and invalidates retention analysis if used incorrectly

Only after resolving these could meaningful exploration begin.

---

## Data Cleaning

**File:** `sql_file/01_Data_Cleaning.sql`

### What Was Found

A full schema audit surfaced two categories of issues across all four tables:

**Type mismatches:**
- `order_items.shipping_limit_date` — stored as `TEXT`, preventing date comparisons
- `orders.order_purchase_timestamp`, `order_approved_at`, `order_delivered_carrier_date`, `order_delivered_customer_date` — all four stored as `TEXT`

**Null disguised as empty strings:**
- Three timestamp columns in `orders` used `''` instead of `NULL` — meaning `IS NULL` checks silently returned no results for genuinely missing data

### The Fix

Timestamp columns were converted to `DATETIME` using `ALTER TABLE ... MODIFY COLUMN`. Before the type conversion, empty strings were explicitly replaced with `NULL` via `UPDATE` — a necessary sequencing step, since MySQL cannot cast `''` to `DATETIME`.

### Understanding Expected vs. Anomalous NULLs

A null audit across all columns included a critical analytical step: classifying which nulls are *operationally expected* versus which signal a *data integrity problem*. The fulfilment lifecycle follows a defined path:

```
created → approved → shipped to carrier → delivered to customer
```

This means a cancelled order missing its delivery timestamp is entirely normal — but a `delivered` order missing that same timestamp is a data failure. That distinction was mapped explicitly before any analysis was written:

| Order Status | Approval NULL | Carrier NULL | Delivery NULL |
|---|---|---|---|
| `created` | Expected | Expected | Expected |
| `processing` | Possible | Expected | Expected |
| `approved` | Anomaly 🚩 | Expected | Expected |
| `shipped` | Anomaly 🚩 | Anomaly 🚩 | Expected |
| `delivered` | Anomaly 🚩 | Anomaly 🚩 | Anomaly 🚩 |
| `canceled` | Expected | Expected | Expected |

### The `orders_clean` View

Rather than modifying source data or duplicating it into a new physical table, a **SQL View** (`orders_clean`) was built as a transformation layer. It exposes all original columns alongside derived analytical fields:

| Derived Column | Logic |
|---|---|
| `is_approved` | `1` if `order_approved_at IS NOT NULL` |
| `is_shipped` | `1` if `order_delivered_carrier_date IS NOT NULL` |
| `is_delivered` | `1` if `order_delivered_customer_date IS NOT NULL` |
| `delivery_time_days` | `DATEDIFF(delivered, purchased)` — `NULL` if undelivered |
| `is_timestamp_anomaly` | `1` if carrier dispatch precedes approval timestamp |

The anomaly flag was the most significant find: a subset of records showed orders dispatched to carriers *before* they were approved — a logical impossibility that indicates upstream data quality issues. Rather than silently dropping these records, they were **flagged and preserved**, giving every downstream query full visibility and explicit control over how to handle them.

**Design principle:** don't delete the mess — document it, flag it, let the analysis decide.

---

## Exploratory Data Analysis

**File:** `sql_file/02_Exploratory_Data_Analysis.sql`

### Geographic Demand

Orders and revenue were broken down by **state** and **city** to surface regional demand patterns. Key queries were structured to compare order volume against total revenue — identifying whether high-volume regions are also high-value, or whether some smaller markets punch above their weight in spend per order.

### Customer Identity — A Critical Nuance

The `customers` table contains an important structural detail: `customer_id` is assigned **per order**, not per person. `customer_unique_id` is the true customer identifier across multiple purchases.

Using `customer_id` for any customer-level metric inflates unique customer counts and completely invalidates retention analysis. All customer-facing queries in this project enforce `customer_unique_id` consistently throughout.

With the correct identity resolved, segmentation became meaningful:

- **One-time vs. repeat customer split** — what proportion of the base returned for a second purchase?
- **Orders per customer distribution** — understanding the full range of purchase frequency
- **Customer Lifetime Value (CLV)** — total revenue and order count per unique customer

### Sales Trends

Order volume and revenue were tracked at both **yearly** and **monthly** granularity. These two views are deliberately kept together: yearly figures compress seasonality into a single number; monthly figures without multi-year context lose the growth narrative. Both are needed to tell the complete story.

**Average Order Value (AOV)** was tracked over time as a separate signal — a rising AOV against flat order counts indicates very different business health than growing volume with declining AOV.

### Payment Behaviour

Brazil's payment ecosystem includes credit cards, *boleto bancário*, vouchers, and debit cards. Payment type distribution was analysed alongside installment behaviour — how many customers split payments, and across how many installments? This has direct implications for cash flow forecasting and financial product design.

### Temporal Behaviour — When Customers Actually Shop

Orders were grouped by **hour of day** and mapped to named time windows:

| Window | Hours |
|---|---|
| Dawn 🌙 | 0 – 6 |
| Morning ☀️ | 7 – 12 |
| Afternoon 🌤 | 13 – 18 |
| Night 🌆 | 19 – 23 |

**Day-of-week** patterns were also surfaced. These behavioural rhythms directly inform marketing timing, logistics staffing windows, and push notification scheduling.

### Delivery Performance

Average delivery time was calculated (excluding timestamp anomalies via `is_timestamp_anomaly = 0`) and orders were classified as **on-time** or **delayed** against `order_estimated_delivery_date` — the date communicated to the customer at point of purchase. Delivery reliability is a primary driver of customer trust and repeat behaviour.

---

## Advanced Analytics

**File:** `sql_file/03_Advance_Analysis.sql`

### Cohort Retention Analysis

Retention is the most honest signal in e-commerce. High acquisition numbers mean nothing if customers disappear after their first order.

Cohort analysis was built using a three-CTE chain:

1. **`first_purchase`** — identifies each customer's first order date as their cohort anchor
2. **`cohort_data`** — maps every subsequent order to its `month_number` offset from cohort entry using `PERIOD_DIFF()`
3. **`cohort_counts`** — aggregates unique customers per cohort per month offset

The final output calculates retention rate as:

```
retention_rate = customers_active_in_month_N / customers_in_month_0 × 100
```

The result is a cohort-by-month grid — a precise view of how many customers from each acquisition cohort remained active over time. A platform with genuine product-market fit shows a gradual, stable retention curve. One dependent on constant new acquisition shows a near-vertical drop to zero within the first few months.

### RFM Segmentation

Not all customers deserve the same attention or the same budget. RFM provides a proven, data-driven framework for segmenting the entire customer base across three behavioural dimensions:

| Dimension | Business Question | Measurement |
|---|---|---|
| **Recency** | How recently did this customer purchase? | Days since last order vs. dataset max date |
| **Frequency** | How often do they buy? | Count of distinct valid orders |
| **Monetary** | How much revenue do they generate? | Total payment value across all orders |

Every customer receives an RFM profile. High-value champions — recent, frequent, high-spend — warrant loyalty investment. Customers with strong historical spend who have lapsed are prime win-back candidates. Low-frequency, low-spend customers may not justify further acquisition cost. Segmentation enables targeted, resource-efficient decision-making rather than treating a 10-order customer the same as a first-time buyer.

### Cohort CLV Trend — The Long-Term Revenue Picture

The final analysis connects acquisition cohorts to cumulative revenue over time, using a `SUM() OVER (PARTITION BY cohort_month ORDER BY month_number)` window function to build a running total per cohort.

```sql
SUM(revenue) OVER (
    PARTITION BY cohort_month
    ORDER BY month_number
) AS cumulative_clv
```

This produces a **CLV curve per cohort** — revealing not just total spend, but *the rate at which value accumulates* and whether it plateaus or continues growing months after acquisition. Cohorts that front-load their revenue behave fundamentally differently from those with sustained long-tail spend, and this distinction directly informs acquisition budget allocation and payback period calculations.

---

## Key Analytical Principles

**Immutable source data.** Raw tables were never modified beyond necessary type corrections. All analytical transformations — flags, derived metrics, business logic — were applied through the `orders_clean` view. Source data remains trustworthy and reverifiable at any point.

**Anomaly flagging over silent exclusion.** The timestamp anomaly (`is_timestamp_anomaly`) was documented and surfaced as a reusable flag rather than silently dropping affected records. Downstream queries can each decide explicitly whether to exclude or include edge cases.

**Identity precision.** The `customer_id` vs. `customer_unique_id` distinction was enforced throughout. This single detail materially changes every customer-level metric — from simple unique counts to retention rates and CLV calculations.

**Dual temporal granularity.** Year-level and month-level views were always produced in parallel. Neither alone is sufficient; each reveals a different dimension of the same underlying trend.

**Subquery aggregation for payment joins.** The `payments` table was pre-aggregated with `SUM(payment_value) GROUP BY order_id` in a derived subquery before joining to orders — avoiding row duplication that would silently inflate revenue figures in direct joins.

---

## Tech Stack

- **Database:** MySQL 8+
- **SQL Features Used:** CTEs, Window Functions (`SUM OVER`), Views (`CREATE OR REPLACE VIEW`), `CASE` expressions, `DATEDIFF`, `PERIOD_DIFF`, `DATE_FORMAT`, correlated subqueries, derived table aggregation

---

## Potential Extensions

- **Product-level analysis** — category revenue breakdown, freight-to-price ratios, top-performing SKUs by volume vs. margin
- **Seller performance** — on-time fulfilment rates, revenue contribution, geographic coverage per seller
- **Churn prediction** — RFM scores exported as features for an ML classification model
- **BI dashboard** — export-ready views surfaced in Metabase, Tableau, or Looker
- **Freight optimisation** — identifying routes or seller-region combinations with disproportionately high freight costs

---

## Author
**Nandhitha**

*Structured with rigour. Designed for decisions.*
