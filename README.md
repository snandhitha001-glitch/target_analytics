# 🛒 Decoding Target — SQL Analysis of E-Commerce Operations

> *What does it actually look like when millions of people shop online — and what can the data tell us about how to serve them better?*

---

## The Business Problem

Every e-commerce platform generates a trail of data: who bought, what they bought, when it shipped, how they paid. But raw transactional data rarely tells a clean story. Timestamps are stored as text. Nulls are disguised as empty strings. Customer identities are fragmented across order records.

This project takes a dataset of **~99,000 real-world orders** from a Brazilian e-commerce marketplace and transforms it — through structured cleaning, exploration, and advanced analytics — into actionable business intelligence.

The dataset spans four interconnected tables:

| File | What it holds |
|---|---|
| `customers.csv` | ~99K customers — identity, geography |
| `orders.csv` | ~99K orders — status, timestamps, full lifecycle |
| `order_items.csv` | ~112K line items — products, pricing, freight |
| `payments.csv` | ~103K transactions — payment method, installments, value |

Four tables. Four perspectives on the same customer journey: browsing, purchasing, paying, waiting.

---

## Chapter 1 — Building a Foundation Worth Trusting

> *Raw data lies by omission. Before any question can be answered, the data must be made honest.*

```
📄 01_Data_Cleaning.sql
```

### What Was Found

Opening the raw tables revealed data quality issues. In `order_items`, the `shipping_limit_date` column was typed as plain text — making date arithmetic impossible. In `orders`, **four separate timestamp columns** shared the same problem. More critically, some columns used empty strings (`''`) where `NULL` should have been, a subtle issue that silently breaks any `IS NULL` filter.

A null audit was conducted across every column in all four tables — not just to count gaps, but to *classify* them. Which nulls are expected? Which are anomalous?

### The Order Lifecycle Framework

The `orders` table encodes a well-defined fulfillment lifecycle:

```
created → approved → shipped to carrier → delivered
```

A canceled order *should* have null delivery timestamps — that's operationally expected. A `delivered` order missing its delivery timestamp is a data integrity failure. This distinction was mapped explicitly before any analysis was written:

| Order Status | Approved NULL | Carrier NULL | Delivered NULL |
|---|---|---|---|
| `created` | Expected | Expected | Expected |
| `processing` | Possible | Expected | Expected |
| `approved` | No | Expected | Expected |
| `shipped` | No | No | Expected |
| `delivered` | Anomaly 🚩 | Anomaly 🚩 | No |
| `canceled` | Expected | Expected | Expected |

### The `orders_clean` View — Logic Without Risk

Rather than mutating raw data or creating a redundant physical table, a **SQL View** (`orders_clean`) was constructed as a lightweight transformation layer. It exposes all original columns plus derived fields needed across every downstream query:

| Derived Column | Logic |
|---|---|
| `is_approved` | 1 if `order_approved_at` is not null |
| `is_shipped` | 1 if `order_delivered_carrier_date` is not null |
| `is_delivered` | 1 if `order_delivered_customer_date` is not null |
| `delivery_time_days` | `DATEDIFF(delivered, purchased)` — null if undelivered |
| `is_timestamp_anomaly` | 1 if carrier date precedes approval date 🚩 |

The anomaly flag was a significant find — some records showed orders dispatched to carriers *before* approval was recorded. Rather than silently dropping these records, they were **flagged and preserved**, allowing each subsequent analysis to make an explicit, conscious decision about how to handle them.

**Design principle applied:** don't discard the mess — document it, flag it, and let the analysis decide.

---

## Chapter 2 — Exploring the Business Landscape

> *With clean data in hand, the focus shifts from fixing problems to finding patterns.*

```
📄 02_Exploratory_Data_Analysis.sql
```

### Geographic Demand — Where Is the Market?

Orders and revenue were broken down by **state** and **city** to surface regional demand patterns. The key question: are high-order-volume regions also high-revenue regions, or are there markets generating disproportionate value worth closer attention?

### Customer Identity — A Critical Data Nuance

The `customers` table contains a subtle but consequential design: `customer_id` is assigned *per order*, not per person. The field `customer_unique_id` represents the true customer across multiple purchases.

Using the wrong identifier inflates customer counts significantly and invalidates any repeat-purchase or retention analysis. All customer-level metrics in this project use `customer_unique_id` throughout.

With the correct identity resolved, meaningful segmentation became possible:

- **One-time vs. repeat customer split** — what proportion of the base returned?
- **Orders per customer** distribution
- **Customer Lifetime Value (CLV)** — total revenue and order count per unique customer

### Sales Trends — Volume, Revenue, and Order Value Over Time

