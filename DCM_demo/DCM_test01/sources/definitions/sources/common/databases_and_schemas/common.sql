--------------------------------------------------
-- DCM管理対象Database
--------------------------------------------------

DEFINE DATABASE {{ database }}
WITH
    COMMENT = 'Database managed by DCM_TEST01 project'
;

--------------------------------------------------
-- 共通Procedure用Schema
--------------------------------------------------

DEFINE SCHEMA {{ database }}.PROCEDURES
WITH
    COMMENT = 'Common procedures used by ETL pipelines'
;