-- ============================================================
-- DCM Project Deploy Script
-- ============================================================

-- ------------------------------------------------------------
-- 0. Execution Role
-- ------------------------------------------------------------

USE ROLE DCM_PROJECT_OWNER;

-- ------------------------------------------------------------
-- 1. Parameters
--    この部分は最初に実行する
-- ------------------------------------------------------------

SET DCM_DATABASE         = 'DCM_ADMIN';
SET DCM_SCHEMA           = 'PROJECTS';
SET DCM_PROJECT_NAME     = 'DCM_TEST01';

-- DCM Project の定義ファイルが存在する Workspace
-- 配置先Workspaceに合わせて都度変更する
SET DCM_SOURCE_PATH =
    'snow://workspace/USER$.PUBLIC.DEFAULT$/versions/live/DCM_demo/DCM_test01';

-- manifest.yml の templating configuration
SET DCM_CONFIGURATION    = 'DEV';

-- Deployment の識別名
SET DCM_DEPLOYMENT_ALIAS = 'deploy_v1';


-- ------------------------------------------------------------
-- DCM Project の完全修飾名を生成
-- ------------------------------------------------------------

SET DCM_PROJECT =
    $DCM_DATABASE || '.' ||
    $DCM_SCHEMA   || '.' ||
    $DCM_PROJECT_NAME;


-- ============================================================
-- SQL生成
-- ============================================================

SET DCM_CREATE_SQL =
    'CREATE DCM PROJECT IF NOT EXISTS ' ||
    $DCM_PROJECT;


SET DCM_PLAN_SQL =
    'EXECUTE DCM PROJECT ' ||
    $DCM_PROJECT ||
    ' PLAN ' ||
    'USING CONFIGURATION ' || $DCM_CONFIGURATION || ' ' ||
    'FROM ''' || $DCM_SOURCE_PATH || '''';


SET DCM_DEPLOY_SQL =
    'EXECUTE DCM PROJECT ' ||
    $DCM_PROJECT ||
    ' DEPLOY AS "' || $DCM_DEPLOYMENT_ALIAS || '" ' ||
    'USING CONFIGURATION ' || $DCM_CONFIGURATION || ' ' ||
    'FROM ''' || $DCM_SOURCE_PATH || '''';


-- ============================================================
-- 2. DCM Project 作成
--
-- 実行する場合:
-- EXECUTE IMMEDIATE の行だけ選択して実行
-- ============================================================

/*

EXECUTE IMMEDIATE $DCM_CREATE_SQL;

*/


-- ============================================================
-- 3. PLAN
--
-- 実際の変更は行わない。
-- CREATE / ALTER / DROP される内容を確認する。
-- DEPLOY 前には必ず実行する。
-- ============================================================

/*

EXECUTE IMMEDIATE $DCM_PLAN_SQL;

*/


-- ============================================================
-- 3. DEPLOY
--
-- 注意:
-- 実際に Snowflake オブジェクトを変更する。
-- PLAN の結果を確認してから実行すること。
-- resultのchangesetを確認
-- ============================================================

/*

EXECUTE IMMEDIATE $DCM_DEPLOY_SQL;

*/