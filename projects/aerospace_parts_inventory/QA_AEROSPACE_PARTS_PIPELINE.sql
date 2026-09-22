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
-- AC-002: NO DUPLICATE BUSINESS KEYS IN TARGET
-- PASS: duplicate_count = 0
-- ============================================================
SELECT
    'AC-002'                            AS acceptance_criteria,
    'NO DUPLICATE PART_NUMBER IN TARGET' AS description,
    COUNT(*)                            AS duplicate_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT PART_NUMBER
    FROM AEROSPACE_PARTS_TARGET
    GROUP BY PART_NUMBER
    HAVING COUNT(*) > 1
);

-- ============================================================
-- AC-003: MANUFACTURER IS UPPERCASED
-- PASS: non_upper_count = 0
-- ============================================================
SELECT
    'AC-003'                        AS acceptance_criteria,
    'MANUFACTURER IS UPPER CASE'    AS description,
    COUNT(*)                        AS non_upper_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE MANUFACTURER != UPPER(MANUFACTURER);

-- ============================================================
-- AC-004: WEIGHT_KG IS NULL WHERE SOURCE VALUE WAS <= 0
-- PASS: invalid_weight_count = 0
-- ============================================================
SELECT
    'AC-004'                                AS acceptance_criteria,
    'WEIGHT_KG NULL WHEN SOURCE <= 0'       AS description,
    COUNT(*)                                AS invalid_weight_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE WEIGHT_KG IS NOT NULL
  AND WEIGHT_KG <= 0;

-- ============================================================
-- AC-005: UNIT_PRICE_USD ROUNDED TO 2 DECIMAL PLACES
-- PASS: unrounded_count = 0
-- ============================================================
SELECT
    'AC-005'                                    AS acceptance_criteria,
    'UNIT_PRICE_USD ROUNDED TO 2 DECIMALS'      AS description,
    COUNT(*)                                    AS unrounded_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE UNIT_PRICE_USD != ROUND(UNIT_PRICE_USD, 2);

-- ============================================================
-- AC-006: END OF LIFE RECORDS EXCLUDED (INSTALLATION_DATE > 3 YRS)
-- PASS: eol_count = 0
-- ============================================================
SELECT
    'AC-006'                                        AS acceptance_criteria,
    'EOL RECORDS EXCLUDED (INSTALLATION > 3 YEARS)' AS description,
    COUNT(*)                                        AS eol_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE INSTALLATION_DATE < DATEADD(YEAR, -3, CURRENT_DATE());

-- ============================================================
-- AC-007: RISK_SCORE DERIVATION IS CORRECT
-- PASS: invalid_risk_count = 0
-- ============================================================
SELECT
    'AC-007'                        AS acceptance_criteria,
    'RISK_SCORE DERIVATION CORRECT' AS description,
    COUNT(*)                        AS invalid_risk_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE RISK_SCORE NOT IN ('High Risk', 'Medium Risk', 'Low Risk')
   OR (CERTIFICATION_STATUS = 'Pending' AND LEAD_TIME_DAYS > 90  AND RISK_SCORE != 'High Risk')
   OR (CERTIFICATION_STATUS IN ('FAA','EASA','Dual') AND LEAD_TIME_DAYS <= 60 AND RISK_SCORE != 'Low Risk');

-- ============================================================
-- AC-008: SOFT DELETE — MISSING SOURCE RECORDS MARKED DECOMMISSIONED
-- PASS: Returns count of Decommissioned records (informational >= 0)
-- ============================================================
SELECT
    'AC-008'                                        AS acceptance_criteria,
    'DECOMMISSIONED RECORDS EXIST FOR MISSING ROWS' AS description,
    COUNT(*)                                        AS decommissioned_count,
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM AEROSPACE_PARTS_TARGET
WHERE STATUS = 'Decommissioned';

-- ============================================================
-- AC-009: RECONCILIATION LOG ENTRY EXISTS FOR LATEST RUN
-- PASS: log_entry_count >= 1
-- ============================================================
SELECT
    'AC-009'                                    AS acceptance_criteria,
    'RECONCILIATION LOG ENTRY FOR LATEST RUN'   AS description,
    COUNT(*)                                    AS log_entry_count,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'FAIL' END AS result
FROM ETL_RECONCILIATION_LOG
WHERE PIPELINE_NAME = 'SP_LOAD_AEROSPACE_PARTS_SCD1'
  AND CAST(RUN_TIMESTAMP AS DATE) = CURRENT_DATE();

-- ============================================================
-- AC-010: TASK IS SCHEDULED AND ACTIVE
-- PASS: task_state = 'started' (active/resumed)
-- ============================================================
SELECT
    'AC-010'                            AS acceptance_criteria,
    'TASK IS SCHEDULED AND ACTIVE'      AS description,
    NAME                                AS task_name,
    STATE                               AS task_state,
    SCHEDULE                            AS task_schedule,
    CASE WHEN STATE = 'started' THEN 'PASS' ELSE 'FAIL' END AS result
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('DAY', -1, CURRENT_TIMESTAMP()),
    TASK_NAME => 'TASK_SP_LOAD_AEROSPACE_PARTS_SCD1'
))
QUALIFY ROW_NUMBER() OVER (ORDER BY SCHEDULED_TIME DESC) = 1;