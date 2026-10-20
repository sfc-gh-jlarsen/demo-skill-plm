-- =============================================================================
-- Presenter safety net: returns the ground-truth answers for Scenarios A, B, C.
-- Run after setup.sql. Set DEMO_DB / DEMO_WH to match setup.sql.
-- =============================================================================
SET DEMO_DB = 'SKILL_DEMO_PLM_20261019';
SET DEMO_WH = '';   -- required

USE WAREHOUSE IDENTIFIER($DEMO_WH);
USE DATABASE IDENTIFIER($DEMO_DB);

-- Item -> PLM base part normalization used throughout:
--   strip '-', strip leading zeros, take 5 digits, prefix 'MT-'.

-- =============================================================================
-- SCENARIO A: Northfield Fleet Services (entry point: customer)
-- =============================================================================

-- A1. Entity resolution: CRM accounts vs ERP customers named like "Northfield".
--     Expect: CRM-A-1007 -> 100457 and 100458 (same email domain), Farm Supply is a different company,
--     CRM-A-1044 is an inactive duplicate.
WITH crm AS (
  SELECT a.ACCOUNT_ID, a.ACCOUNT_NAME, a.IS_ACTIVE,
         ANY_VALUE(SPLIT_PART(c.EMAIL,'@',2)) AS EMAIL_DOMAIN
  FROM CRM.ACCOUNTS a LEFT JOIN CRM.CONTACTS c USING (ACCOUNT_ID)
  WHERE a.ACCOUNT_NAME ILIKE '%northfield%'
  GROUP BY 1,2,3
)
SELECT crm.ACCOUNT_ID, crm.ACCOUNT_NAME, crm.IS_ACTIVE, e.CUST_NO, e.CUST_NAME,
       JAROWINKLER_SIMILARITY(UPPER(crm.ACCOUNT_NAME), e.CUST_NAME) AS NAME_SCORE,
       SPLIT_PART(e.BILL_TO_EMAIL,'@',2) = crm.EMAIL_DOMAIN       AS SAME_EMAIL_DOMAIN
FROM crm JOIN ERP.CUSTOMERS e ON e.CUST_NAME ILIKE 'NORTH%'
ORDER BY crm.ACCOUNT_ID, NAME_SCORE DESC;

-- A2. Northfield cases (expect 6 in the last 60 days, all vibration/shimmy).
SELECT CASE_ID, OPENED_AT::DATE AS OPENED, STATUS, PRODUCT_MENTIONED, SUBJECT
FROM CRM.SUPPORT_CASES
WHERE ACCOUNT_ID = 'CRM-A-1007' AND OPENED_AT >= DATEADD(day,-60,CURRENT_DATE())
ORDER BY OPENED_AT;

-- A3. What Northfield (both ERP customers) bought, normalized to PLM.
--     Expect: 48210A and 0048210 -> MT-48210 (MT-48210-A); one line of MT-55120 (no open changes).
SELECT o.CUST_NO, l.ITEM_NO,
       'MT-' || REGEXP_SUBSTR(LTRIM(REPLACE(l.ITEM_NO,'-',''),'0'),'^[0-9]{5}') AS BASE_PART,
       COUNT(*) AS LINES, SUM(l.QTY) AS UNITS
FROM ERP.SALES_ORDERS o JOIN ERP.ORDER_LINES l USING (SO_NO)
WHERE o.CUST_NO IN ('100457','100458')
GROUP BY 1,2,3 ORDER BY 1,2;

-- A4. Open changes on MT-48210-A and its BOM components, normalized.
--     Expect in flight: ECR-2026-014 (Approved) and MCR-VC-021 (WIP, via component MT-C-7712, no LINKED_ECR).
--     Excluded/done: ECR-2026-009 (Cancelled duplicate), ECR-2026-003 (Implemented), MCR-VC-015 (CLOSED).
WITH scope AS (
  SELECT 'MT-48210-A' AS PART_NUMBER, 'Finished part' AS VIA
  UNION ALL SELECT CHILD_PART, 'BOM component' FROM PLM.BOM WHERE PARENT_PART = 'MT-48210-A'
),
changes AS (
  SELECT 'ECR' AS TYPE, e.ECR_ID AS CHANGE_ID, e.STATUS, ap.PART_NUMBER, ap.FROM_REV || '->' || ap.TO_REV AS REV,
         NULL AS PLANT, e.TARGET_EFFECTIVE_DATE::TIMESTAMP_NTZ AS EFFECTIVE, e.DUPLICATE_OF, e.TITLE AS DESCRIPTION
  FROM PLM.ENGINEERING_CHANGE_REQUESTS e JOIN PLM.ECR_AFFECTED_PARTS ap USING (ECR_ID)
  UNION ALL
  SELECT 'MCR', m.MCR_ID, m.STATUS, m.PART_NUMBER, NULL, m.PLANT,
         CONVERT_TIMEZONE(COALESCE(pl.TIMESTAMP_ZONE,'UTC'), 'UTC', m.EFFECTIVE_TS),
         NULL, m.DESCRIPTION
  FROM MES.MANUFACTURING_CHANGE_REQUESTS m
  LEFT JOIN MES.PLANTS pl ON pl.PLANT = m.PLANT
)
SELECT c.TYPE, c.CHANGE_ID, c.STATUS, sm.NORMALIZED_STATUS, c.PART_NUMBER, s.VIA, c.REV, c.PLANT,
       c.EFFECTIVE AS EFFECTIVE_UTC, c.DUPLICATE_OF,
       (sm.NORMALIZED_STATUS LIKE 'In progress%' AND c.DUPLICATE_OF IS NULL) AS IN_FLIGHT,
       c.DESCRIPTION
