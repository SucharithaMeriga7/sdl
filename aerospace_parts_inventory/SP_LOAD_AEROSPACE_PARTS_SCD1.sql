/*=========================================================
Object Name : SP_LOAD_AEROSPACE_PARTS_SCD1
Purpose     : Aerospace Parts SCD1 pipeline with RISK_SCORE
Author      : SDLC_AGENT
=========================================================*/
CREATE OR REPLACE PROCEDURE GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.SP_LOAD_AEROSPACE_PARTS_SCD1()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    -- SECTION 1: Variables
    v_start_ts          TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    v_run_id            VARCHAR       := UUID_STRING();
    v_last_load_ts      TIMESTAMP_NTZ;
    v_src_count         INTEGER := 0;
    v_dedup_count       INTEGER := 0;
    v_insert_count      INTEGER := 0;
    v_update_count      INTEGER := 0;
    v_delete_count      INTEGER := 0;
    v_invalid_count     INTEGER := 0;
    v_tgt_before        INTEGER := 0;
    v_tgt_after         INTEGER := 0;
    v_result            VARCHAR;

BEGIN
    USE WAREHOUSE SNOWFLAKE_LEARNING_WH;

    -- SECTION 2: Source Processing
    -- Watermark: last successful load or full load on first run
    SELECT COALESCE(MAX(DW_UPDATED_TIMESTAMP), '1900-01-01'::TIMESTAMP_NTZ)
    INTO :v_last_load_ts
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET;

    SELECT COUNT(*) INTO :v_src_count
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_SOURCE
    WHERE UPDATED_AT > :v_last_load_ts;

    SELECT COUNT(*) INTO :v_tgt_before
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET;

    -- Stage raw incremental records
    CREATE OR REPLACE TEMPORARY TABLE SDLC_WIZARD.STG_PARTS_RAW AS
    SELECT PART_NUMBER, MANUFACTURER, WEIGHT_KG, UNIT_PRICE_USD,
           LIFECYCLE_STATUS, INSTALLATION_DATE, CERTIFICATION_STATUS,
           LEAD_TIME_DAYS, UPDATED_AT
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_SOURCE
    WHERE UPDATED_AT > :v_last_load_ts;

    -- Deduplicate: keep latest UPDATED_AT per PART_NUMBER
    CREATE OR REPLACE TEMPORARY TABLE SDLC_WIZARD.STG_PARTS_DEDUP AS
    SELECT PART_NUMBER, MANUFACTURER, WEIGHT_KG, UNIT_PRICE_USD,
           LIFECYCLE_STATUS, INSTALLATION_DATE, CERTIFICATION_STATUS,
           LEAD_TIME_DAYS, UPDATED_AT
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY PART_NUMBER ORDER BY UPDATED_AT DESC) AS RN
        FROM SDLC_WIZARD.STG_PARTS_RAW
    ) WHERE RN = 1;

    SELECT COUNT(*) INTO :v_dedup_count FROM SDLC_WIZARD.STG_PARTS_DEDUP;

    -- SECTION 3: Data Validation
    -- Exclude: LIFECYCLE_STATUS = 'End of Life' AND INSTALLATION_DATE older than 3 years
    CREATE OR REPLACE TEMPORARY TABLE SDLC_WIZARD.STG_PARTS_INVALID AS
    SELECT * FROM SDLC_WIZARD.STG_PARTS_DEDUP
    WHERE LIFECYCLE_STATUS = 'End of Life'
      AND INSTALLATION_DATE < DATEADD(YEAR, -3, CURRENT_DATE());

    SELECT COUNT(*) INTO :v_invalid_count FROM SDLC_WIZARD.STG_PARTS_INVALID;

    -- Apply transformations and RISK_SCORE derivation on valid records
    CREATE OR REPLACE TEMPORARY TABLE SDLC_WIZARD.STG_PARTS_CLEAN AS
    SELECT
        PART_NUMBER,
        INITCAP(MANUFACTURER)                                        AS MANUFACTURER,
        CASE WHEN WEIGHT_KG <= 0 THEN NULL ELSE WEIGHT_KG END        AS WEIGHT_KG,
        ROUND(UNIT_PRICE_USD, 2)                                     AS UNIT_PRICE_USD,
        LIFECYCLE_STATUS,
        INSTALLATION_DATE,
        CERTIFICATION_STATUS,
        LEAD_TIME_DAYS,
        UPDATED_AT,
        CASE
            WHEN CERTIFICATION_STATUS = 'Pending' AND LEAD_TIME_DAYS > 90  THEN 'High Risk'
            WHEN CERTIFICATION_STATUS = 'Pending' OR  LEAD_TIME_DAYS > 120 THEN 'Medium Risk'
            WHEN CERTIFICATION_STATUS IN ('FAA','EASA','Dual') AND LEAD_TIME_DAYS <= 60 THEN 'Low Risk'
            ELSE 'Medium Risk'
        END                                                          AS RISK_SCORE
    FROM SDLC_WIZARD.STG_PARTS_DEDUP
    WHERE NOT (LIFECYCLE_STATUS = 'End of Life'
               AND INSTALLATION_DATE < DATEADD(YEAR, -3, CURRENT_DATE()));

    -- SECTION 4: Merge Logic
    -- SCD1 MERGE + soft-delete absent records in one pass
    MERGE INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET T
    USING (
        -- Union clean source with soft-delete candidates
        SELECT s.PART_NUMBER, s.MANUFACTURER, s.WEIGHT_KG, s.UNIT_PRICE_USD,
               s.LIFECYCLE_STATUS, s.INSTALLATION_DATE, s.CERTIFICATION_STATUS,
               s.LEAD_TIME_DAYS, s.UPDATED_AT, s.RISK_SCORE, FALSE AS IS_SOFT_DELETE
        FROM SDLC_WIZARD.STG_PARTS_CLEAN s
        UNION ALL
        SELECT t2.PART_NUMBER, t2.MANUFACTURER, t2.WEIGHT_KG, t2.UNIT_PRICE_USD,
               'Decommissioned', t2.INSTALLATION_DATE, t2.CERTIFICATION_STATUS,
               t2.LEAD_TIME_DAYS, t2.DW_UPDATED_TIMESTAMP, t2.RISK_SCORE, TRUE
        FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET t2
        WHERE t2.LIFECYCLE_STATUS <> 'Decommissioned'
          AND NOT EXISTS (SELECT 1 FROM SDLC_WIZARD.STG_PARTS_CLEAN s2
                          WHERE s2.PART_NUMBER = t2.PART_NUMBER)
          AND :v_src_count > 0
    ) S ON T.PART_NUMBER = S.PART_NUMBER
    WHEN MATCHED AND S.IS_SOFT_DELETE = TRUE THEN UPDATE SET
        T.LIFECYCLE_STATUS    = 'Decommissioned',
        T.DW_UPDATED_TIMESTAMP = CURRENT_TIMESTAMP()
    WHEN MATCHED AND S.IS_SOFT_DELETE = FALSE THEN UPDATE SET
        T.MANUFACTURER         = S.MANUFACTURER,
        T.WEIGHT_KG            = S.WEIGHT_KG,
        T.UNIT_PRICE_USD       = S.UNIT_PRICE_USD,
        T.LIFECYCLE_STATUS     = S.LIFECYCLE_STATUS,
        T.INSTALLATION_DATE    = S.INSTALLATION_DATE,
        T.CERTIFICATION_STATUS = S.CERTIFICATION_STATUS,
        T.LEAD_TIME_DAYS       = S.LEAD_TIME_DAYS,
        T.UPDATED_AT           = S.UPDATED_AT,
        T.RISK_SCORE           = S.RISK_SCORE,
        T.DW_UPDATED_TIMESTAMP = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED AND S.IS_SOFT_DELETE = FALSE THEN INSERT (
        PART_NUMBER, MANUFACTURER, WEIGHT_KG, UNIT_PRICE_USD,
        LIFECYCLE_STATUS, INSTALLATION_DATE, CERTIFICATION_STATUS,
        LEAD_TIME_DAYS, UPDATED_AT, RISK_SCORE,
        DW_INSERT_TIMESTAMP, DW_UPDATED_TIMESTAMP
    ) VALUES (
        S.PART_NUMBER, S.MANUFACTURER, S.WEIGHT_KG, S.UNIT_PRICE_USD,
        S.LIFECYCLE_STATUS, S.INSTALLATION_DATE, S.CERTIFICATION_STATUS,
        S.LEAD_TIME_DAYS, S.UPDATED_AT, S.RISK_SCORE,
        CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()
    );

    -- Capture DML counts from MERGE
    SELECT COUNT(*) INTO :v_insert_count
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET
    WHERE DW_INSERT_TIMESTAMP >= :v_start_ts;

    SELECT COUNT(*) INTO :v_update_count
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET
    WHERE DW_UPDATED_TIMESTAMP >= :v_start_ts AND DW_INSERT_TIMESTAMP < :v_start_ts
      AND LIFECYCLE_STATUS <> 'Decommissioned';

    SELECT COUNT(*) INTO :v_delete_count
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET
    WHERE DW_UPDATED_TIMESTAMP >= :v_start_ts AND LIFECYCLE_STATUS = 'Decommissioned';

    SELECT COUNT(*) INTO :v_tgt_after
    FROM GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.AEROSPACE_PARTS_TARGET;

    -- SECTION 5: Reconciliation
    INSERT INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.ETL_RECONCILIATION_LOG (
        RUN_ID, RUN_TIMESTAMP, SOURCE_COUNT, TARGET_COUNT_BEFORE, TARGET_COUNT_AFTER,
        INSERTED_COUNT, UPDATED_COUNT, SOFT_DELETED_COUNT, EXCLUDED_COUNT, STATUS, ERROR_MESSAGE
    ) VALUES (
        :v_run_id, :v_start_ts, :v_src_count, :v_tgt_before, :v_tgt_after,
        :v_insert_count, :v_update_count, :v_delete_count, :v_invalid_count, 'SUCCESS', NULL
    );

    -- SECTION 6: Error Handling
    v_result := OBJECT_CONSTRUCT(
        'run_id',           :v_run_id,
        'status',           'SUCCESS',
        'src_count',        :v_src_count,
        'dedup_count',      :v_dedup_count,
        'excluded_count',   :v_invalid_count,
        'inserted_count',   :v_insert_count,
        'updated_count',    :v_update_count,
        'soft_deleted_count',:v_delete_count,
        'tgt_before',       :v_tgt_before,
        'tgt_after',        :v_tgt_after
    )::VARCHAR;
    RETURN v_result;

EXCEPTION WHEN OTHER THEN
    INSERT INTO GEN_AI_POC_SNOWFLAKECOE.SDLC_WIZARD.ETL_RECONCILIATION_LOG (
        RUN_ID, RUN_TIMESTAMP, SOURCE_COUNT, TARGET_COUNT_BEFORE, TARGET_COUNT_AFTER,
        INSERTED_COUNT, UPDATED_COUNT, SOFT_DELETED_COUNT, EXCLUDED_COUNT, STATUS, ERROR_MESSAGE
    ) VALUES (
        :v_run_id, :v_start_ts, :v_src_count, :v_tgt_before, 0,
        0, 0, 0, 0, 'FAILED', SQLERRM
    );
    RETURN OBJECT_CONSTRUCT('error', SQLERRM, 'run_id', :v_run_id)::VARCHAR;
END;
$$;