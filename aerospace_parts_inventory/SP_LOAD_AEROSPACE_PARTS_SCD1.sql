/*=========================================================
Object Name : SP_LOAD_AEROSPACE_PARTS_SCD1
Purpose     : SCD1 pipeline for AEROSPACE_PARTS_TARGET
Author      : SDLC_AGENT
=========================================================*/
CREATE OR REPLACE PROCEDURE GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.SP_LOAD_AEROSPACE_PARTS_SCD1()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
-- SECTION 1: Variables
    v_run_id              VARCHAR;
    v_run_timestamp       TIMESTAMP_NTZ;
    v_execution_start     TIMESTAMP_NTZ;
    v_execution_end       TIMESTAMP_NTZ;
    v_execution_seconds   FLOAT;
    v_load_type           VARCHAR  DEFAULT 'SCD1_INCREMENTAL';
    v_status              VARCHAR  DEFAULT 'SUCCESS';
    v_error_message       VARCHAR  DEFAULT NULL;
    v_source_count        INTEGER  DEFAULT 0;
    v_target_count        INTEGER  DEFAULT 0;
    v_inserted_count      INTEGER  DEFAULT 0;
    v_updated_count       INTEGER  DEFAULT 0;
    v_decommissioned_count INTEGER DEFAULT 0;
    v_rejected_count      INTEGER  DEFAULT 0;
    v_last_run_ts         TIMESTAMP_NTZ;
BEGIN
-- SECTION 2: Source Processing
    v_run_id          := 'RUN_' || TO_VARCHAR(CURRENT_TIMESTAMP,'YYYYMMDD_HH24MISS') || '_' || UNIFORM(1000,9999,RANDOM())::VARCHAR;
    v_run_timestamp   := CURRENT_TIMESTAMP::TIMESTAMP_NTZ;
    v_execution_start := CURRENT_TIMESTAMP::TIMESTAMP_NTZ;

    -- Resolve watermark from last successful run
    SELECT COALESCE(MAX(RUN_TIMESTAMP), '1900-01-01'::TIMESTAMP_NTZ)
    INTO v_last_run_ts
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.ETL_RECONCILIATION_LOG
    WHERE PROCEDURE_NAME = 'SP_LOAD_AEROSPACE_PARTS_SCD1' AND STATUS = 'SUCCESS';

    -- Deduplicate source and apply incremental filter
    CREATE OR REPLACE TEMPORARY TABLE STAGING_PARTS AS
    SELECT
        PART_NUMBER,
        UPPER(MANUFACTURER)                                             AS MANUFACTURER,
        CASE WHEN WEIGHT_KG <= 0 THEN NULL ELSE WEIGHT_KG END          AS WEIGHT_KG,
        ROUND(UNIT_PRICE_USD, 2)                                        AS UNIT_PRICE_USD,
        CERTIFICATION_STATUS,
        LEAD_TIME_DAYS,
        LIFECYCLE_STATUS,
        INSTALLATION_DATE,
        UPDATED_AT,
        STATUS,
        CASE
            WHEN CERTIFICATION_STATUS = 'Pending' AND LEAD_TIME_DAYS > 90  THEN 'High Risk'
            WHEN (CERTIFICATION_STATUS = 'Pending' OR LEAD_TIME_DAYS > 120) THEN 'Medium Risk'
            WHEN CERTIFICATION_STATUS IN ('FAA','EASA','Dual') AND LEAD_TIME_DAYS <= 60 THEN 'Low Risk'
            ELSE 'Medium Risk'
        END                                                             AS RISK_SCORE
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY PART_NUMBER ORDER BY UPDATED_AT DESC) AS RN
        FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_SOURCE
        WHERE UPDATED_AT > v_last_run_ts
    ) deduped
    WHERE RN = 1;

-- SECTION 3: Data Validation
    -- Count raw staged rows before exclusions
    SELECT COUNT(*) INTO v_source_count FROM STAGING_PARTS;

    -- Remove exclusion rule records and capture rejected count
    CREATE OR REPLACE TEMPORARY TABLE STAGING_PARTS_CLEAN AS
    SELECT * FROM STAGING_PARTS
    WHERE NOT (LIFECYCLE_STATUS = 'End of Life' AND DATEDIFF('year', INSTALLATION_DATE, CURRENT_DATE) > 3);

    SELECT v_source_count - COUNT(*) INTO v_rejected_count FROM STAGING_PARTS_CLEAN;

    SELECT COUNT(*) INTO v_target_count
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET;

