DEFINE PROCEDURE DCM_TEST01_DEV.PROCEDURES.SP_CHECK_COPY_RESULT_v1(
    copy_result VARCHAR,
    raise_load_failed_error BOOLEAN DEFAULT TRUE,
    raise_partially_loaded_error BOOLEAN DEFAULT FALSE
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    result                       VARIANT;
    copy_query_id                VARCHAR;
    load_failed_file_count       NUMBER;
    partially_loaded_file_count  NUMBER;

    copy_load_error EXCEPTION (
        -20001,
        'COPY INTO detected LOAD_FAILED files.'
    );

    copy_partial_error EXCEPTION (
        -20002,
        'COPY INTO detected PARTIALLY_LOADED files.'
    );

BEGIN

    result := PARSE_JSON(copy_result);

    copy_query_id :=
        result:"copy_query_id"::VARCHAR;

    load_failed_file_count :=
        result:"load_failed_file_count"::NUMBER;

    partially_loaded_file_count :=
        result:"partially_loaded_file_count"::NUMBER;

    -- =========================================================
    -- LOAD_FAILED を確認
    -- =========================================================
    IF (load_failed_file_count > 0) THEN

        IF (raise_load_failed_error) THEN
            RAISE copy_load_error;
        END IF;

        RETURN
            'COPY INTO completed with LOAD_FAILED files. '
            || 'Load failed file count: '
            || load_failed_file_count
            || '. Query ID: '
            || copy_query_id;

    END IF;

    -- =========================================================
    -- PARTIALLY_LOADED を確認
    -- =========================================================
    IF (partially_loaded_file_count > 0) THEN

        IF (raise_partially_loaded_error) THEN
            RAISE copy_partial_error;
        END IF;

        RETURN
            'COPY INTO completed with PARTIALLY_LOADED files. '
            || 'Partially loaded file count: '
            || partially_loaded_file_count
            || '. Query ID: '
            || copy_query_id;

    END IF;

    -- =========================================================
    -- 正常終了
    -- =========================================================
    RETURN
        'COPY INTO completed successfully. '
        || 'Query ID: '
        || copy_query_id;

END;
$$;