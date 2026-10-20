-- =============================================================================
-- Meridian Tire & Rubber Co. -- CoCo Analyst Demo: "What's in flight, and who's exposed?"
-- Setup: database, four source-system schemas, comments, seed data, STATUS_MAP.
-- All data is fictional. Re-runnable (CREATE OR REPLACE).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Variables block: the ONLY place environment values live. Fill these in.
-- ---------------------------------------------------------------------------
SET DEMO_DB   = 'SKILL_DEMO_PLM_20261019';
SET DEMO_WH   = '';   -- required: warehouse to run setup with
SET DEMO_ROLE = '';   -- required: role that will own the demo database

-- Fail loudly if anything is unset.
EXECUTE IMMEDIATE $$
DECLARE
  missing_config EXCEPTION (-20001, 'Set DEMO_DB, DEMO_WH and DEMO_ROLE in the variables block at the top of setup.sql.');
BEGIN
  IF (COALESCE($DEMO_DB, '') = '' OR COALESCE($DEMO_WH, '') = '' OR COALESCE($DEMO_ROLE, '') = '') THEN
    RAISE missing_config;
  END IF;
  RETURN 'config ok';
END;
$$;

USE ROLE IDENTIFIER($DEMO_ROLE);
USE WAREHOUSE IDENTIFIER($DEMO_WH);
CREATE OR REPLACE DATABASE IDENTIFIER($DEMO_DB)
  COMMENT = 'Meridian Tire & Rubber Co. demo: CRM, ERP, PLM and MES source systems.';
USE DATABASE IDENTIFIER($DEMO_DB);

CREATE OR REPLACE SCHEMA CRM COMMENT = 'Sales and customer support system.';
CREATE OR REPLACE SCHEMA ERP COMMENT = 'Order management and item master system.';
CREATE OR REPLACE SCHEMA PLM COMMENT = 'Product lifecycle / engineering system: parts, BOMs, engineering change requests.';
CREATE OR REPLACE SCHEMA MES COMMENT = 'Manufacturing execution system: plant change requests, production lots, quality holds.';

-- =============================================================================
-- DDL
-- =============================================================================

-- ---------------- CRM ----------------
CREATE OR REPLACE TABLE CRM.ACCOUNTS (
  ACCOUNT_ID   STRING        COMMENT 'CRM account identifier.',
  ACCOUNT_NAME STRING        COMMENT 'Customer legal or trading name as entered by sales.',
  INDUSTRY     STRING        COMMENT 'Customer industry segment.',
  REGION       STRING        COMMENT 'Sales region.',
  IS_ACTIVE    BOOLEAN       COMMENT 'Whether the account is active.',
  CREATED_AT   TIMESTAMP_NTZ COMMENT 'When the account was created in CRM.'
) COMMENT = 'Customer accounts managed by sales.';

CREATE OR REPLACE TABLE CRM.CONTACTS (
  CONTACT_ID STRING COMMENT 'CRM contact identifier.',
  ACCOUNT_ID STRING COMMENT 'Account the contact belongs to.',
  FULL_NAME  STRING COMMENT 'Contact full name.',
  EMAIL      STRING COMMENT 'Contact email address.',
  ROLE       STRING COMMENT 'Contact job role.'
) COMMENT = 'People at customer accounts.';

CREATE OR REPLACE TABLE CRM.SUPPORT_CASES (
  CASE_ID           STRING        COMMENT 'Support case identifier.',
  ACCOUNT_ID        STRING        COMMENT 'Account that raised the case.',
  OPENED_AT         TIMESTAMP_NTZ COMMENT 'When the case was opened.',
  STATUS            STRING        COMMENT 'Case status.',
  PRODUCT_MENTIONED STRING        COMMENT 'Product referenced by the customer, as typed by the support agent.',
  SUBJECT           STRING        COMMENT 'Case subject line.',
  NOTES             STRING        COMMENT 'Support agent notes.'
) COMMENT = 'Customer support cases.';

-- ---------------- ERP ----------------
CREATE OR REPLACE TABLE ERP.CUSTOMERS (
  CUST_NO       STRING COMMENT 'ERP customer number.',
  CUST_NAME     STRING COMMENT 'Customer name on the ERP record.',
  SHIP_TO_NAME  STRING COMMENT 'Ship-to party name.',
  COUNTRY       STRING COMMENT 'Ship-to country.',
  BILL_TO_EMAIL STRING COMMENT 'Accounts payable email for invoicing.'
) COMMENT = 'Sold-to / ship-to customers in ERP.';

CREATE OR REPLACE TABLE ERP.ITEM_MASTER (
  ITEM_NO      STRING COMMENT 'ERP item number.',
  DESCRIPTION  STRING COMMENT 'Item description.',
  PRODUCT_LINE STRING COMMENT 'Product line code.',
  UOM          STRING COMMENT 'Unit of measure.'
) COMMENT = 'Sellable items.';

CREATE OR REPLACE TABLE ERP.SALES_ORDERS (
  SO_NO      STRING COMMENT 'Sales order number.',
  CUST_NO    STRING COMMENT 'Ordering customer.',
  ORDER_DATE DATE   COMMENT 'Order date.',
  SHIP_PLANT STRING COMMENT 'Plant the order ships from.'
) COMMENT = 'Sales order headers.';

CREATE OR REPLACE TABLE ERP.ORDER_LINES (
  SO_NO     STRING COMMENT 'Sales order number.',
  LINE_NO   NUMBER COMMENT 'Line number on the order.',
  ITEM_NO   STRING COMMENT 'Item ordered.',
  QTY       NUMBER COMMENT 'Quantity shipped.',
  LOT_NO    STRING COMMENT 'Production lot shipped on this line.',
  SHIP_DATE DATE   COMMENT 'Ship date.'
) COMMENT = 'Sales order lines with shipped lot.';

