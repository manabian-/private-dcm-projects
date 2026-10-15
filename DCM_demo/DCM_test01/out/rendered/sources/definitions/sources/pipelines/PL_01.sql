-- DATABASE/SCHEMA/TABLE定義

DEFINE DATABASE COPY_TEST_DB;
DEFINE SCHEMA COPY_TEST_DB_DEV.TEST_SCHEMA;

DEFINE TABLE COPY_TEST_DB_DEV.TEST_SCHEMA.ORDERS (
    ORDER_ID                 VARCHAR,
    CUSTOMER_NAME            VARCHAR,
    AMOUNT                   VARCHAR,
    ORDER_DATE               VARCHAR,
    AUDIT__INGEST_TIMESTAMP  TIMESTAMP_LTZ,
    AUDIT__UPDATE_TIMESTAMP  TIMESTAMP_LTZ
);

-- STAGE 定義
define stage DCM_FILEMOVE_DEV.RAW.SOURCE_STAGE
with
    url = 'azure://adlszealast01.blob.core.windows.net/snowpipe-test/inbound/dcm-filemove/source/'
    storage_integration = SI_INBOUND
    file_format = DCM_FILEMOVE_DEV.RAW.CSV_FORMAT
;

define stage DCM_FILEMOVE_DEV.RAW.LANDING_STAGE
with
    url = 'azure://adlszealast01.blob.core.windows.net/snowpipe-test/inbound/dcm-filemove/archive/'
    storage_integration = SI_INBOUND
    file_format = DCM_FILEMOVE_DEV.RAW.CSV_FORMAT
;