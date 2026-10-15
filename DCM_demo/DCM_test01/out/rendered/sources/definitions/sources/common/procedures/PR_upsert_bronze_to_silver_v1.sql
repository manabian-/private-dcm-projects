DEFINE PROCEDURE DCM_TEST01_DEV.PROCEDURES.SP_UPSERT_BRONZE_TO_SILVER_v1(
    P_TARGET_TABLE VARCHAR,
    P_SOURCE_SQL   VARCHAR,
    P_PRIMARY_KEYS ARRAY
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    max_update_timestamp   TIMESTAMP_LTZ;
    min_ingest_timestamp   TIMESTAMP_LTZ;

    min_ingest_sql         VARCHAR;
    on_condition           VARCHAR;
    partition_columns      VARCHAR;
    key_not_null_condition VARCHAR;
    merge_sql              VARCHAR;

    inserted_rows          NUMBER DEFAULT 0;
    updated_rows           NUMBER DEFAULT 0;
    affected_rows          NUMBER DEFAULT 0;

BEGIN
    -- =========================================================
    -- 1. MERGE 先の最新更新日時を取得
    -- =========================================================
    SELECT
        MAX(AUDIT__UPDATE_TIMESTAMP)
    INTO
        :max_update_timestamp
    FROM
        IDENTIFIER(:P_TARGET_TABLE);

    -- =========================================================
    -- 2. MERGE の再処理開始位置を取得
    --
    -- MERGE 先が空の場合:
    --   ソース SQL 全体の最小 INGEST 時刻
    --
    -- MERGE 先にデータがある場合:
    --   MERGE 先の MAX(AUDIT__UPDATE_TIMESTAMP) より後の
    --   AUDIT__UPDATE_TIMESTAMP を持つソースデータから、
    --   最小 AUDIT__INGEST_TIMESTAMP を取得
    -- =========================================================
    min_ingest_sql := '
        SELECT
            MIN(B.AUDIT__INGEST_TIMESTAMP)
                AS MIN_INGEST_TIMESTAMP
        FROM (
            ' || P_SOURCE_SQL || '
        ) AS B
    ';

    IF (max_update_timestamp IS NOT NULL) THEN
        min_ingest_sql := min_ingest_sql || '
            WHERE
                B.AUDIT__UPDATE_TIMESTAMP > ?
        ';
    END IF;

    LET min_ingest_result RESULTSET := (
        SELECT NULL::TIMESTAMP_LTZ AS MIN_INGEST_TIMESTAMP
    );

    IF (max_update_timestamp IS NULL) THEN
        min_ingest_result := (
            EXECUTE IMMEDIATE :min_ingest_sql
        );
    ELSE
        min_ingest_result := (
            EXECUTE IMMEDIATE :min_ingest_sql
            USING (
                max_update_timestamp
            )
        );
    END IF;

    FOR min_ingest_row IN min_ingest_result DO
        min_ingest_timestamp :=
            min_ingest_row.MIN_INGEST_TIMESTAMP;
    END FOR;

    -- =========================================================
    -- 3. 処理対象なし
    -- =========================================================
    IF (min_ingest_timestamp IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'NO_DATA_TO_MERGE',
            'max_update_timestamp', max_update_timestamp,
            'min_ingest_timestamp', min_ingest_timestamp,
            'affected_rows', 0
        );
    END IF;

    -- =========================================================
    -- 4. 主キー配列から SQL の各部分を生成
    --
    -- ・ON の結合条件
    -- ・PARTITION BY の列一覧
    -- ・主キーの NULL 除外条件
    -- =========================================================
    WITH KEY_COLUMNS AS (
        SELECT
            F.INDEX AS KEY_INDEX,
            '"' || REPLACE(F.VALUE::VARCHAR, '"', '""') || '"'
                AS COLUMN_NAME
        FROM
            TABLE(FLATTEN(INPUT => :P_PRIMARY_KEYS)) AS F
    )
    SELECT
        LISTAGG(
            'T.' || COLUMN_NAME || ' = S.' || COLUMN_NAME,
            ' AND '
        ) WITHIN GROUP (ORDER BY KEY_INDEX),

        LISTAGG(
            'B.' || COLUMN_NAME,
            ', '
        ) WITHIN GROUP (ORDER BY KEY_INDEX),

        LISTAGG(
            'B.' || COLUMN_NAME || ' IS NOT NULL',
            ' AND '
        ) WITHIN GROUP (ORDER BY KEY_INDEX)
    INTO
        :on_condition,
        :partition_columns,
        :key_not_null_condition
    FROM
        KEY_COLUMNS;

    -- =========================================================
    -- 5. MERGE SQL を生成
    --
    -- ソース SQL から再処理範囲を抽出
    -- 主キーに NULL を含む行を除外
    -- 同じ主キーが複数ある場合は最新の１行を採用
    -- =========================================================
    merge_sql := '
        MERGE INTO IDENTIFIER(?) AS T

        USING (
            SELECT
                B.*
            FROM (
                ' || P_SOURCE_SQL || '
            ) AS B
            WHERE
                B.AUDIT__INGEST_TIMESTAMP >= ?
                AND ' || key_not_null_condition || '
            QUALIFY
                ROW_NUMBER() OVER (
                    PARTITION BY
                        ' || partition_columns || '
                    ORDER BY
                        B.AUDIT__INGEST_TIMESTAMP DESC NULLS LAST,
                        B.AUDIT__UPDATE_TIMESTAMP DESC NULLS LAST
                ) = 1
        ) AS S

        ON
            ' || on_condition || '

        WHEN MATCHED
            AND (
                T.AUDIT__UPDATE_TIMESTAMP IS NULL
                OR S.AUDIT__UPDATE_TIMESTAMP
                    > T.AUDIT__UPDATE_TIMESTAMP
            )
            THEN UPDATE ALL BY NAME

        WHEN NOT MATCHED THEN
            INSERT ALL BY NAME
    ';

    -- =========================================================
    -- 6. MERGE を実行
    --
    -- テーブル名と開始日時をバインド
    -- RESULTSET は実行結果で初期化
    -- =========================================================
    LET merge_result RESULTSET := (
        EXECUTE IMMEDIATE :merge_sql
        USING (
            P_TARGET_TABLE,
            min_ingest_timestamp
        )
    );

    -- =========================================================
    -- 7. 実行結果から処理件数を取得
    -- =========================================================
    FOR merge_row IN merge_result DO
        inserted_rows := merge_row."number of rows inserted";
        updated_rows  := merge_row."number of rows updated";
    END FOR;

    affected_rows := inserted_rows + updated_rows;

    RETURN OBJECT_CONSTRUCT(
        'status', 'SUCCESS',
        'max_update_timestamp', max_update_timestamp,
        'min_ingest_timestamp', min_ingest_timestamp,
        'affected_rows', affected_rows
    );
END;
$$;