-- ---------------- PLM ----------------
CREATE OR REPLACE TABLE PLM.PARTS (
  PART_NUMBER   STRING COMMENT 'Engineering part number.',
  BASE_PART     STRING COMMENT 'Part number without revision.',
  REVISION      STRING COMMENT 'Revision letter.',
  DESCRIPTION   STRING COMMENT 'Engineering description.',
  PART_TYPE     STRING COMMENT 'FINISHED or COMPONENT.',
  LIFECYCLE     STRING COMMENT 'Lifecycle state.',
  SUPERSEDED_BY STRING COMMENT 'Replacement part number, if any.'
) COMMENT = 'Engineering part master.';

CREATE OR REPLACE TABLE PLM.BOM (
  PARENT_PART STRING       COMMENT 'Parent part number.',
  CHILD_PART  STRING       COMMENT 'Child part number.',
  QTY_PER     NUMBER(10,3) COMMENT 'Quantity of child per parent.'
) COMMENT = 'Engineering bill of materials.';

CREATE OR REPLACE TABLE PLM.ENGINEERING_CHANGE_REQUESTS (
  ECR_ID                STRING        COMMENT 'Engineering change request identifier.',
  TITLE                 STRING        COMMENT 'Short title.',
  DESCRIPTION           STRING        COMMENT 'Description of the change and its purpose.',
  STATUS                STRING        COMMENT 'Workflow status.',
  REQUESTED_BY          STRING        COMMENT 'Requesting engineer.',
  CREATED_AT            TIMESTAMP_NTZ COMMENT 'When the ECR was created.',
  TARGET_EFFECTIVE_DATE DATE          COMMENT 'Planned effective date.',
  DUPLICATE_OF          STRING        COMMENT 'ECR this one duplicates, if any.'
) COMMENT = 'Engineering change requests.';

CREATE OR REPLACE TABLE PLM.ECR_AFFECTED_PARTS (
  ECR_ID      STRING COMMENT 'Engineering change request identifier.',
  PART_NUMBER STRING COMMENT 'Affected part number.',
  FROM_REV    STRING COMMENT 'Revision before the change.',
  TO_REV      STRING COMMENT 'Revision after the change.'
) COMMENT = 'Parts affected by each engineering change request.';

-- ---------------- MES ----------------
CREATE OR REPLACE TABLE MES.MANUFACTURING_CHANGE_REQUESTS (
  MCR_ID       STRING        COMMENT 'Manufacturing change request identifier.',
  PLANT        STRING        COMMENT 'Plant code; see MES.PLANTS.',
  PART_NUMBER  STRING        COMMENT 'Part the change applies to.',
  DESCRIPTION  STRING        COMMENT 'Description of the process change.',
  STATUS       STRING        COMMENT 'Workflow status.',
  RAISED_TS    TIMESTAMP_NTZ COMMENT 'When the MCR was raised.',
  EFFECTIVE_TS TIMESTAMP_NTZ COMMENT 'When the change takes effect on the line.',
  LINKED_ECR   STRING        COMMENT 'Related engineering change request, if recorded.'
) COMMENT = 'Plant-level manufacturing change requests.';

CREATE OR REPLACE TABLE MES.PRODUCTION_LOTS (
  LOT_NO      STRING        COMMENT 'Production lot number.',
  PLANT       STRING        COMMENT 'Producing plant code.',
  PART_NUMBER STRING        COMMENT 'Part produced.',
  PRODUCED_TS TIMESTAMP_NTZ COMMENT 'When the lot was produced.',
  QTY         NUMBER        COMMENT 'Units produced.'
) COMMENT = 'Production lots.';

CREATE OR REPLACE TABLE MES.QUALITY_HOLDS (
  HOLD_ID   STRING        COMMENT 'Quality hold identifier.',
  LOT_NO    STRING        COMMENT 'Lot on hold.',
  REASON    STRING        COMMENT 'Reason for the hold.',
  STATUS    STRING        COMMENT 'ACTIVE or RELEASED.',
  PLACED_TS TIMESTAMP_NTZ COMMENT 'When the hold was placed.'
) COMMENT = 'Quality holds on production lots.';

CREATE OR REPLACE TABLE MES.PLANTS (
  PLANT          STRING COMMENT 'Plant code.',
  PLANT_NAME     STRING COMMENT 'Plant name.',
  COUNTRY        STRING COMMENT 'Country.',
  TIMESTAMP_ZONE STRING COMMENT 'Time zone the plant''s MES records timestamps in (IANA name).'
) COMMENT = 'Manufacturing plants.';

INSERT INTO MES.PLANTS VALUES
  ('HV','Harlow Valley','US','UTC'),
  ('PR','Port Ressing', 'US','UTC'),
  ('VC','Valcourt',     'MX','UTC'),
  ('LM','Lindmark',     'DE','Europe/Berlin');

-- ---------------- Shared ----------------
CREATE OR REPLACE TABLE PUBLIC.STATUS_MAP (
  SOURCE            STRING COMMENT 'ECR or MCR.',
  SOURCE_STATUS     STRING COMMENT 'Status value as stored in the source system.',
  NORMALIZED_STATUS STRING COMMENT 'Common status used for "in flight" reporting.'
) COMMENT = 'Maps ECR and MCR status vocabularies to one shared meaning of "in progress".';

INSERT INTO PUBLIC.STATUS_MAP VALUES
  ('ECR','Draft','Not started'),
  ('ECR','In Review','In progress'),
  ('ECR','Approved','In progress (pending implementation)'),
  ('ECR','Implemented','Done'),
  ('ECR','Cancelled','Excluded'),
  ('MCR','OPEN','In progress'),
  ('MCR','WIP','In progress'),
  ('MCR','CLOSED','Done'),
  ('MCR','REJ','Excluded');