Order counts and revenue were tracked at both **yearly** and **monthly** granularity. Yearly figures mask seasonality; monthly figures without multi-year context lose the growth narrative. Both views together tell the complete story.

**Average Order Value (AOV)** was also tracked over time — a rising AOV against flat order counts signals very different business health than the reverse.

### Payment Behaviour — How Customers Actually Pay

Brazil's payment ecosystem includes credit cards, boleto bancário, vouchers, and debit cards. The distribution across payment types was analysed alongside installment behaviour — how many customers split payments, and into how many installments?

### Temporal Behaviour — When Does Demand Arrive?

Orders were grouped by hour of day and classified into named periods:

- 🌙 **Dawn** (0–6h) · ☀️ **Morning** (7–12h) · 🌤 **Afternoon** (13–18h) · 🌆 **Night** (19–23h)

Day-of-week patterns were also surfaced. These behavioural rhythms have direct implications for marketing timing, logistics staffing, and notification strategies.

### Delivery Performance — Are Promises Being Kept?

Average delivery time was calculated (excluding timestamp anomalies) and orders were classified as **on-time** or **delayed** — measured against the estimated delivery date communicated to the customer at the point of purchase. Delivery reliability is a core driver of customer trust and repeat behaviour.

---

## Chapter 3 — Advanced Analytics for Strategic Decision-Making

> *Exploration reveals what happened. Advanced analysis explains why it matters — and what to do about it.*

```
📄 03_Advance_Analysis.sql
```

### Cohort Retention Analysis — Are Customers Returning?

Retention is the most honest metric in e-commerce. A high acquisition rate means nothing if customers never come back.

Cohort analysis was constructed using CTEs to answer this precisely:

1. Each customer's **first purchase month** was identified as their cohort
2. Subsequent orders were mapped to a **month offset** from that cohort date
3. The retention rate at each offset was calculated:

```
retention_rate = customers_active_in_month_N / customers_in_month_0 × 100
```

The output is a retention grid — a cohort-by-month view of how many customers remained active after acquisition. A platform with strong product-market fit shows a gradual, stable retention curve. One dependent on constant new acquisition shows a steep drop to near-zero within months.

### RFM Segmentation — Treating Different Customers Differently

Not all customers deserve the same attention. RFM is a proven framework for segmenting the customer base across three behavioural dimensions:

| Dimension | Business Question | Measurement |
|---|---|---|
| **Recency** | How recently did this customer purchase? | Days since last order vs. dataset max date |
| **Frequency** | How often do they buy? | Count of distinct valid orders |
| **Monetary** | How much revenue do they generate? | Total payment value across all orders |

Every customer receives an RFM profile. High-value champions (recent, frequent, high-spend) warrant loyalty investment. Lapsed customers with historical spend are win-back candidates. Low-frequency, low-spend customers may not justify acquisition cost. Segmentation enables targeted, resource-efficient decision-making.

### Cohort CLV Trend — The Long-Term Revenue Picture

The final analysis connects cohorts to cumulative revenue over time, using a SQL window function to build a running total per cohort:

```sql
SUM(revenue) OVER (
    PARTITION BY cohort_month
    ORDER BY month_number
)
```

This produces a **CLV curve per acquisition cohort** — revealing not just total spend, but *how quickly* value accumulates and whether it plateaus or continues growing. Cohorts that front-load their revenue behave very differently from those with sustained long-term spend. This distinction directly informs acquisition budget allocation and payback period calculations.

---

## Key Analytical Principles Applied

**Immutable source data.** Raw tables were never modified. All transformations were applied through a view (`orders_clean`), keeping source data trustworthy and reverifiable at any point.

**Anomaly flagging over silent exclusion.** Data quality issues were documented and flagged (`is_timestamp_anomaly`), giving downstream analyses full visibility and control over how edge cases are handled.

**Identity precision.** The distinction between `customer_id` (per order) and `customer_unique_id` (per person) was enforced consistently — a detail that materially affects every customer-level metric.

**Dual temporal granularity.** Year-level and month-level views were always produced together, since each reveals a different dimension of the same trend.

---

## Tech Stack

- **Database:** MySQL 8+
- **SQL Features:** CTEs, Window Functions, Views, CASE expressions, DATEDIFF, PERIOD_DIFF, DATE_FORMAT, correlated subqueries

---

## Potential Extensions

- **Product-level analysis** — category revenue, freight-to-price ratios, top-performing SKUs
- **Seller performance** — on-time rates, revenue contribution, geographic coverage
- **Churn prediction** — RFM scores as features for an ML classification model
- **Executive dashboard** — export-ready views surfaced in a live BI environment

---

*Structured with rigour. Designed for decisions.*
