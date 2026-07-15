{{
    config(
        materialized='table',
        schema='sdlc_wizard'
    )
}}

WITH SNAPSHOT_DATA AS (
    SELECT
        CUSTID,
        NAME,
        EMAILID,
        REGION,
        DBT_VALID_FROM,
        DBT_VALID_TO,
        CASE
            WHEN DBT_VALID_TO IS NULL THEN 'TRUE'
            ELSE 'FALSE'
        END AS ISACTIVE,
        DBT_VALID_FROM AS STARTDATE,
        DBT_VALID_TO AS ENDDATE
    FROM {{ ref('customer_snapshot') }}
)

SELECT
    CUSTID,
    NAME,
    EMAILID,
    REGION,
    STARTDATE,
    ENDDATE,
    ISACTIVE
FROM SNAPSHOT_DATA