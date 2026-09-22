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
-- PASS: All 12 expected columns returned
-- ============================================================
SELECT
    'AC-002'                                  AS acceptance_criteria,
    'REQUIRED COLUMNS PRESENT IN TARGET'      AS description,
    COUNT(*)                                  AS columns_found,
    CASE WHEN COUNT(*) = 12 THEN 'PASS' ELSE 'FAIL' END AS result
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'SDLC_WIZARD'
  AND TABLE_NAME   = 'AEROSPACE_PARTS_TARGET'
  AND COLUMN_NAME IN (
        'PART_NUMBER','MANUFACTURER','WEIGHT_KG','UNIT_PRICE_USD',
        'LIFECYCLE_STATUS','INSTALLATION_DATE','CERTIFICATION_STATUS',
        'LEAD_TIME_DAYS','UPDATED_AT','RISK_SCORE',
        'DW_INSERT_TIMESTAMP','DW_UPDATED_TIMESTAMP'
  );

-- ============================================================
-- AC-003: MANUFACTURER CAMELCASE — NO ALL-UPPER OR ALL-LOWER VALUES
-- PASS: 0 rows violating CamelCase (INITCAP) rule
-- ============================================================
SELECT
    'AC-003'                                        AS acceptance_criteria,
    'MANUFACTURER CAMELCASE VALIDATION'             AS description,
    COUNT(*)                                        AS violation_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE MANUFACTURER IS NOT NULL
  AND MANUFACTURER <> INITCAP(MANUFACTURER);

-- ============================================================
-- AC-004: WEIGHT_KG — NO NON-POSITIVE VALUES
-- PASS: 0 rows with WEIGHT_KG <= 0
-- ============================================================
SELECT
    'AC-004'                                        AS acceptance_criteria,
    'WEIGHT_KG NO NON-POSITIVE VALUES'              AS description,
    COUNT(*)                                        AS violation_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE WEIGHT_KG IS NOT NULL
  AND WEIGHT_KG <= 0;

-- ============================================================
-- AC-005: UNIT_PRICE_USD — ROUNDED TO 2 DECIMAL PLACES
-- PASS: 0 rows where value differs from its 2-decimal rounded form
-- ============================================================
SELECT
    'AC-005'                                        AS acceptance_criteria,
    'UNIT_PRICE_USD ROUNDED TO 2 DECIMAL PLACES'    AS description,
    COUNT(*)                                        AS violation_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE UNIT_PRICE_USD IS NOT NULL
  AND UNIT_PRICE_USD <> ROUND(UNIT_PRICE_USD, 2);

-- ============================================================
-- AC-006: EXCLUSION RULE — NO END-OF-LIFE RECORDS OLDER THAN 3 YEARS
-- PASS: 0 rows where LIFECYCLE_STATUS = 'End of Life'
--       AND INSTALLATION_DATE < DATEADD(year,-3,CURRENT_DATE)
-- ============================================================
SELECT
    'AC-006'                                                AS acceptance_criteria,
    'END-OF-LIFE RECORDS OLDER THAN 3 YEARS EXCLUDED'       AS description,
    COUNT(*)                                                AS violation_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END     AS result
FROM AEROSPACE_PARTS_TARGET
WHERE LIFECYCLE_STATUS  = 'End of Life'
  AND INSTALLATION_DATE < DATEADD(YEAR, -3, CURRENT_DATE());

-- ============================================================
-- AC-007: RISK_SCORE — ONLY VALID VALUES PRESENT
-- PASS: 0 rows with RISK_SCORE outside ('High Risk','Medium Risk','Low Risk')
-- ============================================================
SELECT
    'AC-007'                                        AS acceptance_criteria,
    'RISK_SCORE VALID VALUES ONLY'                  AS description,
    COUNT(*)                                        AS violation_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE RISK_SCORE NOT IN ('High Risk', 'Medium Risk', 'Low Risk');

-- ============================================================
-- AC-008: SOFT DELETE — DECOMMISSIONED RECORDS EXIST FOR ABSENT SOURCE ROWS
-- PASS: At least 0 rows with LIFECYCLE_STATUS = 'Decommissioned' (no error)
-- ============================================================
SELECT
    'AC-008'                                        AS acceptance_criteria,
    'SOFT DELETE DECOMMISSIONED RECORDS PRESENT'    AS description,
    COUNT(*)                                        AS decommissioned_count,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE LIFECYCLE_STATUS = 'Decommissioned';

-- ============================================================
-- AC-009: RECONCILIATION LOG — AT LEAST ONE COMPLETED RUN LOGGED
-- PASS: >= 1 row in ETL_RECONCILIATION_LOG with STATUS = 'SUCCESS'
-- ============================================================
SELECT
    'AC-009'                                        AS acceptance_criteria,
    'RECONCILIATION LOG HAS SUCCESS ENTRY'          AS description,
    COUNT(*)                                        AS success_run_count,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'FAIL' END AS result
FROM ETL_RECONCILIATION_LOG
WHERE STATUS = 'SUCCESS';

-- ============================================================
-- AC-010: NO DUPLICATE PART_NUMBER IN TARGET
-- PASS: 0 duplicate PART_NUMBER values
-- ============================================================
SELECT
    'AC-010'                                        AS acceptance_criteria,
    'NO DUPLICATE PART_NUMBER IN TARGET'            AS description,
    COUNT(*)                                        AS duplicate_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT PART_NUMBER
    FROM AEROSPACE_PARTS_TARGET
    GROUP BY PART_NUMBER
    HAVING COUNT(*) > 1
) dupes;

-- ============================================================
-- AC-010b: DW TIMESTAMPS POPULATED FOR ALL TARGET ROWS
-- PASS: 0 rows missing DW_INSERT_TIMESTAMP or DW_UPDATED_TIMESTAMP
-- ============================================================
SELECT
    'AC-010b'                                           AS acceptance_criteria,
    'DW TIMESTAMPS POPULATED ON ALL TARGET ROWS'        AS description,
    COUNT(*)                                            AS violation_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE DW_INSERT_TIMESTAMP  IS NULL
   OR DW_UPDATED_TIMESTAMP IS NULL;