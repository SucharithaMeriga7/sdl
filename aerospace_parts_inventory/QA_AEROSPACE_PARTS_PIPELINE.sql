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
-- PASS: column_count = 19
-- ============================================================
SELECT
    'AC-002'                                  AS acceptance_criteria,
    'SCHEMA VALIDATION — REQUIRED COLUMNS'    AS description,
    COUNT(*)                                  AS column_count,
    CASE WHEN COUNT(*) = 19 THEN 'PASS' ELSE 'FAIL' END AS result
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'SDLC_WIZARD'
  AND TABLE_NAME   = 'AEROSPACE_PARTS_TARGET'
  AND COLUMN_NAME IN (
        'PART_NUMBER','MANUFACTURER','PART_NAME','CATEGORY',
        'LIFECYCLE_STATUS','INSTALLATION_DATE','CERTIFICATION_STATUS',
        'LEAD_TIME_DAYS','WEIGHT_KG','UNIT_PRICE_USD','SUPPLIER_ID',
        'WAREHOUSE_LOCATION','QUANTITY_ON_HAND','REORDER_THRESHOLD',
        'RISK_SCORE','STATUS','UPDATED_AT',
        'DW_INSERT_TIMESTAMP','DW_UPDATE_TIMESTAMP'
      );

-- ============================================================
-- AC-003: BUSINESS KEY UNIQUENESS — NO DUPLICATE PART_NUMBER
-- PASS: duplicate_count = 0
-- ============================================================
SELECT
    'AC-003'                                        AS acceptance_criteria,
    'BUSINESS KEY UNIQUENESS — NO DUPLICATE PART_NUMBER' AS description,
    COUNT(*)                                        AS duplicate_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT PART_NUMBER
    FROM AEROSPACE_PARTS_TARGET
    GROUP BY PART_NUMBER
    HAVING COUNT(*) > 1
) dups;

-- ============================================================
-- AC-004: MANUFACTURER UPPER-CASE TRANSFORMATION
-- PASS: non_upper_count = 0
-- ============================================================
SELECT
    'AC-004'                                        AS acceptance_criteria,
    'MANUFACTURER UPPER-CASE TRANSFORMATION'        AS description,
    COUNT(*)                                        AS non_upper_count,
    CASE WHEN COUNT(*) = 0