--------------------------------------------------
-- DCM管理対象Database
--------------------------------------------------

DEFINE DATABASE DCM_TEST01_DEV
WITH
    COMMENT = 'Database managed by DCM_TEST01 project'
;

--------------------------------------------------
-- 共通Procedure用Schema
--------------------------------------------------

DEFINE SCHEMA DCM_TEST01_DEV.PROCEDURES
WITH
    COMMENT = 'Common procedures used by ETL pipelines'
;