FROM changes c
JOIN scope s USING (PART_NUMBER)
JOIN PUBLIC.STATUS_MAP sm ON sm.SOURCE = c.TYPE AND sm.SOURCE_STATUS = c.STATUS
ORDER BY IN_FLIGHT DESC, c.TYPE, c.CHANGE_ID;

-- A5. Exposure: Northfield lines/lots of MT-48210 and quality holds.
--     Expect: 6 lines, 720 units, 6 lots; 3 lots (L-VC-0102/0103/0105) on ACTIVE hold = 304 units.
--     5 of the 6 lots were produced at VC, where MCR-VC-021 is in progress.
SELECT o.CUST_NO, l.SO_NO, l.LINE_NO, l.ITEM_NO, l.QTY, l.LOT_NO, p.PLANT, p.PRODUCED_TS::DATE AS PRODUCED,
       h.HOLD_ID, h.STATUS AS HOLD_STATUS, h.REASON
FROM ERP.SALES_ORDERS o
JOIN ERP.ORDER_LINES l USING (SO_NO)
JOIN MES.PRODUCTION_LOTS p ON p.LOT_NO = l.LOT_NO
LEFT JOIN MES.QUALITY_HOLDS h ON h.LOT_NO = l.LOT_NO AND h.STATUS = 'ACTIVE'
WHERE o.CUST_NO IN ('100457','100458') AND p.PART_NUMBER = 'MT-48210-A'
ORDER BY l.SO_NO, l.LINE_NO;

SELECT COUNT(*) AS LINES, SUM(l.QTY) AS UNITS, COUNT(DISTINCT l.LOT_NO) AS LOTS,
       COUNT(DISTINCT h.LOT_NO) AS LOTS_ON_ACTIVE_HOLD,
       SUM(IFF(h.LOT_NO IS NOT NULL, l.QTY, 0)) AS UNITS_ON_ACTIVE_HOLD
FROM ERP.SALES_ORDERS o
JOIN ERP.ORDER_LINES l USING (SO_NO)
JOIN MES.PRODUCTION_LOTS p ON p.LOT_NO = l.LOT_NO
LEFT JOIN MES.QUALITY_HOLDS h ON h.LOT_NO = l.LOT_NO AND h.STATUS = 'ACTIVE'
WHERE o.CUST_NO IN ('100457','100458') AND p.PART_NUMBER = 'MT-48210-A';

-- =============================================================================
-- SCENARIO B: MT-61500 (entry point: part)
-- =============================================================================

-- B1. Supersession.  Expect: MT-61500-A Superseded by MT-61520-A.
SELECT PART_NUMBER, LIFECYCLE, SUPERSEDED_BY FROM PLM.PARTS
WHERE BASE_PART IN ('MT-61500','MT-61520') ORDER BY 1;

-- B2. Open changes on old + new part. Times converted to UTC using MES.PLANTS.TIMESTAMP_ZONE.
--     Expect: ECR-2026-022 (In Review, on MT-61520-A); MCR-LM-007 (OPEN, on MT-61500-A, future effective date).
SELECT 'ECR' AS TYPE, e.ECR_ID AS CHANGE_ID, e.STATUS, sm.NORMALIZED_STATUS, ap.PART_NUMBER, NULL AS PLANT,
       NULL::TIMESTAMP_NTZ AS EFFECTIVE_LOCAL, e.TARGET_EFFECTIVE_DATE::TIMESTAMP_NTZ AS EFFECTIVE_UTC,
       e.TARGET_EFFECTIVE_DATE > CURRENT_DATE() AS FUTURE
FROM PLM.ENGINEERING_CHANGE_REQUESTS e JOIN PLM.ECR_AFFECTED_PARTS ap USING (ECR_ID)
JOIN PUBLIC.STATUS_MAP sm ON sm.SOURCE = 'ECR' AND sm.SOURCE_STATUS = e.STATUS
WHERE ap.PART_NUMBER IN ('MT-61500-A','MT-61520-A') AND sm.NORMALIZED_STATUS LIKE 'In progress%'
UNION ALL
SELECT 'MCR', m.MCR_ID, m.STATUS, sm.NORMALIZED_STATUS, m.PART_NUMBER, m.PLANT,
       m.EFFECTIVE_TS,
       CONVERT_TIMEZONE(COALESCE(pl.TIMESTAMP_ZONE,'UTC'), 'UTC', m.EFFECTIVE_TS),
       m.EFFECTIVE_TS > CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