-- =============================================================================
-- SCENARIO ROWS (hand-written, deterministic relative to run date)
-- =============================================================================

-- ---------------- CRM: scenario accounts ----------------
INSERT INTO CRM.ACCOUNTS VALUES
  ('CRM-A-1007','Northfield Fleet Services, Inc.','Transportation','US-Midwest', TRUE,  '2019-03-14 09:00:00'),
  ('CRM-A-1044','Northfield Fleet Services',      'Transportation','US-Midwest', FALSE, '2017-06-02 09:00:00'),
  ('CRM-A-1012','Northfield Farm Supply',         'Agriculture',   'US-Midwest', TRUE,  '2020-01-21 09:00:00'),
  ('CRM-A-1021','Alder Creek Logistics',          'Transportation','US-West',    TRUE,  '2021-08-09 09:00:00'),
  ('CRM-A-1031','Brightwater Auto Group',         'Auto Retail',   'US-East',    TRUE,  '2018-11-30 09:00:00'),
  ('CRM-A-1032','Castellan Motor Holdings LLC',   'Auto Retail',   'US-South',   TRUE,  '2022-02-17 09:00:00'),
  ('CRM-A-1033','Kestrel Motor Group',            'Auto Retail',   'US-East',    TRUE,  '2023-05-05 09:00:00');

INSERT INTO CRM.CONTACTS VALUES
  ('CON-5001','CRM-A-1007','Dana Whitcomb',  'dana.whitcomb@northfieldfleet.example',  'Fleet Maintenance Manager'),
  ('CON-5002','CRM-A-1007','Luis Ortega',    'luis.ortega@northfieldfleet.example',    'Purchasing'),
  ('CON-5003','CRM-A-1012','Marla Jensen',   'marla@northfieldfarmsupply.example',     'Owner'),
  ('CON-5004','CRM-A-1021','Priya Natarajan','priya.n@aldercreeklogistics.example',    'Operations Director'),
  ('CON-5005','CRM-A-1031','Tom Becker',     'tbecker@brightwaterauto.example',        'Service Director'),
  ('CON-5006','CRM-A-1032','Rae Castellan',  'rae@castellanmotors.example',            'CFO'),
  ('CON-5007','CRM-A-1033','Jordan Pike',    'jordan.pike@kestrelmotors.example',      'Parts Manager');

INSERT INTO CRM.SUPPORT_CASES VALUES
  ('CS-26-04101','CRM-A-1007', DATEADD(day,-58,CURRENT_DATE())::TIMESTAMP_NTZ, 'Closed',
   '48210 LT', 'Vibration complaint - unit 114',
   'Driver reports vibration at highway speed after tire swap on unit 114. Balanced twice, no change. Tires from recent shipment.'),
  ('CS-26-04117','CRM-A-1007', DATEADD(day,-44,CURRENT_DATE())::TIMESTAMP_NTZ, 'Working',
   'LT all-terrain 48210', 'Shimmy on new tires',
   'Fleet manager says steering shimmy over 60 mph on 4 trucks. All on the new LT all-terrain set. Requested replacement.'),
  ('CS-26-04122','CRM-A-1007', DATEADD(day,-37,CURRENT_DATE())::TIMESTAMP_NTZ, 'Escalated',
   'the light truck tire', 'Repeat vibration - escalating',
   'Third vibration report this month. Customer suspects tire uniformity, not balance. Wants an engineering answer.'),
  ('CS-26-04130','CRM-A-1007', DATEADD(day,-25,CURRENT_DATE())::TIMESTAMP_NTZ, 'Working',
   '265/70R17 LT', 'West yard vibration',
   'West region yard (Boise) now seeing the same vibration at highway speed on recently delivered tires.'),
  ('CS-26-04138','CRM-A-1007', DATEADD(day,-14,CURRENT_DATE())::TIMESTAMP_NTZ, 'New',
   'LT AT 48210', 'Ride quality complaint',
   'Drivers report a shake around 55-65 mph. Road force measured high on two tires.'),
  ('CS-26-04144','CRM-A-1007', DATEADD(day,-6,CURRENT_DATE())::TIMESTAMP_NTZ,  'New',
   'light truck all terrain', 'Request credit for replacements',
   'Customer asking for credit on 24 replacement tires due to vibration/shimmy. Account team copied.'),
  ('CS-26-04150','CRM-A-1012', DATEADD(day,-30,CURRENT_DATE())::TIMESTAMP_NTZ, 'Working',
   'farm implement 70100', 'Sidewall cracking on implement tires',
   'Implement tires showing sidewall weather cracking after one season in storage.'),
  ('CS-26-04160','CRM-A-1021', DATEADD(day,-70,CURRENT_DATE())::TIMESTAMP_NTZ, 'Closed',
   '55120 regional', 'Delivery paperwork',
   'Missing packing list on delivery; resent. No product issue.');

-- ---------------- ERP: scenario customers ----------------
INSERT INTO ERP.CUSTOMERS VALUES
  ('100457','NORTHFIELD FLEET SVCS',   'NORTHFIELD FLEET SVCS - DES MOINES','US','ap@northfieldfleet.example'),
  ('100458','NORTHFIELD FLEET (WEST)', 'NORTHFIELD FLEET WEST - BOISE',     'US','ap@northfieldfleet.example'),
  ('100512','NORTHFLD FARM SUPPLY',    'NORTHFLD FARM SUPPLY',              'US','office@northfieldfarmsupply.example'),
  ('100601','ALDER CREEK LOGISTICS',   'ALDER CREEK LOGISTICS - RENO',      'US','payables@aldercreeklogistics.example'),
  ('100702','BRIGHTWATER AUTO GROUP',  'BRIGHTWATER AUTO GROUP',            'US','ap@brightwaterauto.example'),
  ('100703','CASTLN MTR HLDGS',        'CASTLN MTR HLDGS - HOUSTON',        'US',NULL),
  ('100704','KMG RETAIL HOLDINGS',     'KMG RETAIL HOLDINGS #0412',         'US','ap@kestrelmotors.example');

