WITH RAW_CUSTOMER AS (
    SELECT
        $1::STRING AS CUSTID,
        $2::STRING AS NAME,
        $3::STRING AS EMAILID,
        $4::STRING AS REGION
    FROM
        @gen_ai_poc_snowflakecoe.sdlc_wizard.sdlc_wizard_stage/customerdata
        (FILE_FORMAT => 'gen_ai_poc_snowflakecoe.sdlc_wizard.CSV_STAGE_FORMAT')
)

SELECT
    CUSTID,
    NAME,
    EMAILID,
    REGION
FROM RAW_CUSTOMER