/*=========================================================
Object Name : SP_LOAD_AEROSPACE_PARTS_SCD1
Purpose     : Aerospace parts SCD1 pipeline with delta changes applied
Author      : SDLC_AGENT
=========================================================*/
CREATE OR REPLACE PROCEDURE GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.SP_LOAD_AEROSPACE_PARTS_SCD1()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    -- SECTION 1: Variables
    v_watermark_from        TIMESTAMP_NTZ;
    v_watermark_to          TIMESTAMP_NTZ;
    v_source_count          INTEGER DEFAULT 0;
    v_target_pre_count      INTEGER DEFAULT 0;
    v_target_post_count     INTEGER DEFAULT 0;
    v_inserted_count        INTEGER DEFAULT 0;
    v_updated_count         INTEGER DEFAULT 0;
    v_soft_deleted_count    INTEGER DEFAULT 0;
    v_excluded_count        INTEGER DEFAULT 0;
    v_run_id                VARCHAR;
    v_run_timestamp         TIMESTAMP_NTZ;
    v_start_ts              TIMESTAMP_NTZ;
    v_end_ts                TIMESTAMP_NTZ;
    v_elapsed_seconds       FLOAT;
    v_status                VARCHAR DEFAULT 'SUCCESS';
    v_error_message         VARCHAR DEFAULT NULL;
    v_result                VARCHAR;