-- SECTION 4: Merge Logic
    MERGE INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET TGT
    USING STAGING_PARTS_CLEAN SRC
       ON TGT.PART_NUMBER = SRC.PART_NUMBER
    WHEN MATCHED THEN UPDATE SET
        TGT.MANUFACTURER         = SRC.MANUFACTURER,
        TGT.WEIGHT_KG            = SRC.WEIGHT_KG,
        TGT.UNIT_PRICE_USD       = SRC.UNIT_PRICE_USD,
        TGT.CERTIFICATION_STATUS = SRC.CERTIFICATION_STATUS,
        TGT.LEAD_TIME_DAYS       = SRC.LEAD_TIME_DAYS,
        TGT.LIFECYCLE_STATUS     = SRC.LIFECYCLE_STATUS,
        TGT.INSTALLATION_DATE    = SRC.INSTALLATION_DATE,
        TGT.UPDATED_AT           = SRC.UPDATED_AT,
        TGT.STATUS               = SRC.STATUS,
        TGT.RISK_SCORE           = SRC.RISK_SCORE,
        TGT.DW_UPDATE_TIMESTAMP  = CURRENT_TIMESTAMP::TIMESTAMP_NTZ
    WHEN NOT MATCHED THEN INSERT (
        PART_NUMBER, MANUFACTURER, WEIGHT_KG, UNIT_PRICE_USD,
        CERTIFICATION_STATUS, LEAD_TIME_DAYS, LIFECYCLE_STATUS,
        INSTALLATION_DATE, UPDATED_AT, STATUS, RISK_SCORE,
        DW_INSERT_TIMESTAMP, DW_UPDATE_TIMESTAMP
    ) VALUES (
        SRC.PART_NUMBER, SRC.MANUFACTURER, SRC.WEIGHT_KG, SRC.UNIT_PRICE_USD,
        SRC.CERTIFICATION_STATUS, SRC.LEAD_TIME_DAYS, SRC.LIFECYCLE_STATUS,
        SRC.INSTALLATION_DATE, SRC.UPDATED_AT, SRC.STATUS, SRC.RISK_SCORE,
        CURRENT_TIMESTAMP::TIMESTAMP_NTZ, CURRENT_TIMESTAMP::TIMESTAMP_NTZ
    );

    -- Capture merge counts
    SELECT COUNT(*) INTO v_updated_count
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET TGT
    INNER JOIN STAGING_PARTS_CLEAN SRC ON TGT.PART_NUMBER = SRC.PART_NUMBER
    WHERE TGT.DW_INSERT_TIMESTAMP < TGT.DW_UPDATE_TIMESTAMP;

    SELECT COUNT(*) INTO v_inserted_count
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET
    WHERE DW_INSERT_TIMESTAMP >= v_execution_start;

    -- Soft delete: mark absent source records as Decommissioned
    UPDATE GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET TGT
    SET TGT.STATUS = 'Decommissioned', TGT.DW_UPDATE_TIMESTAMP = CURRENT_TIMESTAMP::TIMESTAMP_NTZ
    WHERE TGT.STATUS != 'Decommissioned'
      AND NOT EXISTS (
          SELECT 1 FROM STAGING_PARTS_CLEAN SRC WHERE SRC.PART_NUMBER = TGT.PART_NUMBER
      );

    SELECT COUNT(*) INTO v_decommissioned_count
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET
    WHERE STATUS = 'Decommissioned' AND DW_UPDATE_TIMESTAMP >= v_execution_start;

-- SECTION 5: Reconciliation
    v_execution_end     := CURRENT_TIMESTAMP::TIMESTAMP_NTZ;
    v_execution_seconds := DATEDIFF('second', v_execution_start, v_execution_end);

    INSERT INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.ETL_RECONCILIATION_LOG (
        RUN_ID, PROCEDURE_NAME, RUN_TIMESTAMP, LOAD_TYPE,
        SOURCE_COUNT, TARGET_COUNT, INSERTED_COUNT, UPDATED_COUNT,
        DECOMMISSIONED_COUNT, REJECTED_COUNT,
        EXECUTION_START, EXECUTION_END, EXECUTION_SECONDS, STATUS, ERROR_MESSAGE
    ) VALUES (
        v_run_id, 'SP_LOAD_AEROSPACE_PARTS_SCD1', v_run_timestamp, v_load_type,
        v_source_count, v_target_count, v_inserted_count, v_updated_count,
        v_decommissioned_count, v_rejected_count,
        v_execution_start, v_execution_end, v_execution_seconds, v_status, v_error_message
    );

-- SECTION 6: Error Handling
    RETURN OBJECT_CONSTRUCT(
        'run_id',          v_run_id,
        'status',          v_status,
        'source_count',    v_source_count,
        'inserted',        v_inserted_count,
        'updated',         v_updated_count,
        'decommissioned',  v_decommissioned_count,
        'rejected',        v_rejected_count,
        'duration_seconds',v_execution_seconds
    )::VARCHAR;

EXCEPTION WHEN OTHER THEN
    v_status        := 'FAILED';
    v_error_message := SQLERRM;
    v_execution_end := CURRENT_TIMESTAMP::TIMESTAMP_NTZ;

    INSERT INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.ETL_RECONCILIATION_LOG (
        RUN_ID, PROCEDURE_NAME, RUN_TIMESTAMP, LOAD_TYPE,
        SOURCE_COUNT, TARGET_COUNT, INSERTED_COUNT, UPDATED_COUNT,
        DECOMMISSIONED_COUNT, REJECTED_COUNT,
        EXECUTION_START, EXECUTION_END, EXECUTION_SECONDS, STATUS, ERROR_MESSAGE
    ) VALUES (
        v_run_id, 'SP_LOAD_AEROSPACE_PARTS_SCD1', v_run_timestamp, v_load_type,
        v_source_count, v_target_count, v_inserted_count, v_updated_count,
        v_decommissioned_count, v_rejected_count,
        v_execution_start, v_execution_end,
        DATEDIFF('second', v_execution_start, v_execution_end),
        v_status, v_error_message
    );

    RETURN OBJECT_CONSTRUCT('error', SQLERRM)::VARCHAR;
END;
$$;

-- Scheduled Task: daily 02:00 UTC
CREATE OR REPLACE TASK GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.TASK_LOAD_AEROSPACE_PARTS_SCD1
    WAREHOUSE = W_CAPG_APAC_IND_DEMO_IDEA_REFACTOR_SOL_XS
    SCHEDULE  = 'USING CRON 0 2 * * * UTC'
AS
CALL GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.SP_LOAD_AEROSPACE_PARTS_SCD1();

ALTER TASK GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.TASK_LOAD_AEROSPACE_PARTS_SCD1 RESUME;