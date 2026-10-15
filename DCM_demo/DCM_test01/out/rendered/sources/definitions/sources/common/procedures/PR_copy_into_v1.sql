DEFINE PROCEDURE DCM_TEST01_DEV.PROCEDURES.SP_COPY_v1(
    P_TARGET_TABLE         VARCHAR,
    P_SOURCE_STAGE         VARCHAR,
    P_SOURCE_PATH          VARCHAR DEFAULT NULL,
    P_FILE_FORMAT          VARCHAR DEFAULT NULL,
    P_MATCH_BY_COLUMN_NAME VARCHAR DEFAULT NULL,
    P_INCLUDE_METADATA     VARCHAR DEFAULT NULL,
    P_ON_ERROR             VARCHAR DEFAULT NULL,
    P_FILES                VARCHAR DEFAULT NULL,
    P_PATTERN              VARCHAR DEFAULT NULL,
    P_FORCE                BOOLEAN DEFAULT NULL,
    P_PURGE                BOOLEAN DEFAULT NULL,
    P_SIZE_LIMIT           NUMBER  DEFAULT NULL,
    P_LOAD_UNCERTAIN_FILES BOOLEAN DEFAULT NULL,
    P_ENFORCE_LENGTH       BOOLEAN DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    copy_sql                    VARCHAR;
    stage_location              VARCHAR;

    copy_query_id               VARCHAR;
    copy_status                 VARCHAR;
    load_status                 VARCHAR;

    processed_file_count        NUMBER DEFAULT 0;
    loaded_file_count           NUMBER DEFAULT 0;
    load_failed_file_count      NUMBER DEFAULT 0;
    partially_loaded_file_count NUMBER DEFAULT 0;

    rows_parsed                 NUMBER DEFAULT 0;
    rows_loaded                 NUMBER DEFAULT 0;
    errors_seen                 NUMBER DEFAULT 0;

    return_value                VARCHAR;

BEGIN
    -- =========================================================
    -- ステージパスを生成
    -- P_SOURCE_STAGE は @ を含めずに指定
    -- =========================================================
    stage_location := '@' || P_SOURCE_STAGE;

    IF (P_SOURCE_PATH IS NOT NULL AND P_SOURCE_PATH <> '') THEN
        stage_location := stage_location || '/' ||
            LTRIM(P_SOURCE_PATH, '/');
    END IF;

    -- =========================================================
    -- COPY INTO の基本SQLを生成
    -- ステージパスは空白などを扱えるよう一重引用符で囲む
    -- =========================================================
    copy_sql :=
        'COPY INTO IDENTIFIER(?) ' ||
        'FROM ''' ||
            REPLACE(stage_location, '''', '''''') ||
        ''' ';

    -- =========================================================
    -- 対象ファイル
    -- P_FILES は括弧を含まないSQL断片
    -- 例: 'orders_01.csv', 'orders_02.csv'
    -- =========================================================
    IF (P_FILES IS NOT NULL AND P_FILES <> '') THEN
        copy_sql := copy_sql ||
            'FILES = (' || P_FILES || ') ';
    END IF;

    -- =========================================================
    -- ファイル名の正規表現
    -- P_PATTERN は外側の引用符を含めずに指定
    -- =========================================================
    IF (P_PATTERN IS NOT NULL AND P_PATTERN <> '') THEN
        copy_sql := copy_sql ||
            'PATTERN = ''' ||
                REPLACE(P_PATTERN, '''', '''''') ||
            ''' ';
    END IF;

    -- =========================================================
    -- ファイル形式
    -- P_FILE_FORMAT は括弧を含まないSQL断片
    -- =========================================================
    IF (P_FILE_FORMAT IS NOT NULL AND P_FILE_FORMAT <> '') THEN
        copy_sql := copy_sql ||
            'FILE_FORMAT = (' || P_FILE_FORMAT || ') ';
    END IF;

    -- =========================================================
    -- 列名による対応付け
    -- =========================================================
    IF (
        P_MATCH_BY_COLUMN_NAME IS NOT NULL
        AND P_MATCH_BY_COLUMN_NAME <> ''
    ) THEN
        copy_sql := copy_sql ||
            'MATCH_BY_COLUMN_NAME = ''' ||
                REPLACE(P_MATCH_BY_COLUMN_NAME, '''', '''''') ||
            ''' ';
    END IF;

    -- =========================================================
    -- メタデータのマッピング
    -- P_INCLUDE_METADATA は括弧を含まないSQL断片
    -- =========================================================
    IF (
        P_INCLUDE_METADATA IS NOT NULL
        AND P_INCLUDE_METADATA <> ''
    ) THEN
        copy_sql := copy_sql ||
            'INCLUDE_METADATA = (' || P_INCLUDE_METADATA || ') ';
    END IF;

    -- =========================================================
    -- エラー時の動作
    -- =========================================================
    IF (P_ON_ERROR IS NOT NULL AND P_ON_ERROR <> '') THEN
        copy_sql := copy_sql ||
            'ON_ERROR = ''' ||
                REPLACE(P_ON_ERROR, '''', '''''') ||
            ''' ';
    END IF;

    -- =========================================================
    -- ロード済みファイルの強制再ロード
    -- =========================================================
    IF (P_FORCE IS NOT NULL) THEN
        copy_sql := copy_sql ||
            'FORCE = ' || IFF(P_FORCE, 'TRUE', 'FALSE') || ' ';
    END IF;

    -- =========================================================
    -- 正常ロード後のファイル削除
    -- =========================================================
    IF (P_PURGE IS NOT NULL) THEN
        copy_sql := copy_sql ||
            'PURGE = ' || IFF(P_PURGE, 'TRUE', 'FALSE') || ' ';
    END IF;

    -- =========================================================
    -- 1回のロード量の制限（バイト）
    -- =========================================================
    IF (P_SIZE_LIMIT IS NOT NULL) THEN
        copy_sql := copy_sql ||
            'SIZE_LIMIT = ' || TO_VARCHAR(P_SIZE_LIMIT) || ' ';
    END IF;

    -- =========================================================
    -- ロード状態が不明なファイルの取り込み
    -- =========================================================
    IF (P_LOAD_UNCERTAIN_FILES IS NOT NULL) THEN
        copy_sql := copy_sql ||
            'LOAD_UNCERTAIN_FILES = ' ||
                IFF(P_LOAD_UNCERTAIN_FILES, 'TRUE', 'FALSE') ||
            ' ';
    END IF;

    -- =========================================================
    -- 列の長さを超える文字列の扱い
    -- TRUE: エラー / FALSE: 切り捨て
    -- =========================================================
    IF (P_ENFORCE_LENGTH IS NOT NULL) THEN
        copy_sql := copy_sql ||
            'ENFORCE_LENGTH = ' ||
                IFF(P_ENFORCE_LENGTH, 'TRUE', 'FALSE') ||
            ' ';
    END IF;

    -- =========================================================
    -- 集計のため、成功ファイルも実行結果に含める
    -- =========================================================
    copy_sql := copy_sql ||
        'RETURN_FAILED_ONLY = FALSE';

    -- =========================================================
    -- データをロードし、実行直後に Query ID を保存
    -- =========================================================
    EXECUTE IMMEDIATE :copy_sql USING (P_TARGET_TABLE);
    copy_query_id := SQLID;

    -- =========================================================
    -- 0 files processed の場合は列構成が異なるため、
    -- 最初に status のみ確認
    -- =========================================================
    SELECT "status"
    INTO :copy_status
    FROM TABLE(RESULT_SCAN(:copy_query_id))
    LIMIT 1;

    -- =========================================================
    -- COPY INTO の実行結果を集計
    -- =========================================================
    IF (copy_status != 'Copy executed with 0 files processed.') THEN
        SELECT
            COUNT(*),
            COALESCE(COUNT_IF("status" = 'LOADED'), 0),
            COALESCE(COUNT_IF("status" = 'LOAD_FAILED'), 0),
            COALESCE(COUNT_IF("status" = 'PARTIALLY_LOADED'), 0),
            COALESCE(SUM("rows_parsed"), 0),
            COALESCE(SUM("rows_loaded"), 0),
            COALESCE(SUM("errors_seen"), 0)
        INTO
            :processed_file_count,
            :loaded_file_count,
            :load_failed_file_count,
            :partially_loaded_file_count,
            :rows_parsed,
            :rows_loaded,
            :errors_seen
        FROM TABLE(RESULT_SCAN(:copy_query_id));
    END IF;

    -- =========================================================
    -- ロード結果を判定
    -- =========================================================
    IF (load_failed_file_count > 0) THEN
        load_status := 'ERROR';
    ELSEIF (partially_loaded_file_count > 0) THEN
        load_status := 'PARTIAL_ERROR';
    ELSE
        load_status := 'SUCCESS';
    END IF;

    -- =========================================================
    -- 実行結果を JSON として返却
    -- =========================================================
    return_value := TO_JSON(
        OBJECT_CONSTRUCT(
            'load_status', load_status,
            'copy_query_id', copy_query_id,
            'processed_file_count', processed_file_count,
            'loaded_file_count', loaded_file_count,
            'load_failed_file_count', load_failed_file_count,
            'partially_loaded_file_count', partially_loaded_file_count,
            'rows_parsed', rows_parsed,
            'rows_loaded', rows_loaded,
            'errors_seen', errors_seen
        )
    );

    RETURN return_value;

EXCEPTION
    WHEN OTHER THEN
        RETURN TO_JSON(
            OBJECT_CONSTRUCT_KEEP_NULL(
                'load_status', 'ERROR',
                'copy_query_id', copy_query_id,
                'processed_file_count', processed_file_count,
                'loaded_file_count', loaded_file_count,
                'load_failed_file_count', load_failed_file_count,
                'partially_loaded_file_count', partially_loaded_file_count,
                'rows_parsed', rows_parsed,
                'rows_loaded', rows_loaded,
                'errors_seen', errors_seen,
                'error_code', SQLCODE,
                'error_message', SQLERRM,
                'sql_state', SQLSTATE
            )
        );
END;
$$;