DEFINE PROCEDURE {{ database }}.PROCEDURES.SP_DELETE_OLD_ORDERS_v1(
    P_TARGET_TABLE VARCHAR,
    retention_days NUMBER DEFAULT 60
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    deleted_row_count NUMBER DEFAULT 0;

BEGIN

    DELETE FROM IDENTIFIER(:P_TARGET_TABLE)
    WHERE
        AUDIT__INGEST_TIMESTAMP
            < DATEADD(
                DAY,
                -1 * :retention_days,
                CURRENT_TIMESTAMP()
            );

    deleted_row_count := SQLROWCOUNT;

    RETURN
        'Deleted '
        || deleted_row_count
        || ' rows older than '
        || retention_days
        || ' days.';

END;
$$;
