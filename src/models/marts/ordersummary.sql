{{
    config(
        materialized='table',
        schema='sdlc_wizard'
    )
}}

WITH CUSTOMER_DATA AS (
    SELECT
        CUSTID,
        NAME,
        EMAILID,
        REGION
    FROM {{ ref('int_customer_clean') }}
),

ORDER_DATA AS (
    SELECT
        ORDERID,
        CUSTID,
        ITEMNAME,
        PRICEPERUNIT,
        QTY,
        ORDER_DATE,
        STARTDATE,
        ENDDATE,
        ISACTIVE,
        (PRICEPERUNIT * QTY) AS TOTALAMOUNT
    FROM {{ ref('int_order_clean') }}
),

JOINED_DATA AS (
    SELECT
        O.ORDERID,
        C.CUSTID,
        C.NAME,
        C.EMAILID,
        C.REGION,
        O.ITEMNAME,
        O.PRICEPERUNIT,
        O.QTY,
        O.TOTALAMOUNT,
        O.ORDER_DATE,
        O.STARTDATE,
        O.ENDDATE,
        O.ISACTIVE
    FROM ORDER_DATA O
    INNER JOIN CUSTOMER_DATA C
        ON O.CUSTID = C.CUSTID
)

SELECT
    ORDERID,
    CUSTID,
    NAME,
    EMAILID,
    REGION,
    ITEMNAME,
    PRICEPERUNIT,
    QTY,
    TOTALAMOUNT,
    ORDER_DATE,
    STARTDATE,
    ENDDATE,
    ISACTIVE
FROM JOINED_DATA