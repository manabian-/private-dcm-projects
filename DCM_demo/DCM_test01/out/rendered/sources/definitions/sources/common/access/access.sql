--------------------------------------------------
-- TASK実行ロールの作成
--------------------------------------------------

DEFINE ROLE ETL_TASK_ROLE;

--------------------------------------------------
-- ロール階層
--------------------------------------------------

GRANT ROLE ETL_TASK_ROLE
TO ROLE DCM_PROJECT_OWNER;

--------------------------------------------------
-- TASK実行ロールにWarehouseの利用権限を付与
--------------------------------------------------

GRANT USAGE ON WAREHOUSE DCM_DEMO_WH
TO ROLE ETL_TASK_ROLE;

--------------------------------------------------
-- TASK実行ロールにTASK実行権限を付与
--------------------------------------------------

GRANT EXECUTE TASK ON ACCOUNT
TO ROLE ETL_TASK_ROLE;

--------------------------------------------------
-- DCM Database/schemaの利用権限付与
--------------------------------------------------

GRANT USAGE ON DATABASE DCM_TEST01_DEV
TO ROLE ETL_TASK_ROLE;

GRANT USAGE ON SCHEMA DCM_TEST01_DEV.PROCEDURES
TO ROLE ETL_TASK_ROLE;

--------------------------------------------------
-- TASK実行ロールに共通ProcedureのUSAGE権限を付与
--------------------------------------------------

-- COPY_INTO
GRANT USAGE ON PROCEDURE DCM_TEST01_DEV.PROCEDURES.SP_COPY_v1(
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    BOOLEAN,
    BOOLEAN,
    NUMBER,
    BOOLEAN,
    BOOLEAN
)
TO ROLE ETL_TASK_ROLE;

-- CHECK COPY RESULT
GRANT USAGE ON PROCEDURE DCM_TEST01_DEV.PROCEDURES.SP_CHECK_COPY_RESULT_v1(
    VARCHAR,
    BOOLEAN,
    BOOLEAN
)
TO ROLE ETL_TASK_ROLE;

-- DELETE OLD ORDERS
GRANT USAGE ON PROCEDURE DCM_TEST01_DEV.PROCEDURES.SP_DELETE_OLD_ORDERS_v1(
    VARCHAR,
    NUMBER
)
TO ROLE ETL_TASK_ROLE;

-- MERGE ORDERS
GRANT USAGE ON PROCEDURE DCM_TEST01_DEV.PROCEDURES.SP_UPSERT_BRONZE_TO_SILVER_v1(
    VARCHAR,
    VARCHAR,
    ARRAY
)
TO ROLE ETL_TASK_ROLE;

-- UNLOAD FROM STREAM
GRANT USAGE ON PROCEDURE
    DCM_TEST01_DEV.PROCEDURES.SP_UNLOAD_FROM_STREAM_v1(
        VARCHAR,
        VARCHAR,
        VARCHAR,
        VARCHAR,
        VARCHAR,
        BOOLEAN,
        BOOLEAN,
        NUMBER,
        BOOLEAN,
        BOOLEAN,
        VARCHAR,
        BOOLEAN,
        VARCHAR,
        VARCHAR,
        VARCHAR,
        VARCHAR
    )
TO ROLE ETL_TASK_ROLE;

-- UNLOAD FROM TABLE
GRANT USAGE ON PROCEDURE
    DCM_TEST01_DEV.PROCEDURES.SP_UNLOAD_FROM_TABLE_v1(
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    BOOLEAN,
    BOOLEAN,
    NUMBER,
    BOOLEAN,
    BOOLEAN,
    VARCHAR,
    BOOLEAN,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR
    )
TO ROLE ETL_TASK_ROLE;