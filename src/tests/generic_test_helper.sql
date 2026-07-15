-- This file provides a validation query to raise awareness of data quality issues.
-- dbt tests defined in schema.yml handle standard assertions.
-- This test checks that ordersummary has no orphaned orders (orders without matching customers).
-- If any rows are returned, the test fails, which effectively raises an exception in the dbt test framework.

SELECT
    O.ORDERID,
    O.CUSTID
FROM {{ ref('ordersummary') }} O
LEFT JOIN {{ ref('int_customer_clean') }} C
    ON O.CUSTID = C.CUSTID
WHERE C.CUSTID IS NULL