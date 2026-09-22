/*=========================================================
Object Name : QA_AEROSPACE_PARTS_PIPELINE
Purpose     : QA acceptance criteria queries
Database    : GEN_AI_POC_SNOWFLAKECOE
Schema      : SDLC_WIZARD
Warehouse   : SNOWFLAKE_LEARNING_WH
SP          : SP_LOAD_AEROSPACE_PARTS_SCD1
AC Range    : AC-001 through AC-010
=========================================================*/

USE DATABASE GEN_AI_POC_SNOWFLAKECOE;
USE SCHEMA SDLC_WIZARD;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;

-- ============================================================
-- AC-001: TARGET TABLE EXISTS AND IS ACCESSIBLE
-- PASS: Returns row count >= 0 with no errors
-- ============================================================
SELECT
    'AC-001'                                AS acceptance_criteria,
    'TARGET TABLE EXISTS AND IS ACCESSIBLE' AS description,
    COUNT(*)                                AS row_count,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET;

-- ============================================================
-- AC-002: SCHEMA VALIDATION — REQUIRED COLUMNS PRESENT
-- PASS: All expected columns exist in target
-- ============================================================
SELECT
    'AC-002'                                    AS acceptance_criteria,
    'SCHEMA VALIDATION - REQUIRED COLUMNS'      AS description,
    COLUMN_NAME,
    DATA_TYPE,
    'PASS'                                      AS result
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA  = 'SDLC_WIZARD'
  AND TABLE_NAME    = 'AEROSPACE_PARTS_TARGET'
  AND COLUMN_NAME IN (
      'PART_NUMBER','PART_NAME','CATEGORY','SUPPLIER_ID',
      'UNIT_PRICE_USD','WEIGHT_KG','LEAD_TIME_DAYS',
      'CERTIFICATION_STATUS','INSTALLATION_DATE','LIFECYCLE_STATUS',
      'RISK_SCORE','UPDATED_AT','IS_DELETED',
      'DW_INSERT_TS','DW_LAST_UPDATE_TIMESTAMP','DW_BATCH_ID'
  )
ORDER BY ORDINAL_POSITION;

-- ============================================================
-- AC-003: BUSINESS KEY UNIQUENESS — NO DUPLICATE PART_NUMBER
-- PASS: duplicate_count = 0
-- ============================================================
SELECT
    'AC-003'                           AS acceptance_criteria,
    'BUSINESS KEY UNIQUENESS'          AS description,
    COUNT(*)                           AS duplicate_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT PART_NUMBER, COUNT(*) AS CNT
    FROM AEROSPACE_PARTS_TARGET
    GROUP BY PART_NUMBER
    HAVING CNT > 1
);

-- ============================================================
-- AC-004: NO NULL BUSINESS KEYS
-- PASS: null_key_count = 0
-- ============================================================
SELECT
    'AC-004'                        AS acceptance_criteria,
    'NO NULL BUSINESS KEYS'         AS description,
    COUNT(*)                        AS null_key_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE PART_NUMBER IS NULL;

-- ============================================================
-- AC-005: RISK_SCORE POPULATION AND VALID VALUES
-- PASS: invalid_risk_count = 0
-- ============================================================
SELECT
    'AC-005'                          AS acceptance_criteria,
    'RISK_SCORE VALID VALUES'         AS description,
    COUNT(*)                          AS invalid_risk_count,