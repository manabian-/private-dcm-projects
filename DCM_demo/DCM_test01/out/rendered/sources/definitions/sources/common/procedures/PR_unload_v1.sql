DEFINE PROCEDURE DCM_TEST01_DEV.PROCEDURES.SP_UNLOAD(
    P_TARGET_STAGE         VARCHAR,
    P_TARGET_PATH          VARCHAR,
    P_SOURCE_QUERY         VARCHAR,
    P_FILE_FORMAT          VARCHAR DEFAULT NULL,
    P_PARTITION_BY         VARCHAR DEFAULT NULL,
    P_OVERWRITE            BOOLEAN DEFAULT NULL,
    P_SINGLE               BOOLEAN DEFAULT NULL,
    P_MAX_FILE_SIZE        NUMBER(38, 0) DEFAULT NULL,
    P_INCLUDE_QUERY_ID     BOOLEAN DEFAULT NULL,
    P_DETAILED_OUTPUT      BOOLEAN DEFAULT NULL,
    P_VALIDATION_MODE      VARCHAR DEFAULT NULL,
    P_HEADER               BOOLEAN DEFAULT NULL,
    P_TARGET_LOCATION      VARCHAR DEFAULT NULL,
    P_STORAGE_INTEGRATION  VARCHAR DEFAULT NULL,
    P_CREDENTIALS          VARCHAR DEFAULT NULL,
    P_ENCRYPTION           VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    copy_sql        VARCHAR;
    target_location VARCHAR;
    copy_query_id   VARCHAR;

BEGIN
    -- =========================================================
    -- 1. 出力先を設定
    --
    -- ステージへの出力:
    --   P_TARGET_STAGE と P_TARGET_PATH を使用
    --
    -- 外部 URL への直接出力:
    --   P_TARGET_LOCATION を使用
    -- =========================================================
    IF (P_TARGET_LOCATION IS NOT NULL) THEN
        target_location := P_TARGET_LOCATION;
    ELSE
        target_location :=
            '@' || P_TARGET_STAGE || '/' ||
            LTRIM(COALESCE(P_TARGET_PATH, ''), '/');
    END IF;

    copy_sql :=
        'COPY INTO ' ||
        CHR(39) ||
        REPLACE(
            target_location,
            CHR(39),
            CHR(39) || CHR(39)
        ) ||
        CHR(39);

    -- =========================================================
    -- 2. 外部 URL 用の認証・暗号化設定
    -- =========================================================
    IF (P_STORAGE_INTEGRATION IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' STORAGE_INTEGRATION = ' || P_STORAGE_INTEGRATION;
    END IF;

    IF (P_CREDENTIALS IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' CREDENTIALS = (' || P_CREDENTIALS || ')';
    END IF;

    IF (P_ENCRYPTION IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' ENCRYPTION = (' || P_ENCRYPTION || ')';
    END IF;

    -- =========================================================
    -- 3. SELECT 文・パーティション式・ファイル形式
    -- =========================================================
    copy_sql := copy_sql ||
        ' FROM (' || P_SOURCE_QUERY || ')';

    IF (P_PARTITION_BY IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' PARTITION BY (' || P_PARTITION_BY || ')';
    END IF;

    IF (P_FILE_FORMAT IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' FILE_FORMAT = (' || P_FILE_FORMAT || ')';
    END IF;

    -- =========================================================
    -- 4. COPY オプション
    -- =========================================================
    IF (P_OVERWRITE IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' OVERWRITE = ' ||
            IFF(P_OVERWRITE, 'TRUE', 'FALSE');
    END IF;

    IF (P_SINGLE IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' SINGLE = ' ||
            IFF(P_SINGLE, 'TRUE', 'FALSE');
    END IF;

    IF (P_MAX_FILE_SIZE IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' MAX_FILE_SIZE = ' ||
            TO_VARCHAR(P_MAX_FILE_SIZE);
    END IF;

    IF (P_INCLUDE_QUERY_ID IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' INCLUDE_QUERY_ID = ' ||
            IFF(P_INCLUDE_QUERY_ID, 'TRUE', 'FALSE');
    END IF;

    IF (P_DETAILED_OUTPUT IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' DETAILED_OUTPUT = ' ||
            IFF(P_DETAILED_OUTPUT, 'TRUE', 'FALSE');
    END IF;

    -- =========================================================
    -- 5. 検証モード・列名出力
    -- =========================================================
    IF (P_VALIDATION_MODE IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' VALIDATION_MODE = ' ||
            CHR(39) ||
            REPLACE(
                P_VALIDATION_MODE,
                CHR(39),
                CHR(39) || CHR(39)
            ) ||
            CHR(39);
    END IF;

    IF (P_HEADER IS NOT NULL) THEN
        copy_sql := copy_sql ||
            ' HEADER = ' ||
            IFF(P_HEADER, 'TRUE', 'FALSE');
    END IF;

    -- =========================================================
    -- 6. COPY INTO を実行し、クエリ ID を返す
    -- =========================================================
    EXECUTE IMMEDIATE :copy_sql;

    copy_query_id := SQLID;

    RETURN copy_query_id;

END;
$$;