-- ---------------- PLM: scenario parts ----------------
INSERT INTO PLM.PARTS VALUES
  ('MT-48210-A','MT-48210','A','LT all-terrain 265/70R17 load range E','FINISHED','Active',NULL),
  ('MT-61500-A','MT-61500','A','Passenger touring 215/55R17 (legacy)', 'FINISHED','Superseded','MT-61520-A'),
  ('MT-61520-A','MT-61520','A','Passenger touring 215/55R17',          'FINISHED','Active',NULL),
  ('MT-55120-A','MT-55120','A','Commercial regional haul 295/75R22.5', 'FINISHED','Active',NULL),
  ('MT-C-7712', 'MT-C-7712',NULL,'Tread compound, LT all-terrain',     'COMPONENT','Active',NULL),
  ('MT-C-7718', 'MT-C-7718',NULL,'Tread compound, passenger touring',  'COMPONENT','Active',NULL),
  ('MT-C-7720', 'MT-C-7720',NULL,'Steel belt package',                 'COMPONENT','Active',NULL),
  ('MT-C-7731', 'MT-C-7731',NULL,'Body ply cord, polyester',           'COMPONENT','Active',NULL),
  ('MT-C-7745', 'MT-C-7745',NULL,'Bead wire bundle',                   'COMPONENT','Active',NULL),
  ('MT-C-7750', 'MT-C-7750',NULL,'Inner liner compound',               'COMPONENT','Active',NULL),
  ('MT-C-7760', 'MT-C-7760',NULL,'Tread compound, commercial',         'COMPONENT','Active',NULL);

INSERT INTO PLM.BOM VALUES
  ('MT-48210-A','MT-C-7712',1),('MT-48210-A','MT-C-7720',1),('MT-48210-A','MT-C-7731',2),
  ('MT-48210-A','MT-C-7745',2),('MT-48210-A','MT-C-7750',1),
  ('MT-61500-A','MT-C-7718',1),('MT-61500-A','MT-C-7720',1),('MT-61500-A','MT-C-7731',1),('MT-61500-A','MT-C-7750',1),
  ('MT-61520-A','MT-C-7718',1),('MT-61520-A','MT-C-7720',1),('MT-61520-A','MT-C-7731',1),('MT-61520-A','MT-C-7750',1),
  ('MT-55120-A','MT-C-7760',1),('MT-55120-A','MT-C-7720',2),('MT-55120-A','MT-C-7745',2);

INSERT INTO PLM.ENGINEERING_CHANGE_REQUESTS VALUES
  ('ECR-2026-003','Second-source carbon black for MT-C-7712',
   'Qualify a second-source carbon black supplier for the LT all-terrain tread compound. Validation complete.',
   'Implemented','R. Halvorsen', DATEADD(day,-210,CURRENT_DATE())::TIMESTAMP_NTZ, DATEADD(day,-150,CURRENT_DATE()), NULL),
  ('ECR-2026-009','Ply angle change for 48210 uniformity',
   'Change ply angle on 48210 to improve uniformity at speed.',
   'Cancelled','S. Mbeki', DATEADD(day,-40,CURRENT_DATE())::TIMESTAMP_NTZ, DATEADD(day,30,CURRENT_DATE()), 'ECR-2026-014'),
  ('ECR-2026-014','Cord-ply angle adjustment, MT-48210',
   'Adjust body-ply cord angle to address high-speed uniformity (radial force variation) on the LT all-terrain 265/70R17. Revision A to B.',
   'Approved','A. Lindqvist', DATEADD(day,-35,CURRENT_DATE())::TIMESTAMP_NTZ, DATEADD(day,25,CURRENT_DATE()), NULL),
  ('ECR-2026-022','Inner-liner gauge reduction, MT-61520',
   'Reduce inner-liner gauge on the passenger touring 215/55R17 for weight and rolling resistance.',
   'In Review','K. Osei', DATEADD(day,-18,CURRENT_DATE())::TIMESTAMP_NTZ, DATEADD(day,60,CURRENT_DATE()), NULL);

INSERT INTO PLM.ECR_AFFECTED_PARTS VALUES
  ('ECR-2026-003','MT-C-7712', NULL, NULL),
  ('ECR-2026-009','MT-48210-A','A','B'),
  ('ECR-2026-014','MT-48210-A','A','B'),
  ('ECR-2026-022','MT-61520-A','A','B');

-- ---------------- MES: scenario MCRs, lots, holds ----------------
INSERT INTO MES.MANUFACTURING_CHANGE_REQUESTS VALUES
  ('MCR-VC-015','VC','MT-48210-A',
   'Switch bead seat lubricant to water-based formulation.',
   'CLOSED', DATEADD(day,-150,CURRENT_DATE())::TIMESTAMP_NTZ, DATEADD(day,-120,CURRENT_DATE())::TIMESTAMP_NTZ, NULL),
  ('MCR-VC-021','VC','MT-C-7712',
   'Cure time adjustment on press bank C after compound viscosity drift observed in incoming tread compound.',
   'WIP', DATEADD(day,-28,CURRENT_DATE())::TIMESTAMP_NTZ, DATEADD(day,5,CURRENT_DATE())::TIMESTAMP_NTZ, NULL),
  ('MCR-LM-007','LM','MT-61500-A',
   'Extend inner-liner splice overlap on the legacy touring line until production transitions to the replacement part.',
   'OPEN', DATEADD(day,-10,CURRENT_DATE())::TIMESTAMP_NTZ,
   DATEADD(hour,6,DATEADD(day,12,CURRENT_DATE())::TIMESTAMP_NTZ), NULL);

