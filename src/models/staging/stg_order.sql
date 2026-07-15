WITH RAW_ORDER AS (
    SELECT
        $1::STRING AS ORDERID,
        $2::STRING AS CUSTID,
        $3::STRING AS ITEMNAME,
        $4::STRING AS PRICEPERUNIT,
        $5::STRING AS QTY,
        $6::STRING AS ORDER_DATE,
        $7::STRING AS STARTDATE,
        $8::STRING AS ENDDATE,
        $9::STRING AS ISACTIVE
    FROM
        @gen_ai_poc_snowflakecoe.sdlc_wizard.sdlc_wizard_stage/orderdata
        (FILE_FORMAT => 'gen_ai_poc_snowflakecoe.sdlc_wizard.CSV_STAGE_FORMAT')
)

SELECT
    ORDERID,
    CUSTID,
    ITEMNAME,
    PRICEPERUNIT,
    QTY,
    ORDER_DATE,
    STARTDATE,
    ENDDATE,
    ISACTIVE
FROM RAW_ORDER