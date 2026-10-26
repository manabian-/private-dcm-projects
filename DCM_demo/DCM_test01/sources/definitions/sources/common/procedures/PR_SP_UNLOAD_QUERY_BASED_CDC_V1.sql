DEFINE PROCEDURE {{ database }}.PROCEDURES.SP_UNLOAD_QUERY_BASED_CDC_V1(
    P_SOURCE_QUERY      VARCHAR,
    P_TARGET_STAGE      VARCHAR,
    P_CHECKPOINT_STAGE  VARCHAR,
    P_TARGET_PATH       VARCHAR DEFAULT 'output',
    P_CHECKPOINT_PATH   VARCHAR DEFAULT 'checkpoints',
    P_TIMESTAMP_COLUMN  VARCHAR DEFAULT 'AUDIT__UPDATA1_TIMESTAMP',
    P_LOOKBACK_SECONDS  NUMBER(38, 0) DEFAULT 0,
    P_FILE_FORMAT          VARCHAR DEFAULT 'TYPE = PARQUET COMPRESSION = SNAPPY',
    P_PARTITION_BY         VARCHAR DEFAULT NULL,
    P_OVERWRITE            BOOLEAN DEFAULT NULL,
    P_SINGLE               BOOLEAN DEFAULT NULL,
    P_MAX_FILE_SIZE        NUMBER(38, 0) DEFAULT 268435456,
    P_INCLUDE_QUERY_ID     BOOLEAN DEFAULT TRUE,
    P_DETAILED_OUTPUT      BOOLEAN DEFAULT FALSE,
    P_VALIDATION_MODE      VARCHAR DEFAULT NULL,
    P_HEADER               BOOLEAN DEFAULT TRUE,
    P_TARGET_LOCATION      VARCHAR DEFAULT NULL,
    P_STORAGE_INTEGRATION  VARCHAR DEFAULT NULL,
    P_CREDENTIALS          VARCHAR DEFAULT NULL,
    P_ENCRYPTION           VARCHAR DEFAULT NULL
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    -- 注意事項:
    -- ・記事の SP_UNLOAD を EXECUTE AS CALLER で事前に作成すること。
    -- ・SP_UNLOAD の追加オプションはデータ出力に適用する。
    -- ・P_TARGET_LOCATION 指定時はその場所に直接出力する。
    -- ・VALIDATION_MODE 指定時は出力せず、チェックポイントも更新しない。
    -- ・クエリの結果に P_TIMESTAMP_COLUMN で指定した列を含めること。
    -- ・更新日時は UTC の TIMESTAMP_NTZ。INSERT/UPDATE 時に必ず更新すること。
    -- ・物理 DELETE と更新前の値は取得できない。
    -- ・同じチェックポイントを使用する処理は直列実行すること。
    -- ・ステージへの出力と JSON 更新は一体でロールバックできない。
    --   再実行時の重複を前提とし、後段で主キー/更新日時による処理を行うこと。
    -- ・CHECKPOINT_STAGE の既定のファイル形式は JSON に設定すること。
    -- ・処理ごとに異なる P_CHECKPOINT_PATH を指定すること。
    -- ・クエリを変更する場合は別の P_CHECKPOINT_PATH を指定すること。

    v_source_query VARCHAR;
    v_target_stage VARCHAR;
    v_checkpoint_stage VARCHAR;
    v_timestamp_column VARCHAR;
    v_target_path VARCHAR;
    v_checkpoint_path VARCHAR;
    v_checkpoint_file VARCHAR;
    v_output_path VARCHAR;
    v_output_location VARCHAR;
    v_run_id VARCHAR;
    v_run_timestamp VARCHAR;
    v_timestamp_format VARCHAR DEFAULT 'YYYY-MM-DD"T"HH24:MI:SS.FF9"Z"';
    v_sql VARCHAR;
    v_list_query_id VARCHAR;
    v_source_query_id VARCHAR;
    v_unload_query_id VARCHAR;
    v_checkpoint_query_id VARCHAR;
    v_checkpoint_json VARCHAR;
    v_checkpoint VARIANT;
    v_last_timestamp TIMESTAMP_NTZ(9);
    v_lower_timestamp TIMESTAMP_NTZ(9);
    v_batch_max_timestamp TIMESTAMP_NTZ(9);
    v_next_timestamp TIMESTAMP_NTZ(9);
    v_file_count NUMBER DEFAULT 0;
    v_row_count NUMBER DEFAULT 0;
    v_null_timestamp_rows NUMBER DEFAULT 0;
    v_unloaded_rows NUMBER DEFAULT 0;
    v_unload_rows_column VARCHAR;
    v_result RESULTSET;

    e_invalid_checkpoint EXCEPTION (
        -20002,
        'Invalid checkpoint. Check the JSON format, source query, watermark column, and watermark value.'
    );
    e_invalid_data EXCEPTION (
        -20003,
        'Invalid timestamp or unloaded row count. Checkpoint was not advanced.'
    );

BEGIN
    -- 1. クエリ、オブジェクト名、パスを設定
    v_source_query := REGEXP_REPLACE(
        TRIM(P_SOURCE_QUERY),
        ';[[:space:]]*$',
        ''
    );

    v_target_stage := UPPER(LTRIM(TRIM(P_TARGET_STAGE), '@'));
    v_checkpoint_stage := UPPER(LTRIM(TRIM(P_CHECKPOINT_STAGE), '@'));
    v_timestamp_column := UPPER(TRIM(P_TIMESTAMP_COLUMN));
    v_target_path := TRIM(COALESCE(P_TARGET_PATH, ''), '/');
    v_checkpoint_path := TRIM(COALESCE(P_CHECKPOINT_PATH, ''), '/');

    -- 指定されたパスの直下にチェックポイントを保存する。
    v_checkpoint_file := '@' || v_checkpoint_stage || '/'
        || IFF(v_checkpoint_path = '', '', v_checkpoint_path || '/')
        || 'checkpoint.json';

    -- 2. チェックポイントファイルの有無を確認
    v_sql := 'LIST ' || v_checkpoint_file
        || ' PATTERN = ''(^|.*/)checkpoint[.]json$''';

    EXECUTE IMMEDIATE :v_sql;
    v_list_query_id := SQLID;

    SELECT COUNT(*)
    INTO :v_file_count
    FROM TABLE(RESULT_SCAN(:v_list_query_id));

    IF (v_file_count > 1) THEN
        RAISE e_invalid_checkpoint;
    END IF;

    -- ファイルが存在しない場合だけ初回とする。
    IF (v_file_count = 1) THEN
        v_sql := 'SELECT $1 AS CHECKPOINT FROM ' || v_checkpoint_file
            || ' (PATTERN => ''(^|.*/)checkpoint[.]json$'')';

        v_result := (EXECUTE IMMEDIATE :v_sql);

        FOR r IN v_result DO
            v_checkpoint := r.CHECKPOINT;
        END FOR;

        IF (
            NOT COALESCE(IS_OBJECT(v_checkpoint), FALSE)
            OR COALESCE(
                TRY_TO_NUMBER(v_checkpoint:schema_version::VARCHAR),
                -1
            ) <> 1
            OR COALESCE(
                v_checkpoint:source_query::VARCHAR,
                ''
            ) <> v_source_query
            OR COALESCE(
                v_checkpoint:wartermark_column::VARCHAR,
                v_checkpoint:timestamp_column::VARCHAR,
                ''
            ) <> v_timestamp_column
        ) THEN
            RAISE e_invalid_checkpoint;
        END IF;

        v_last_timestamp := TRY_TO_TIMESTAMP_NTZ(
            v_checkpoint:wartermark_value::VARCHAR,
            v_timestamp_format
        );

        IF (v_last_timestamp IS NULL) THEN
            RAISE e_invalid_checkpoint;
        END IF;
    END IF;

    -- 3. 初回はクエリ結果の全件、2 回目以降は更新日時で抽出
    v_sql := 'SELECT * FROM (' || CHR(10)
        || v_source_query || CHR(10)
        || ') AS SRC';

    IF (v_last_timestamp IS NULL) THEN
        v_result := (EXECUTE IMMEDIATE :v_sql);
        v_source_query_id := SQLID;
    ELSE
        v_lower_timestamp := DATEADD(
            'SECOND',
            -P_LOOKBACK_SECONDS,
            v_last_timestamp
        );

        v_sql := v_sql
            || ' WHERE SRC.' || v_timestamp_column
            || IFF(P_LOOKBACK_SECONDS = 0, ' > ?', ' >= ?');

        v_result := (
            EXECUTE IMMEDIATE :v_sql USING (v_lower_timestamp)
        );
        v_source_query_id := SQLID;
    END IF;

    -- 最大値の取得と UNLOAD に同じ抽出結果を使用する。
    SELECT
        COUNT(*),
        MAX(IDENTIFIER(:v_timestamp_column)),
        COUNT_IF(IDENTIFIER(:v_timestamp_column) IS NULL)
    INTO
        :v_row_count,
        :v_batch_max_timestamp,
        :v_null_timestamp_rows
    FROM TABLE(RESULT_SCAN(:v_source_query_id));

    -- 対象がなければ JSON を更新せず終了
    IF (v_row_count = 0) THEN
        RETURN OBJECT_CONSTRUCT_KEEP_NULL(
            'status', 'NO_DATA',
            'source_query', v_source_query,
            'wartermark_column', v_timestamp_column,
            'wartermark_value',
                TO_VARCHAR(v_last_timestamp, v_timestamp_format),
            'unloaded_rows', 0,
            'checkpoint_file', v_checkpoint_file
        );
    END IF;

    IF (
        v_batch_max_timestamp IS NULL
        OR COALESCE(v_null_timestamp_rows, 0) > 0
    ) THEN
        RAISE e_invalid_data;
    END IF;

    v_next_timestamp := v_batch_max_timestamp;

    IF (v_last_timestamp IS NOT NULL) THEN
        -- LOOKBACK で再取得した場合もチェックポイントを後退させない。
        v_next_timestamp := GREATEST(
            v_last_timestamp,
            v_batch_max_timestamp
        );
    END IF;

    -- 4. SP_UNLOAD を呼び出して指定形式に UNLOAD
    v_run_id := UUID_STRING();

    v_run_timestamp := TO_VARCHAR(
        CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP())::TIMESTAMP_NTZ,
        'YYYY-MM-DD"T"HH24-MI-SS"Z"'
    );

    v_output_path := IFF(v_target_path = '', '', v_target_path || '/')
        || 'audit__ingest_timestamp=' || v_run_timestamp || '/';

    v_output_location := COALESCE(
        P_TARGET_LOCATION,
        '@' || v_target_stage || '/' || v_output_path
    );

    -- 抽出済みの結果を参照する SELECT 文を SP_UNLOAD に渡す。
    v_sql := 'SELECT * FROM TABLE(RESULT_SCAN('
        || CHR(39) || v_source_query_id || CHR(39) || '))';

    -- SP_UNLOAD が返す COPY INTO のクエリ ID を取得する。
    CALL {{ database }}.PROCEDURES.SP_UNLOAD_v1(
        P_TARGET_STAGE        => :v_target_stage,
        P_TARGET_PATH         => :v_output_path,
        P_SOURCE_QUERY        => :v_sql,
        P_FILE_FORMAT         => :P_FILE_FORMAT,
        P_PARTITION_BY        => :P_PARTITION_BY,
        P_OVERWRITE           => :P_OVERWRITE,
        P_SINGLE              => :P_SINGLE,
        P_MAX_FILE_SIZE       => :P_MAX_FILE_SIZE,
        P_INCLUDE_QUERY_ID    => :P_INCLUDE_QUERY_ID,
        P_DETAILED_OUTPUT     => :P_DETAILED_OUTPUT,
        P_VALIDATION_MODE     => :P_VALIDATION_MODE,
        P_HEADER              => :P_HEADER,
        P_TARGET_LOCATION     => :P_TARGET_LOCATION,
        P_STORAGE_INTEGRATION => :P_STORAGE_INTEGRATION,
        P_CREDENTIALS         => :P_CREDENTIALS,
        P_ENCRYPTION          => :P_ENCRYPTION
    ) INTO :v_unload_query_id;

    -- 検証モードでは実ファイルが出力されないため、チェックポイントを更新しない。
    IF (P_VALIDATION_MODE IS NOT NULL) THEN
        RETURN OBJECT_CONSTRUCT_KEEP_NULL(
            'status', 'VALIDATED',
            'source_query', v_source_query,
            'wartermark_column', v_timestamp_column,
            'wartermark_value',
                TO_VARCHAR(v_last_timestamp, v_timestamp_format),
            'validated_rows', v_row_count,
            'unloaded_rows', 0,
            'checkpoint_file', v_checkpoint_file
        );
    END IF;

    -- 詳細出力ではファイル別の row_count、それ以外では rows_unloaded を集計する。
    v_unload_rows_column := IFF(
        COALESCE(P_DETAILED_OUTPUT, FALSE),
        'row_count',
        'rows_unloaded'
    );

    SELECT COALESCE(
        SUM(GET_IGNORE_CASE(COPY_RESULT, :v_unload_rows_column)::NUMBER),
        0
    )
    INTO :v_unloaded_rows
    FROM (
        SELECT OBJECT_CONSTRUCT(*) AS COPY_RESULT
        FROM TABLE(RESULT_SCAN(:v_unload_query_id))
    );

    IF (v_unloaded_rows <> v_row_count) THEN
        RAISE e_invalid_data;
    END IF;

    -- 5. 新形式のチェックポイントを作成
    SELECT OBJECT_CONSTRUCT_KEEP_NULL(
        'schema_version', 1,
        'source_query', :v_source_query,
        'wartermark_column', :v_timestamp_column,
        'wartermark_value',
            TO_VARCHAR(:v_next_timestamp, :v_timestamp_format),
        'previous_timestamp',
            TO_VARCHAR(:v_last_timestamp, :v_timestamp_format),
        'completed_at_utc', TO_VARCHAR(
            CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP())::TIMESTAMP_NTZ,
            :v_timestamp_format
        ),
        'unloaded_rows', :v_unloaded_rows,
        'output_location', :v_output_location,
        'lookback_seconds', :P_LOOKBACK_SECONDS
    )
    INTO :v_checkpoint;

    v_checkpoint_json := TO_JSON(v_checkpoint);

    -- データ出力成功後にチェックポイントを上書き
    v_sql := 'COPY INTO ' || v_checkpoint_file
        || ' FROM (SELECT PARSE_JSON(?))'
        || ' FILE_FORMAT = (TYPE = JSON COMPRESSION = NONE)'
        || ' SINGLE = TRUE'
        || ' OVERWRITE = TRUE';

    EXECUTE IMMEDIATE :v_sql USING (v_checkpoint_json);
    v_checkpoint_query_id := SQLID;

    -- 6. 返却用の項目を同じ階層に追加
    v_checkpoint := OBJECT_INSERT(
        v_checkpoint,
        'status',
        'SUCCESS'
    );

    RETURN v_checkpoint;
END;
$$;
