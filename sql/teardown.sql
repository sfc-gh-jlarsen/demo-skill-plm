-- Removes everything created by setup.sql. Set the same values used in setup.sql.
SET DEMO_DB   = 'SKILL_DEMO_PLM_20261019';
SET DEMO_ROLE = '';   -- required

USE ROLE IDENTIFIER($DEMO_ROLE);
DROP DATABASE IF EXISTS IDENTIFIER($DEMO_DB);
