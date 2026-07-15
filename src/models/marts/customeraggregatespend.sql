{{
    config(
        materialized='table',
        schema='sdlc_wizard'
    )
}}

WITH ORDER_SUMMARY AS (
    SELECT
        NAME,
        ORDER_DATE,
        TOTALAMOUNT
    FROM {{ ref('ordersummary') }}
),

AGGREGATED_SPEND AS (
    SELECT
        NAME,
        ORDER_DATE,
        SUM(TOTALAMOUNT) AS TOTALAMOUNT
    FROM ORDER_SUMMARY
    GROUP BY NAME, ORDER_DATE
)

SELECT
    NAME,
    ORDER_DATE,
    TOTALAMOUNT
FROM AGGREGATED_SPEND