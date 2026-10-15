



--------------------------------------------------
-- Schema
--------------------------------------------------

GRANT USAGE
ON SCHEMA DCM_TEST01_DEV.PL_DEMO01
TO ROLE ETL_TASK_ROLE;


--------------------------------------------------
-- Bronze
-- SP_COPY      : INSERT
-- SP_UPSERT    : SELECT
-- SP_DELETE    : DELETE
--------------------------------------------------

GRANT SELECT, INSERT, DELETE
ON TABLE DCM_TEST01_DEV.PL_DEMO01.ORDERS_BRONZE
TO ROLE ETL_TASK_ROLE;


--------------------------------------------------
-- Silver
-- SP_UPSERT : SELECT / INSERT / UPDATE
--------------------------------------------------

GRANT SELECT, INSERT, UPDATE
ON TABLE DCM_TEST01_DEV.PL_DEMO01.ORDERS
TO ROLE ETL_TASK_ROLE;


--------------------------------------------------
-- Stream
-- SP_UNLOADで参照
--------------------------------------------------

GRANT SELECT
ON STREAM DCM_TEST01_DEV.PL_DEMO01.ORDERS_STREAM
TO ROLE ETL_TASK_ROLE;


--------------------------------------------------
-- Source Stage
-- SP_COPYで参照
--------------------------------------------------

GRANT USAGE
ON STAGE DCM_TEST01_DEV.PL_DEMO01.SOURCE_STAGE
TO ROLE ETL_TASK_ROLE;


--------------------------------------------------
-- UNLOAD Stage
--------------------------------------------------

GRANT USAGE
ON STAGE DCM_TEST01_DEV.PL_DEMO01.OUTPUT_STAGE
TO ROLE ETL_TASK_ROLE;