INSERT INTO MES.PRODUCTION_LOTS VALUES
  ('L-VC-0101','VC','MT-48210-A', DATEADD(day,-100,CURRENT_DATE())::TIMESTAMP_NTZ, 400),
  ('L-VC-0102','VC','MT-48210-A', DATEADD(day,-95, CURRENT_DATE())::TIMESTAMP_NTZ, 400),
  ('L-VC-0103','VC','MT-48210-A', DATEADD(day,-55, CURRENT_DATE())::TIMESTAMP_NTZ, 400),
  ('L-VC-0104','VC','MT-48210-A', DATEADD(day,-40, CURRENT_DATE())::TIMESTAMP_NTZ, 400),
  ('L-VC-0105','VC','MT-48210-A', DATEADD(day,-38, CURRENT_DATE())::TIMESTAMP_NTZ, 400),
  ('L-VC-0106','VC','MT-48210-A', DATEADD(day,-36, CURRENT_DATE())::TIMESTAMP_NTZ, 400),
  ('L-HV-0420','HV','MT-48210-A', DATEADD(day,-420,CURRENT_DATE())::TIMESTAMP_NTZ, 500),
  ('L-LM-0201','LM','MT-61500-A', DATEADD(day,-30, CURRENT_DATE())::TIMESTAMP_NTZ, 600),
  ('L-LM-0202','LM','MT-61500-A', DATEADD(day,-60, CURRENT_DATE())::TIMESTAMP_NTZ, 600),
  ('L-LM-0203','LM','MT-61500-A', DATEADD(day,-85, CURRENT_DATE())::TIMESTAMP_NTZ, 600),
  ('L-LM-0204','LM','MT-61500-A', DATEADD(day,-200,CURRENT_DATE())::TIMESTAMP_NTZ, 600),
  ('L-LM-0205','LM','MT-61520-A', DATEADD(day,-80, CURRENT_DATE())::TIMESTAMP_NTZ, 300),
  ('L-PR-0301','PR','MT-55120-A', DATEADD(day,-50, CURRENT_DATE())::TIMESTAMP_NTZ, 500),
  ('L-PR-0302','PR','MT-55120-A', DATEADD(day,-25, CURRENT_DATE())::TIMESTAMP_NTZ, 500),
  ('L-PR-0303','PR','MT-55120-A', DATEADD(day,-10, CURRENT_DATE())::TIMESTAMP_NTZ, 500),
  ('L-PR-0304','PR','MT-55120-A', DATEADD(day,-60, CURRENT_DATE())::TIMESTAMP_NTZ, 500);

INSERT INTO MES.QUALITY_HOLDS VALUES
  ('QH-0090','L-VC-0106','Uniformity out of spec (radial force variation above limit)','RELEASED', DATEADD(day,-34,CURRENT_DATE())::TIMESTAMP_NTZ),
  ('QH-0101','L-VC-0102','Uniformity out of spec (radial force variation above limit)','ACTIVE',   DATEADD(day,-33,CURRENT_DATE())::TIMESTAMP_NTZ),
  ('QH-0102','L-VC-0103','Uniformity out of spec (radial force variation above limit)','ACTIVE',   DATEADD(day,-33,CURRENT_DATE())::TIMESTAMP_NTZ),
  ('QH-0103','L-VC-0105','Uniformity out of spec (radial force variation above limit)','ACTIVE',   DATEADD(day,-20,CURRENT_DATE())::TIMESTAMP_NTZ);

-- ---------------- ERP: scenario items and orders ----------------
INSERT INTO ERP.ITEM_MASTER VALUES
  ('48210A',  'LT AT 265/70R17 E',          'LT','EA'),
  ('0048210', 'LT A/T 265/70R17 LRE (OLD)', 'LT','EA'),
  ('61500A',  'PSG TOURING 215/55R17',      'PS','EA'),
  ('61500-A', 'PSG TOUR 215/55R17 DLR PK',  'PS','EA'),
  ('61520A',  'PSG TOURING 215/55R17 NEW',  'PS','EA'),
  ('55120A',  'COMM REGIONAL 295/75R22.5',  'CM','EA');

INSERT INTO ERP.SALES_ORDERS VALUES
  ('SO-480022','100457', DATEADD(day,-400,CURRENT_DATE()),'HV'),
  ('SO-500101','100457', DATEADD(day,-90, CURRENT_DATE()),'VC'),
  ('SO-500118','100457', DATEADD(day,-45, CURRENT_DATE()),'VC'),
  ('SO-500125','100458', DATEADD(day,-30, CURRENT_DATE()),'VC'),
  ('SO-500130','100512', DATEADD(day,-120,CURRENT_DATE()),'HV'),
  ('SO-500140','100702', DATEADD(day,-20, CURRENT_DATE()),'LM'),
  ('SO-500151','100703', DATEADD(day,-50, CURRENT_DATE()),'LM'),
  ('SO-500163','100704', DATEADD(day,-75, CURRENT_DATE()),'LM'),
  ('SO-500170','100601', DATEADD(day,-40, CURRENT_DATE()),'PR'),
  ('SO-500171','100601', DATEADD(day,-15, CURRENT_DATE()),'PR');

