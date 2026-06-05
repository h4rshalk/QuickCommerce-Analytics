-- ============================================================
-- QuickCommerce Analytics - Advanced SQL Queries
-- Author: Harshal Kawane
-- Database: quickcommerce
-- ============================================================

USE quickcommerce;


-- ============================================================
-- QUERY 1: Stockout & Fill Rate Analysis
-- Business Question: Which stores are losing revenue due to
-- stockouts during peak hours?
-- ============================================================

WITH peak_hour_orders AS (
    SELECT
        fo.store_id,
        ds.store_name,
        ds.city,
        CASE
            WHEN HOUR(fo.order_time) BETWEEN 7 AND 10 THEN 'Morning Peak'
            WHEN HOUR(fo.order_time) BETWEEN 18 AND 21 THEN 'Evening Peak'
            ELSE 'Normal Hours'
        END AS hour_type,
        COUNT(fo.order_id)                    AS total_orders,
        SUM(fo.is_stockout)                   AS stockout_orders,
        SUM(fo.total_amount)                  AS total_revenue,
        SUM(CASE WHEN fo.is_stockout = 1 
            THEN fo.total_amount ELSE 0 END)  AS lost_revenue
    FROM fact_orders fo
    JOIN dim_dark_stores ds ON fo.store_id = ds.store_id
    GROUP BY fo.store_id, ds.store_name, ds.city,
        CASE
            WHEN HOUR(fo.order_time) BETWEEN 7 AND 10 THEN 'Morning Peak'
            WHEN HOUR(fo.order_time) BETWEEN 18 AND 21 THEN 'Evening Peak'
            ELSE 'Normal Hours'
        END
),
ranked_stores AS (
    SELECT
        store_name,
        city,
        hour_type,
        total_orders,
        stockout_orders,
        ROUND((stockout_orders / total_orders) * 100, 2)    AS stockout_rate_pct,
        ROUND((1 - stockout_orders / total_orders) * 100, 2) AS fill_rate_pct,
        ROUND(lost_revenue, 2)                               AS lost_revenue,
        DENSE_RANK() OVER (
            PARTITION BY hour_type 
            ORDER BY lost_revenue DESC
        ) AS revenue_loss_rank
    FROM peak_hour_orders
)
SELECT *
FROM ranked_stores
WHERE revenue_loss_rank <= 5
ORDER BY hour_type, revenue_loss_rank;



-- ============================================================
-- QUERY 2: Rider Efficiency & Performance Analysis
-- Business Question: Who are the best and worst performing
-- riders and how do they rank within their city?
-- ============================================================

WITH rider_metrics AS (
    SELECT
        fo.rider_id,
        dr.rider_name,
        dr.city,
        dr.vehicle_type,
        COUNT(fo.order_id)                                    AS total_deliveries,
        ROUND(AVG(fo.actual_delivery_mins), 2)                AS avg_delivery_mins,
        SUM(fo.is_late_delivery)                              AS late_deliveries,
        ROUND((SUM(fo.is_late_delivery) / COUNT(fo.order_id)) * 100, 2) AS late_pct,
        ROUND(AVG(CASE WHEN fo.is_late_delivery = 1 
            THEN fo.actual_delivery_mins END), 2)             AS avg_late_delivery_mins,
        ROUND(AVG(CASE WHEN fo.is_late_delivery = 0 
            THEN fo.actual_delivery_mins END), 2)             AS avg_ontime_delivery_mins
    FROM fact_orders fo
    JOIN dim_riders dr ON fo.rider_id = dr.rider_id
    WHERE fo.rider_id != 'UNASSIGNED'
    GROUP BY fo.rider_id, dr.rider_name, dr.city, dr.vehicle_type
),
ranked_riders AS (
    SELECT
        rider_name,
        city,
        vehicle_type,
        total_deliveries,
        avg_delivery_mins,
        late_deliveries,
        late_pct,
        avg_late_delivery_mins,
        avg_ontime_delivery_mins,
        DENSE_RANK() OVER (
            PARTITION BY city 
            ORDER BY late_pct ASC
        ) AS city_performance_rank,
        DENSE_RANK() OVER (
            PARTITION BY city 
            ORDER BY late_pct DESC
        ) AS city_worst_rank
    FROM rider_metrics
)
SELECT *
FROM ranked_riders
WHERE city_performance_rank <= 3 
   OR city_worst_rank <= 3
ORDER BY city, city_performance_rank;


-- ============================================================
-- QUERY 3: SLA Breach Tipping Points
-- Business Question: At what order volume does the 10-minute
-- delivery promise start breaking?
-- ============================================================

WITH hourly_orders AS (
    SELECT
        HOUR(order_time)                                    AS order_hour,
        DATE(order_date)                                    AS order_date,
        COUNT(order_id)                                     AS total_orders,
        SUM(is_late_delivery)                               AS late_orders,
        ROUND(AVG(actual_delivery_mins), 2)                 AS avg_delivery_mins,
        ROUND((SUM(is_late_delivery) / COUNT(order_id)) * 100, 2) AS sla_breach_pct
    FROM fact_orders
    GROUP BY HOUR(order_time), DATE(order_date)
),
hourly_averages AS (
    SELECT
        order_hour,
        ROUND(AVG(total_orders), 0)                        AS avg_orders_per_hour,
        ROUND(AVG(avg_delivery_mins), 2)                   AS avg_delivery_mins,
        ROUND(AVG(sla_breach_pct), 2)                      AS avg_sla_breach_pct,
        MAX(total_orders)                                   AS max_orders_in_hour,
        MAX(sla_breach_pct)                                 AS max_sla_breach_pct,
        CASE
            WHEN order_hour BETWEEN 7 AND 10  THEN 'Morning Peak'
            WHEN order_hour BETWEEN 18 AND 21 THEN 'Evening Peak'
            ELSE 'Normal Hours'
        END                                                AS hour_category,
        LAG(ROUND(AVG(sla_breach_pct), 2)) OVER (
            ORDER BY order_hour
        )                                                  AS prev_hour_breach_pct,
        ROUND(AVG(sla_breach_pct), 2) - LAG(
            ROUND(AVG(sla_breach_pct), 2)
        ) OVER (ORDER BY order_hour)                       AS breach_pct_change
    FROM hourly_orders
    GROUP BY order_hour
)
SELECT
    order_hour,
    hour_category,
    avg_orders_per_hour,
    avg_delivery_mins,
    avg_sla_breach_pct,
    max_orders_in_hour,
    max_sla_breach_pct,
    COALESCE(prev_hour_breach_pct, 0)                      AS prev_hour_breach_pct,
    COALESCE(breach_pct_change, 0)                         AS breach_pct_change
FROM hourly_averages
ORDER BY order_hour;