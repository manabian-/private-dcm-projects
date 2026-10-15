-- DCM PROJECTの事前準備作業ファイル

USE ROLE ACCOUNTADMIN;

--------------------------------------------------
-- DCM Project格納場所
--------------------------------------------------

CREATE DATABASE IF NOT EXISTS DCM_ADMIN;

CREATE SCHEMA IF NOT EXISTS DCM_ADMIN.PROJECTS;

--------------------------------------------------
-- DCM Project Ownerロールの作成
--------------------------------------------------

CREATE ROLE IF NOT EXISTS DCM_PROJECT_OWNER;

GRANT USAGE ON DATABASE DCM_ADMIN
TO ROLE DCM_PROJECT_OWNER;

GRANT USAGE ON SCHEMA DCM_ADMIN.PROJECTS
TO ROLE DCM_PROJECT_OWNER;

GRANT CREATE DCM PROJECT ON SCHEMA DCM_ADMIN.PROJECTS
TO ROLE DCM_PROJECT_OWNER;

--------------------------------------------------
-- DCMオーナーがDatabase/WHを作成できる権限を付与
--------------------------------------------------

GRANT CREATE DATABASE ON ACCOUNT
TO ROLE DCM_PROJECT_OWNER;

GRANT CREATE WAREHOUSE ON ACCOUNT
TO ROLE DCM_PROJECT_OWNER;

--------------------------------------------------
-- ユーザーがRoleを利用できるようにする
--------------------------------------------------

GRANT ROLE DCM_PROJECT_OWNER
-- USER名を記載する
TO USER TOSHIHIKO;

--------------------------------------------------
-- STORAGE INTEGRATIONの作成と権限付与
--------------------------------------------------

CREATE STORAGE INTEGRATION IF NOT EXISTS SI_INBOUND
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = AZURE
  ENABLED = TRUE
  AZURE_TENANT_ID = '532fb247-45f8-436c-b567-3b996e912a5b'
  STORAGE_ALLOWED_LOCATIONS = (
    'azure://adlszealast01.blob.core.windows.net/snowpipe-test/inbound/'
  );

DESC INTEGRATION SI_INBOUND;

GRANT USAGE ON INTEGRATION SI_INBOUND
TO ROLE DCM_PROJECT_OWNER
WITH GRANT OPTION;

--------------------------------------------------
-- DCMオーナーがTASK用Roleを作成できる権限を付与
--------------------------------------------------

GRANT CREATE ROLE ON ACCOUNT
TO ROLE DCM_PROJECT_OWNER;

GRANT EXECUTE TASK ON ACCOUNT
TO ROLE DCM_PROJECT_OWNER
WITH GRANT OPTION;

--------------------------------------------------
-- WHを作成
--------------------------------------------------

CREATE WAREHOUSE IF NOT EXISTS DCM_DEMO_WH
with
    warehouse_size = 'XSMALL'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'Warehouse for DCM DEMO'
;

--------------------------------------------------
-- DCMオーナーがWHを利用できる権限を付与
--------------------------------------------------

GRANT USAGE ON WAREHOUSE DCM_DEMO_WH
TO ROLE DCM_PROJECT_OWNER
WITH GRANT OPTION;