INSERT INTO ERP.ORDER_LINES VALUES
  ('SO-480022',1,'0048210',200,'L-HV-0420', DATEADD(day,-397,CURRENT_DATE())),
  ('SO-500101',1,'48210A', 120,'L-VC-0101', DATEADD(day,-87, CURRENT_DATE())),
  ('SO-500101',2,'48210A',  80,'L-VC-0102', DATEADD(day,-87, CURRENT_DATE())),
  ('SO-500118',1,'48210A', 160,'L-VC-0103', DATEADD(day,-42, CURRENT_DATE())),
  ('SO-500118',2,'55120A',  40,'L-PR-0304', DATEADD(day,-42, CURRENT_DATE())),
  ('SO-500125',1,'48210A',  96,'L-VC-0104', DATEADD(day,-27, CURRENT_DATE())),
  ('SO-500125',2,'48210A',  64,'L-VC-0105', DATEADD(day,-27, CURRENT_DATE())),
  ('SO-500130',1,'70100A',  60,'L-HV-1000', DATEADD(day,-117,CURRENT_DATE())),
  ('SO-500140',1,'61500A', 240,'L-LM-0201', DATEADD(day,-17, CURRENT_DATE())),
  ('SO-500151',1,'61500-A',180,'L-LM-0202', DATEADD(day,-47, CURRENT_DATE())),
  ('SO-500163',1,'61500A', 300,'L-LM-0203', DATEADD(day,-72, CURRENT_DATE())),
  ('SO-500163',2,'61520A', 100,'L-LM-0205', DATEADD(day,-72, CURRENT_DATE())),
  ('SO-500170',1,'55120A', 400,'L-PR-0301', DATEADD(day,-37, CURRENT_DATE())),
  ('SO-500171',1,'55120A', 300,'L-PR-0302', DATEADD(day,-12, CURRENT_DATE()));

-- =============================================================================
-- FILLER ROWS (generated, deterministic -- no RANDOM())
-- Filler parts are MT-70100..MT-71335 and MT-C-81xx; they never touch scenario parts.
-- =============================================================================

-- CRM filler accounts (54)
INSERT INTO CRM.ACCOUNTS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 54)))
SELECT
  'CRM-A-' || (2000 + i),
  GET(ARRAY_CONSTRUCT('Summit','Granite','Bluewater','Redline','Ironwood','Clearpath','Harbor','Pinecrest','Silverline','Oakridge','Westgate','Stonebridge'), MOD(i,12))::STRING
    || ' ' || GET(ARRAY_CONSTRUCT('Transport','Tire Center','Auto Supply','Fleet Leasing','Distribution'), FLOOR(i/12))::STRING,
  GET(ARRAY_CONSTRUCT('Transportation','Tire Retail','Auto Retail','Leasing','Distribution'), FLOOR(i/12))::STRING,
  GET(ARRAY_CONSTRUCT('US-East','US-West','US-South','US-Midwest','Canada','Mexico'), MOD(i,6))::STRING,
  MOD(i,17) <> 16,
  DATEADD(day, -(400 + i*23), '2026-01-01'::DATE)::TIMESTAMP_NTZ
FROM g;

-- CRM filler contacts (one per filler account)
INSERT INTO CRM.CONTACTS
SELECT
  'CON-' || (6000 + ROW_NUMBER() OVER (ORDER BY ACCOUNT_ID)),
  ACCOUNT_ID,
  GET(ARRAY_CONSTRUCT('Alex Moran','Jamie Cho','Sam Ruiz','Taylor Grant','Morgan Price','Casey Lund'), MOD(ROW_NUMBER() OVER (ORDER BY ACCOUNT_ID),6))::STRING,
  'contact' || (6000 + ROW_NUMBER() OVER (ORDER BY ACCOUNT_ID)) || '@' || LOWER(REPLACE(ACCOUNT_NAME,' ','')) || '.example',
  GET(ARRAY_CONSTRUCT('Purchasing','Fleet Manager','Owner','Service Manager'), MOD(ROW_NUMBER() OVER (ORDER BY ACCOUNT_ID),4))::STRING
FROM CRM.ACCOUNTS WHERE ACCOUNT_ID >= 'CRM-A-2000';

-- CRM filler cases (292)
INSERT INTO CRM.SUPPORT_CASES
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS s FROM TABLE(GENERATOR(ROWCOUNT => 292)))
SELECT
  'CS-26-' || (10000 + s),
  'CRM-A-' || (2000 + MOD(s,54)),
  DATEADD(day, -MOD(s*7, 365), CURRENT_DATE())::TIMESTAMP_NTZ,
  GET(ARRAY_CONSTRUCT('Closed','Closed','Working','New','Escalated','Closed'), MOD(s,6))::STRING,
  GET(ARRAY_CONSTRUCT('part ','','item #','tire '), MOD(s,4))::STRING || (70100 + MOD(s*3,96)*13),
  GET(ARRAY_CONSTRUCT('Delivery delay','Invoice question','Warranty claim','Tread wear question','Pricing request','Damaged in transit'), MOD(s,6))::STRING,
  GET(ARRAY_CONSTRUCT('Customer asked for updated ETA.','Invoice total did not match PO; corrected.','Warranty claim submitted for one tire with sidewall damage.','Customer asked about expected tread life.','Requested volume pricing for next quarter.','Two tires arrived with damaged wrap; replacement sent.'), MOD(s,6))::STRING
FROM g;

-- ERP filler customers (54, mirror filler CRM accounts in uppercase)
INSERT INTO ERP.CUSTOMERS
SELECT
  (101000 + (SUBSTR(ACCOUNT_ID,7)::INT - 2000))::STRING,
  UPPER(ACCOUNT_NAME),
  UPPER(ACCOUNT_NAME),
  IFF(REGION = 'Canada','CA', IFF(REGION = 'Mexico','MX','US')),
  'ap@' || LOWER(REPLACE(ACCOUNT_NAME,' ','')) || '.example'
