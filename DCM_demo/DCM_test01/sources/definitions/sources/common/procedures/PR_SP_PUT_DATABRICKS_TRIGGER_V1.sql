DEFINE PROCEDURE
    {{ database }}.PROCEDURES.SP_PUT_DATABRICKS_TRIGGER_V1(
        P_TARGET_STAGE VARCHAR,
        P_TARGET_PATH VARCHAR
    )
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_copy_query_id VARCHAR;
    v_target_location VARCHAR;
    v_copy_sql VARCHAR;

BEGIN

    -- 出力先を作成
    -- 例:
    -- @DCM_TEST01_DEV.PL_DEMO01.JOB_TRIGGER_STAGE/job_a/run_
    v_target_location :=
        '@' || P_TARGET_STAGE || '/' || P_TARGET_PATH || '/run_';

    -- COPY INTO文を生成
    v_copy_sql :=
        'COPY INTO ' || v_target_location || '
         FROM (
             SELECT ''trigger''
         )
         FILE_FORMAT = (
             TYPE = CSV
             COMPRESSION = NONE
         )
         SINGLE = FALSE
         INCLUDE_QUERY_ID = TRUE
         HEADER = FALSE';

    -- 起動用ファイルを作成
    EXECUTE IMMEDIATE :v_copy_sql;

    -- COPYのQuery ID
    v_copy_query_id := SQLID;

    RETURN OBJECT_CONSTRUCT(
        'status', 'FILE_CREATED',
        'copy_query_id', v_copy_query_id,
        'stage_path',
        '@' || P_TARGET_STAGE || '/' || P_TARGET_PATH || '/'
    );

END;
$$;