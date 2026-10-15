{# PL_demo01で使用するSchema #}
{% set app_schema = 'PL_DEMO01' %}

{# このファイルで定義するオブジェクト名 #}
{% set object_namespace = database ~ '.' ~ app_schema %}

{% set orders_bronze_table = object_namespace ~ '.ORDERS_BRONZE' %}
{% set orders_silver_table = object_namespace ~ '.ORDERS' %}
{% set orders_stream = object_namespace ~ '.ORDERS_STREAM' %}

{% set move_orders_files_task = object_namespace ~ '.TASK_MOVE_ORDERS_FILES' %}
{% set copy_orders_task = object_namespace ~ '.TASK_COPY_ORDERS' %}
{% set merge_orders_task = object_namespace ~ '.TASK_MERGE_ORDERS' %}
{% set cleanup_orders_bronze_task = object_namespace ~ '.TASK_CLEANUP_ORDERS_BRONZE' %}
{% set unload_orders_cdc_task = object_namespace ~ '.TASK_UNLOAD_ORDERS_CDC' %}

{# bronze tableの削除期間 #}
{% set retention_days = 60 %}

-- Orders の Bronze / Silver、Stream、Task Graph をこのファイルで管理する。
-- SQL ファイルの並び順はデプロイ順序ではない。

-- schema
DEFINE SCHEMA {{ database }}.{{ app_schema }};

-- Ingest:ソースファイルを配置するADLSパス
DEFINE STAGE {{ database }}.{{ app_schema }}.SOURCE_STAGE
    URL = 'azure://adlszealast01.blob.core.windows.net/snowpipe-test/inbound/PL_demo01'
    STORAGE_INTEGRATION = SI_INBOUND;

-- output:unload出力先ADLSパス
DEFINE STAGE {{ database }}.{{ app_schema }}.OUTPUT_STAGE
    URL = 'azure://adlszealast01.blob.core.windows.net/snowpipe-test/inbound/PL_demo01'
    STORAGE_INTEGRATION = SI_INBOUND;
    
-- Bronze: 原文の文字列を保持し、COPY のメタデータを監査列に記録する。
DEFINE TABLE {{ orders_bronze_table }} (
    ORDER_ID VARCHAR,
    CUSTOMER_NAME VARCHAR,
    AMOUNT VARCHAR,
    ORDER_DATE VARCHAR,
    AUDIT__INGEST_TIMESTAMP TIMESTAMP_LTZ,
    AUDIT__UPDATE_TIMESTAMP TIMESTAMP_LTZ
);

-- Silver: 型を揃え、ORDER_ID ごとに最新のレコードを保持する。
DEFINE TABLE {{ orders_silver_table }} (
    ORDER_ID NUMBER,
    CUSTOMER_NAME VARCHAR,
    AMOUNT NUMBER(18, 2),
    ORDER_DATE DATE,
    AUDIT__INGEST_TIMESTAMP TIMESTAMP_LTZ,
    AUDIT__UPDATE_TIMESTAMP TIMESTAMP_LTZ
)
    CHANGE_TRACKING = TRUE;

DEFINE STREAM {{ orders_stream }}
    ON TABLE {{ orders_silver_table }}
    APPEND_ONLY = FALSE
    SHOW_INITIAL_ROWS = FALSE;

-- file moveは一旦削除

DEFINE TASK {{ copy_orders_task }}
    WAREHOUSE = '{{ warehouse }}'
    TIMEZONE = 'UTC', AUTOCOMMIT = TRUE
    -- {# SCHEDULE = '{{ schedule }}' #}
    -- {# AFTER {{ move_orders_files_task }} #}
    SUSPENDED
AS
DECLARE
    copy_result VARCHAR;
    check_result VARCHAR;
BEGIN
    CALL {{ database }}.PROCEDURES.SP_COPY(
        P_TARGET_TABLE => '{{ orders_bronze_table }}',
        -- ファイル移動を行わないのでsource stageを読み取る
        P_SOURCE_STAGE => '{{ database }}.{{ app_schema }}.SOURCE_STAGE',
        P_SOURCE_PATH => 'source/',
        P_FILE_FORMAT => $$
            TYPE = CSV
            PARSE_HEADER = TRUE
            FIELD_OPTIONALLY_ENCLOSED_BY = '"'
            ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
        $$,
        P_MATCH_BY_COLUMN_NAME => 'CASE_INSENSITIVE',
        P_INCLUDE_METADATA => $$
            AUDIT__INGEST_TIMESTAMP = METADATA$FILE_LAST_MODIFIED,
            AUDIT__UPDATE_TIMESTAMP = METADATA$START_SCAN_TIME
        $$,
        P_ON_ERROR => 'SKIP_FILE',
        P_FORCE => FALSE,
        P_PURGE => FALSE
    ) INTO :copy_result;

    CALL SYSTEM$SET_RETURN_VALUE(:copy_result);

    -- ファイル単位の失敗と COPY SQL 自体の失敗のどちらも後続を停止する。
    CALL {{ database }}.PROCEDURES.SP_CHECK_COPY_RESULT(
        :copy_result, TRUE, TRUE
    ) INTO :check_result;

END;

DEFINE TASK {{ merge_orders_task }}
    WAREHOUSE = '{{ warehouse }}'
    TIMEZONE = 'UTC', AUTOCOMMIT = TRUE
    AFTER {{ copy_orders_task }}
    STARTED
AS
DECLARE
    merge_result VARIANT;
    return_value VARCHAR;
BEGIN
    CALL {{ database }}.PROCEDURES.SP_UPSERT_BRONZE_TO_SILVER(
        P_TARGET_TABLE => '{{ orders_silver_table }}',
        P_SOURCE_SQL => $$
            SELECT
                TRY_CAST(ORDER_ID AS NUMBER) AS ORDER_ID,
                CUSTOMER_NAME,
                TRY_CAST(AMOUNT AS NUMBER(18, 2)) AS AMOUNT,
                TRY_CAST(ORDER_DATE AS DATE) AS ORDER_DATE,
                AUDIT__INGEST_TIMESTAMP,
                AUDIT__UPDATE_TIMESTAMP
            FROM {{ orders_bronze_table }}
        $$,
        P_PRIMARY_KEYS => ARRAY_CONSTRUCT('ORDER_ID')
    ) INTO :merge_result;

    return_value := TO_JSON(:merge_result);


    CALL SYSTEM$SET_RETURN_VALUE(:return_value);
END;

DEFINE TASK {{ cleanup_orders_bronze_task }}
    WAREHOUSE = '{{ warehouse }}'
    TIMEZONE = 'UTC', AUTOCOMMIT = TRUE
    AFTER {{ merge_orders_task }}
    STARTED
AS
DECLARE
    delete_result VARCHAR DEFAULT 'SKIPPED: retention_days <= 0';
BEGIN
    -- Silver の MERGE が成功した後に Bronze だけを削除する。
    IF ({{ retention_days }} > 0) THEN
        CALL {{ database }}.PROCEDURES.SP_DELETE_OLD_ORDERS(
            P_TARGET_TABLE => '{{ orders_bronze_table }}',
            RETENTION_DAYS => {{ retention_days }}
        ) INTO :delete_result;
    END IF;

    CALL SYSTEM$SET_RETURN_VALUE(:delete_result);
END;

DEFINE TASK {{ unload_orders_cdc_task }}
    WAREHOUSE = '{{ warehouse }}'
    TIMEZONE = 'UTC', AUTOCOMMIT = TRUE
    AFTER {{ cleanup_orders_bronze_task }}
    WHEN SYSTEM$STREAM_HAS_DATA('{{ orders_stream }}')
    STARTED
AS
DECLARE
    unload_query_id VARCHAR;
BEGIN
    CALL {{ database }}.PROCEDURES.SP_UNLOAD_FROM_STREAM(
        P_TARGET_STAGE => '{{ database }}.{{ app_schema }}.OUTPUT_STAGE',
        P_TARGET_PATH => 'output/',
        P_SOURCE_QUERY => $$
            SELECT
                ORDER_ID,
                CUSTOMER_NAME,
                AMOUNT,
                ORDER_DATE,
                CONVERT_TIMEZONE('UTC', AUDIT__INGEST_TIMESTAMP)::TIMESTAMP_NTZ(0) AS AUDIT__INGEST_TIMESTAMP,
                CONVERT_TIMEZONE('UTC', AUDIT__UPDATE_TIMESTAMP)::TIMESTAMP_NTZ(0) AS AUDIT__UPDATE_TIMESTAMP,
                METADATA$ACTION AS AUDIT_METADATA_ACTION,
                METADATA$ISUPDATE AS AUDIT_METADATA_ISUPDATE,
                METADATA$ROW_ID AS AUDIT_METADATA_ROW_ID
            FROM {{ orders_stream }}
        $$,
        P_FILE_FORMAT => $$
            TYPE = PARQUET
            COMPRESSION = SNAPPY
        $$,
        P_PARTITION_BY => $$
            'audit__ingest_timestamp=' ||
            TO_VARCHAR(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP()),
                       'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        $$,
        P_MAX_FILE_SIZE => 268435456,
        P_INCLUDE_QUERY_ID => TRUE,
        P_DETAILED_OUTPUT => TRUE
    ) INTO :unload_query_id;

    CALL SYSTEM$SET_RETURN_VALUE(:unload_query_id);
END;