FROM CRM.ACCOUNTS WHERE ACCOUNT_ID >= 'CRM-A-2000';

-- PLM filler finished parts (96) and components (13)
INSERT INTO PLM.PARTS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 96)))
SELECT
  'MT-' || (70100 + i*13) || '-A',
  'MT-' || (70100 + i*13),
  'A',
  GET(ARRAY_CONSTRUCT('Passenger all-season','Light truck highway','Commercial drive axle','Off-road loader'), MOD(i,4))::STRING || ' series ' || (70100 + i*13),
  'FINISHED',
  IFF(MOD(i,19) = 18, 'Obsolete', 'Active'),
  NULL
FROM g;

INSERT INTO PLM.PARTS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS j FROM TABLE(GENERATOR(ROWCOUNT => 13)))
SELECT
  'MT-C-' || (8100 + j*7), 'MT-C-' || (8100 + j*7), NULL,
  GET(ARRAY_CONSTRUCT('Sidewall compound','Apex filler','Cap ply nylon','Chafer fabric','Belt edge strip','Tread base compound'), MOD(j,6))::STRING || ' ' || (8100 + j*7),
  'COMPONENT', 'Active', NULL
FROM g;

-- PLM filler BOM (two filler components per filler finished part)
INSERT INTO PLM.BOM
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 96)))
SELECT 'MT-' || (70100 + i*13) || '-A', 'MT-C-' || (8100 + MOD(i,13)*7), 1 FROM g
UNION ALL
SELECT 'MT-' || (70100 + i*13) || '-A', 'MT-C-' || (8100 + MOD(i+5,13)*7), 2 FROM g;

-- PLM filler ECRs (36: ECR-2026-001..040 minus scenario IDs)
INSERT INTO PLM.ENGINEERING_CHANGE_REQUESTS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 40)))
SELECT
  'ECR-2026-' || LPAD(n,3,'0'),
  GET(ARRAY_CONSTRUCT('Label update','Mold vent revision','Sidewall marking change','Packaging change','Compound cost reduction','Tolerance update'), MOD(n,6))::STRING
    || ', MT-' || (70100 + MOD(n*7,96)*13),
  GET(ARRAY_CONSTRUCT('Update DOT and sidewall labeling.','Revise mold vent pattern to reduce flash.','Change sidewall lettering per marketing request.','Move to recyclable packaging.','Substitute lower-cost filler with equivalent performance.','Tighten bead diameter tolerance.'), MOD(n,6))::STRING,
  GET(ARRAY_CONSTRUCT('Draft','In Review','Approved','Implemented','Cancelled'), MOD(n,5))::STRING,
  GET(ARRAY_CONSTRUCT('R. Halvorsen','S. Mbeki','A. Lindqvist','K. Osei','P. Duarte'), MOD(n,5))::STRING,
  DATEADD(day, -(5 + MOD(n*13,300)), CURRENT_DATE())::TIMESTAMP_NTZ,
  DATEADD(day, 60 - (5 + MOD(n*13,300)), CURRENT_DATE()),
  NULL
FROM g WHERE n NOT IN (3,9,14,22);

INSERT INTO PLM.ECR_AFFECTED_PARTS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 40)))
SELECT 'ECR-2026-' || LPAD(n,3,'0'), 'MT-' || (70100 + MOD(n*7,96)*13) || '-A', 'A', 'B'
FROM g WHERE n NOT IN (3,9,14,22);

-- MES filler MCRs (27)
INSERT INTO MES.MANUFACTURING_CHANGE_REQUESTS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 27)))
SELECT
  'MCR-' || GET(ARRAY_CONSTRUCT('HV','PR','VC','LM'), MOD(i,4))::STRING || '-' || LPAD(30 + i,3,'0'),
  GET(ARRAY_CONSTRUCT('HV','PR','VC','LM'), MOD(i,4))::STRING,
  IFF(MOD(i,2) = 0, 'MT-C-' || (8100 + MOD(i,13)*7), 'MT-' || (70100 + MOD(i*5,96)*13) || '-A'),
  GET(ARRAY_CONSTRUCT('Adjust extruder temperature profile.','Replace bladder supplier.','Change mixer cycle sequence.','Update building drum setting.','Revise inspection frequency.'), MOD(i,5))::STRING,
  GET(ARRAY_CONSTRUCT('OPEN','WIP','CLOSED','REJ','CLOSED'), MOD(i,5))::STRING,
  DATEADD(day, -(20 + i*9), CURRENT_DATE())::TIMESTAMP_NTZ,
  DATEADD(day, -(6 + i*9), CURRENT_DATE())::TIMESTAMP_NTZ,
  IFF(MOD(i,3) = 0 AND i <> 21, 'ECR-2026-' || LPAD(i+1,3,'0'), NULL)
FROM g;

-- MES filler lots (480) -- filler parts only, produced well before filler orders ship
INSERT INTO MES.PRODUCTION_LOTS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS k FROM TABLE(GENERATOR(ROWCOUNT => 480)))
SELECT
  'L-' || GET(ARRAY_CONSTRUCT('HV','PR','VC','LM'), MOD(k,4))::STRING || '-' || (1000 + k),
  GET(ARRAY_CONSTRUCT('HV','PR','VC','LM'), MOD(k,4))::STRING,
  'MT-' || (70100 + MOD(k,96)*13) || '-A',
  DATEADD(day, -(380 + MOD(k,30)), CURRENT_DATE())::TIMESTAMP_NTZ,
  200 + MOD(k,5)*100
FROM g;