BEGIN
    -- SECTION 2: Source Processing
    v_run_id        := 'RUN_' || TO_VARCHAR(CURRENT_TIMESTAMP, 'YYYYMMDD_HH24MISS');
    v_run_timestamp := CURRENT_TIMESTAMP::TIMESTAMP_NTZ;
    v_start_ts      := CURRENT_TIMESTAMP::TIMESTAMP_NTZ;

    -- Resolve incremental watermark; COALESCE to 1900-01-01 for first full load
    SELECT COALESCE(MAX(DW_LAST_UPDATE_TIMESTAMP), '1900-01-01'::TIMESTAMP_NTZ)
      INTO v_watermark_from
      FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET;

    v_watermark_to := CURRENT_TIMESTAMP::TIMESTAMP_NTZ;

    -- Deduplicated staging with transforms
    CREATE OR REPLACE TEMPORARY TABLE TEMP_AEROSPACE_STAGED AS
    SELECT
        PART_NUMBER,
        MANUFACTURER,
        NULLIF(CASE WHEN WEIGHT_KG <= 0 THEN NULL ELSE WEIGHT_KG END, 0) AS WEIGHT_KG,
        ROUND(UNIT_PRICE_USD, 2)                                          AS UNIT_PRICE_USD,
        CERTIFICATION_STATUS,
        LEAD_TIME_DAYS,
        LIFECYCLE_STATUS,
        INSTALLATION_DATE,
        UPDATED_AT,
        ROW_NUMBER() OVER (PARTITION BY PART_NUMBER ORDER BY UPDATED_AT DESC) AS RN
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_SOURCE
    WHERE UPDATED_AT > v_watermark_from
      AND UPDATED_AT <= v_watermark_to;

    -- Deduplicated + enriched
    CREATE OR REPLACE TEMPORARY TABLE TEMP_AEROSPACE_ENRICHED AS
    SELECT
        PART_NUMBER,
        MANUFACTURER,
        WEIGHT_KG,
        UNIT_PRICE_USD,
        CERTIFICATION_STATUS,
        LEAD_TIME_DAYS,
        LIFECYCLE_STATUS,
        INSTALLATION_DATE,
        UPDATED_AT,
        CASE
            WHEN CERTIFICATION_STATUS = 'Pending' AND LEAD_TIME_DAYS > 90  THEN 'High Risk'
            WHEN CERTIFICATION_STATUS = 'Pending' OR  LEAD_TIME_DAYS > 120 THEN 'Medium Risk'
            WHEN CERTIFICATION_STATUS IN ('FAA','EASA','Dual') AND LEAD_TIME_DAYS <= 60 THEN 'Low Risk'
            ELSE 'Medium Risk'
        END AS RISK_SCORE
    FROM TEMP_AEROSPACE_STAGED
    WHERE RN = 1;

    SELECT COUNT(*) INTO v_source_count FROM TEMP_AEROSPACE_ENRICHED;

    -- SECTION 3: Data Validation
    -- Exclude End-of-Life records older than 3 years
    CREATE OR REPLACE TEMPORARY TABLE TEMP_AEROSPACE_VALID AS
    SELECT * FROM TEMP_AEROSPACE_ENRICHED
    WHERE NOT (LIFECYCLE_STATUS = 'End of Life' AND INSTALLATION_DATE < DATEADD(year, -3, CURRENT_DATE()));

    SELECT v_source_count - COUNT(*) INTO v_excluded_count FROM TEMP_AEROSPACE_VALID;

    SELECT COUNT(*) INTO v_target_pre_count
      FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET;

    -- SECTION 4: Merge Logic
    MERGE INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET T
    USING TEMP_AEROSPACE_VALID S
       ON T.PART_NUMBER = S.PART_NUMBER
    WHEN MATCHED THEN UPDATE SET
        T.MANUFACTURER            = S.MANUFACTURER,
        T.WEIGHT_KG               = S.WEIGHT_KG,
        T.UNIT_PRICE_USD          = S.UNIT_PRICE_USD,
        T.CERTIFICATION_STATUS    = S.CERTIFICATION_STATUS,
        T.LEAD_TIME_DAYS          = S.LEAD_TIME_DAYS,
        T.LIFECYCLE_STATUS        = S.LIFECYCLE_STATUS,
        T.INSTALLATION_DATE       = S.INSTALLATION_DATE,
        T.UPDATED_AT              = S.UPDATED_AT,
        T.RISK_SCORE              = S.RISK_SCORE,
        T.DW_LAST_UPDATE_TIMESTAMP = CURRENT_TIMESTAMP::TIMESTAMP_NTZ
    WHEN NOT MATCHED THEN INSERT (
        PART_NUMBER, MANUFACTURER, WEIGHT_KG, UNIT_PRICE_USD,
        CERTIFICATION_STATUS, LEAD_TIME_DAYS, LIFECYCLE_STATUS,
        INSTALLATION_DATE, UPDATED_AT, RISK_SCORE,
        DW_INSERT_TIMESTAMP, DW_LAST_UPDATE_TIMESTAMP
    ) VALUES (
        S.PART_NUMBER, S.MANUFACTURER, S.WEIGHT_KG, S.UNIT_PRICE_USD,
        S.CERTIFICATION_STATUS, S.LEAD_TIME_DAYS, S.LIFECYCLE_STATUS,
        S.INSTALLATION_DATE, S.UPDATED_AT, S.RISK_SCORE,
        CURRENT_TIMESTAMP::TIMESTAMP_NTZ, CURRENT_TIMESTAMP::TIMESTAMP_NTZ
    );

    SELECT COUNT_IF(METADATA$ACTION='INSERT'),
           COUNT_IF(METADATA$ACTION='UPDATE' AND METADATA$ISUPDATE=TRUE)
      INTO v_inserted_count, v_updated_count
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Soft delete: records in target not in current source extract
    UPDATE GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET T
       SET T.LIFECYCLE_STATUS          = 'Decommissioned',
           T.DW_LAST_UPDATE_TIMESTAMP  = CURRENT_TIMESTAMP::TIMESTAMP_NTZ
     WHERE NOT EXISTS (
           SELECT 1 FROM TEMP_AEROSPACE_VALID S WHERE S.PART_NUMBER = T.PART_NUMBER
     )
       AND T.LIFECYCLE_STATUS <> 'Decommissioned';

    SELECT COUNT(*) INTO v_soft_deleted_count FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    SELECT COUNT(*) INTO v_target_post_count
      FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET;

    v_end_ts        := CURRENT_TIMESTAMP::TIMESTAMP_NTZ;
    v_elapsed_seconds := DATEDIFF('millisecond', v_start_ts, v_end_ts) / 1000.0;

    -- SECTION 5: Reconciliation
    INSERT INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.ETL_RECONCILIATION_LOG (
        RUN_ID, RUN_TIMESTAMP, PROCEDURE_NAME,
        WATERMARK_FROM, WATERMARK_TO,
        SOURCE_COUNT, TARGET_PRE_COUNT, TARGET_POST_COUNT,
        INSERTED_COUNT, UPDATED_COUNT, SOFT_DELETED_COUNT, EXCLUDED_COUNT,
        ELAPSED_SECONDS, STATUS, ERROR_MESSAGE
    ) VALUES (
        v_run_id, v_run_timestamp, 'SP_LOAD_AEROSPACE_PARTS_SCD1',
        v_watermark_from, v_watermark_to,
        v_source_count, v_target_pre_count, v_target_post_count,
        v_inserted_count, v_updated_count, v_soft_deleted_count, v_excluded_count,
        v_elapsed_seconds, v_status, v_error_message
    );

    -- SECTION 6: Error Handling
    v_result := OBJECT_CONSTRUCT(
        'run_id',            v_run_id,
        'status',            v_status,
        'source_count',      v_source_count,
        'inserted_count',    v_inserted_count,
        'updated_count',     v_updated_count,
        'soft_deleted_count',v_soft_deleted_count,
        'excluded_count',    v_excluded_count,
        'elapsed_seconds',   v_elapsed_seconds
    )::VARCHAR;

    RETURN v_result;

EXCEPTION WHEN OTHER THEN
    RETURN OBJECT_CONSTRUCT('error', SQLERRM)::VARCHAR;
END;
$$;