FROM MES.MANUFACTURING_CHANGE_REQUESTS m
LEFT JOIN MES.PLANTS pl ON pl.PLANT = m.PLANT
JOIN PUBLIC.STATUS_MAP sm ON sm.SOURCE = 'MCR' AND sm.SOURCE_STATUS = m.STATUS
WHERE m.PART_NUMBER IN ('MT-61500-A','MT-61520-A') AND sm.NORMALIZED_STATUS LIKE 'In progress%';

-- B3. Customers who ordered MT-61500 / MT-61520 in the last 90 days, with best CRM match.
--     Expect: 100702 BRIGHTWATER (high, exact name), 100703 CASTLN MTR HLDGS (medium, abbreviation),
--             100704 KMG RETAIL HOLDINGS (low by name; only the email domain matches Kestrel Motor Group).
WITH buyers AS (
  SELECT o.CUST_NO, LISTAGG(DISTINCT l.ITEM_NO, ', ') AS ITEMS, SUM(l.QTY) AS UNITS
  FROM ERP.SALES_ORDERS o JOIN ERP.ORDER_LINES l USING (SO_NO)
  WHERE 'MT-' || REGEXP_SUBSTR(LTRIM(REPLACE(l.ITEM_NO,'-',''),'0'),'^[0-9]{5}') IN ('MT-61500','MT-61520')
    AND o.ORDER_DATE >= DATEADD(day,-90,CURRENT_DATE())
  GROUP BY 1
),
crm AS (
  SELECT a.ACCOUNT_ID, a.ACCOUNT_NAME, ANY_VALUE(SPLIT_PART(c.EMAIL,'@',2)) AS EMAIL_DOMAIN
  FROM CRM.ACCOUNTS a LEFT JOIN CRM.CONTACTS c USING (ACCOUNT_ID)
  WHERE a.IS_ACTIVE GROUP BY 1,2
)
SELECT b.CUST_NO, e.CUST_NAME, b.ITEMS, b.UNITS, crm.ACCOUNT_ID, crm.ACCOUNT_NAME,
       JAROWINKLER_SIMILARITY(UPPER(crm.ACCOUNT_NAME), e.CUST_NAME) AS NAME_SCORE,
       SPLIT_PART(e.BILL_TO_EMAIL,'@',2) = crm.EMAIL_DOMAIN AS SAME_EMAIL_DOMAIN
FROM buyers b JOIN ERP.CUSTOMERS e USING (CUST_NO)
JOIN crm ON crm.EMAIL_DOMAIN = SPLIT_PART(e.BILL_TO_EMAIL,'@',2)
         OR JAROWINKLER_SIMILARITY(UPPER(crm.ACCOUNT_NAME), e.CUST_NAME) >= 85
QUALIFY ROW_NUMBER() OVER (PARTITION BY b.CUST_NO ORDER BY SAME_EMAIL_DOMAIN DESC, NAME_SCORE DESC) = 1
ORDER BY NAME_SCORE DESC;

-- =============================================================================
-- SCENARIO C: Alder Creek Logistics (clean result)
-- =============================================================================

-- C1. Parts Alder Creek bought and any in-flight change on them or their components.
--     Expect: MT-55120-A checked (plus 3 components); zero in-flight changes.
WITH parts AS (
  SELECT DISTINCT 'MT-' || REGEXP_SUBSTR(LTRIM(REPLACE(l.ITEM_NO,'-',''),'0'),'^[0-9]{5}') || '-A' AS PART_NUMBER
  FROM ERP.SALES_ORDERS o JOIN ERP.ORDER_LINES l USING (SO_NO) WHERE o.CUST_NO = '100601'
),
scope AS (
  SELECT PART_NUMBER FROM parts
  UNION SELECT b.CHILD_PART FROM PLM.BOM b JOIN parts p ON b.PARENT_PART = p.PART_NUMBER
),
inflight AS (
  SELECT ap.PART_NUMBER, e.ECR_ID AS CHANGE_ID FROM PLM.ENGINEERING_CHANGE_REQUESTS e
  JOIN PLM.ECR_AFFECTED_PARTS ap USING (ECR_ID)
  JOIN PUBLIC.STATUS_MAP sm ON sm.SOURCE='ECR' AND sm.SOURCE_STATUS=e.STATUS
  WHERE sm.NORMALIZED_STATUS LIKE 'In progress%' AND e.DUPLICATE_OF IS NULL
  UNION ALL
  SELECT m.PART_NUMBER, m.MCR_ID FROM MES.MANUFACTURING_CHANGE_REQUESTS m
  JOIN PUBLIC.STATUS_MAP sm ON sm.SOURCE='MCR' AND sm.SOURCE_STATUS=m.STATUS
  WHERE sm.NORMALIZED_STATUS LIKE 'In progress%'
)
SELECT s.PART_NUMBER, COUNT(i.CHANGE_ID) AS IN_FLIGHT_CHANGES
FROM scope s LEFT JOIN inflight i USING (PART_NUMBER)
GROUP BY 1 ORDER BY 1;