-- MES filler holds (21)
INSERT INTO MES.QUALITY_HOLDS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 21)))
SELECT
  'QH-' || LPAD(i+1,4,'0'),
  'L-' || GET(ARRAY_CONSTRUCT('HV','PR','VC','LM'), MOD(i*23,4))::STRING || '-' || (1000 + i*23),
  GET(ARRAY_CONSTRUCT('Visual defect - blister','Bead area porosity','Cure record incomplete','Label misprint'), MOD(i,4))::STRING,
  IFF(MOD(i,3) = 0, 'ACTIVE', 'RELEASED'),
  IFF(MOD(i,3) = 0, DATEADD(day, -(1 + MOD(i,3)), CURRENT_DATE()), DATEADD(day, -(370 + MOD(i*23,30)), CURRENT_DATE()))::TIMESTAMP_NTZ
FROM g;

-- ERP filler items: one primary per filler part (two formats) + legacy zero-padded for even parts (96 + 48)
INSERT INTO ERP.ITEM_MASTER
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 96)))
SELECT
  IFF(MOD(i,2) = 0, (70100 + i*13) || 'A', (70100 + i*13) || '-A'),
  GET(ARRAY_CONSTRUCT('PSG ALL-SEASON','LT HWY','COMM DRIVE','OTR LOADER'), MOD(i,4))::STRING || ' ' || (70100 + i*13),
  GET(ARRAY_CONSTRUCT('PS','LT','CM','OR'), MOD(i,4))::STRING,
  'EA'
FROM g
UNION ALL
SELECT
  '00' || (70100 + i*13),
  GET(ARRAY_CONSTRUCT('PSG ALL-SEASON','LT HWY','COMM DRIVE','OTR LOADER'), MOD(i,4))::STRING || ' ' || (70100 + i*13) || ' (OLD)',
  GET(ARRAY_CONSTRUCT('PS','LT','CM','OR'), MOD(i,4))::STRING,
  'EA'
FROM g WHERE MOD(i,2) = 0;

-- ERP filler order lines (1,986) and their order headers
CREATE OR REPLACE TEMPORARY TABLE ERP._FILLER_LINES AS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS s FROM TABLE(GENERATOR(ROWCOUNT => 1986))),
x AS (SELECT s, MOD(s,96) AS p, FLOOR(s/3) AS o FROM g)
SELECT
  'SO-' || (600000 + o)                                                   AS SO_NO,
  o                                                                       AS O,
  MOD(s,3) + 1                                                            AS LINE_NO,
  IFF(MOD(p,2) = 0 AND MOD(s,7) = 0, '00' || (70100 + p*13),
      IFF(MOD(p,2) = 0, (70100 + p*13) || 'A', (70100 + p*13) || '-A'))   AS ITEM_NO,
  10 + MOD(s,9)*10                                                        AS QTY,
  'L-' || GET(ARRAY_CONSTRUCT('HV','PR','VC','LM'), MOD(p + 96*MOD(FLOOR(s/96),5),4))::STRING
       || '-' || (1000 + p + 96*MOD(FLOOR(s/96),5))                       AS LOT_NO,
  DATEADD(day, 2 - (4 + MOD(o*17,365)), CURRENT_DATE())                   AS SHIP_DATE
FROM x;

INSERT INTO ERP.SALES_ORDERS
SELECT DISTINCT
  SO_NO,
  (101000 + MOD(O,54))::STRING,
  DATEADD(day, -(4 + MOD(O*17,365)), CURRENT_DATE()),
  GET(ARRAY_CONSTRUCT('HV','PR','VC','LM'), MOD(O,4))::STRING
FROM ERP._FILLER_LINES;

INSERT INTO ERP.ORDER_LINES
SELECT SO_NO, LINE_NO, ITEM_NO, QTY, LOT_NO, SHIP_DATE FROM ERP._FILLER_LINES;

DROP TABLE ERP._FILLER_LINES;

-- Row-count summary
SELECT 'CRM.ACCOUNTS' t, COUNT(*) n FROM CRM.ACCOUNTS UNION ALL
SELECT 'CRM.CONTACTS', COUNT(*) FROM CRM.CONTACTS UNION ALL
SELECT 'CRM.SUPPORT_CASES', COUNT(*) FROM CRM.SUPPORT_CASES UNION ALL
SELECT 'ERP.CUSTOMERS', COUNT(*) FROM ERP.CUSTOMERS UNION ALL
SELECT 'ERP.ITEM_MASTER', COUNT(*) FROM ERP.ITEM_MASTER UNION ALL
SELECT 'ERP.SALES_ORDERS', COUNT(*) FROM ERP.SALES_ORDERS UNION ALL
SELECT 'ERP.ORDER_LINES', COUNT(*) FROM ERP.ORDER_LINES UNION ALL
SELECT 'PLM.PARTS', COUNT(*) FROM PLM.PARTS UNION ALL
SELECT 'PLM.BOM', COUNT(*) FROM PLM.BOM UNION ALL
SELECT 'PLM.ENGINEERING_CHANGE_REQUESTS', COUNT(*) FROM PLM.ENGINEERING_CHANGE_REQUESTS UNION ALL
SELECT 'PLM.ECR_AFFECTED_PARTS', COUNT(*) FROM PLM.ECR_AFFECTED_PARTS UNION ALL
SELECT 'MES.MANUFACTURING_CHANGE_REQUESTS', COUNT(*) FROM MES.MANUFACTURING_CHANGE_REQUESTS UNION ALL
SELECT 'MES.PRODUCTION_LOTS', COUNT(*) FROM MES.PRODUCTION_LOTS UNION ALL
SELECT 'MES.QUALITY_HOLDS', COUNT(*) FROM MES.QUALITY_HOLDS UNION ALL
SELECT 'MES.PLANTS', COUNT(*) FROM MES.PLANTS UNION ALL
SELECT 'PUBLIC.STATUS_MAP', COUNT(*) FROM PUBLIC.STATUS_MAP;
