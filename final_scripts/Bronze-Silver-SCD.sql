CREATE OR REPLACE PROCEDURE SILVER.SP_LOAD_CLAIMS_SCD2(
    P_INITIAL_LOAD BOOLEAN
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_ROWS NUMBER DEFAULT 0;
    V_TXN_STARTED BOOLEAN DEFAULT FALSE;

BEGIN

    -- 1. Create session-level temporary processing table
    CREATE OR REPLACE TEMP TABLE TMP_CLAIMS_SCD2 (
        CLAIM_ID                  VARCHAR(50),
        POLICY_ID                 VARCHAR(50),
        CUSTOMER_ID               VARCHAR(50),
        CLAIM_REGISTRATION_DATE   DATE,
        LOSS_DATE                 DATE,
        CLAIM_TYPE                VARCHAR(100),
        CLAIM_AMOUNT              NUMBER(18,2),
        APPROVED_AMOUNT           NUMBER(18,2),
        CLAIM_STATUS              VARCHAR(50),
        ASSESSOR_ID               VARCHAR(50),
        BRANCH_ID                 VARCHAR(50),
        SOURCE_UPDATED_TS         TIMESTAMP_NTZ,
        RECORD_HASH               VARCHAR(64),
        EFFECTIVE_START_DATE      TIMESTAMP_NTZ,
        _FILE_NAME                VARCHAR(500),
        _LOAD_TS                  TIMESTAMP_NTZ,
        _BATCH_ID                 VARCHAR(100)
    );

    -- 2. Start transaction
    BEGIN TRANSACTION;
    V_TXN_STARTED := TRUE;

    -- 3. Read initial Bronze data or incremental Stream data

    IF (P_INITIAL_LOAD = TRUE) THEN

        INSERT INTO TMP_CLAIMS_SCD2
        SELECT
            CLAIM_ID,
            POLICY_ID,
            CUSTOMER_ID,
            CLAIM_REGISTRATION_DATE,
            LOSS_DATE,
            CLAIM_TYPE,
            CLAIM_AMOUNT,
            APPROVED_AMOUNT,
            CLAIM_STATUS,
            ASSESSOR_ID,
            BRANCH_ID,
            SOURCE_UPDATED_TS,

            SHA2(
                TO_JSON(
                    ARRAY_CONSTRUCT(
                        POLICY_ID,
                        CUSTOMER_ID,
                        CLAIM_REGISTRATION_DATE,
                        LOSS_DATE,
                        CLAIM_TYPE,
                        CLAIM_AMOUNT,
                        APPROVED_AMOUNT,
                        CLAIM_STATUS,
                        ASSESSOR_ID,
                        BRANCH_ID
                    )
                ),
                256
            ),

            COALESCE(
                SOURCE_UPDATED_TS,
                _LOAD_TS,
                CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
            ),

            _FILE_NAME,
            _LOAD_TS,
            _BATCH_ID

        FROM (
            SELECT
                CLAIM_ID,
                POLICY_ID,
                CUSTOMER_ID,
                TRY_TO_DATE(CLAIM_REGISTRATION_DATE)
                    AS CLAIM_REGISTRATION_DATE,
                TRY_TO_DATE(LOSS_DATE)
                    AS LOSS_DATE,
                CLAIM_TYPE,
                TRY_TO_DECIMAL(CLAIM_AMOUNT, 18, 2)
                    AS CLAIM_AMOUNT,
                TRY_TO_DECIMAL(APPROVED_AMOUNT, 18, 2)
                    AS APPROVED_AMOUNT,
                CLAIM_STATUS,
                ASSESSOR_ID,
                BRANCH_ID,
                TRY_TO_TIMESTAMP_NTZ(SOURCE_UPDATED_TS)
                    AS SOURCE_UPDATED_TS,
                _FILE_NAME,
                _LOAD_TS,
                _BATCH_ID,

                ROW_NUMBER() OVER (
                    PARTITION BY CLAIM_ID
                    ORDER BY
                        TRY_TO_TIMESTAMP_NTZ(SOURCE_UPDATED_TS)
                            DESC NULLS LAST,
                        _LOAD_TS DESC
                ) AS RN

            FROM BRONZE.CLAIMS
            WHERE CLAIM_ID IS NOT NULL
        )
        WHERE RN = 1;

    ELSE

        INSERT INTO TMP_CLAIMS_SCD2
        SELECT
            CLAIM_ID,
            POLICY_ID,
            CUSTOMER_ID,
            CLAIM_REGISTRATION_DATE,
            LOSS_DATE,
            CLAIM_TYPE,
            CLAIM_AMOUNT,
            APPROVED_AMOUNT,
            CLAIM_STATUS,
            ASSESSOR_ID,
            BRANCH_ID,
            SOURCE_UPDATED_TS,

            SHA2(
                TO_JSON(
                    ARRAY_CONSTRUCT(
                        POLICY_ID,
                        CUSTOMER_ID,
                        CLAIM_REGISTRATION_DATE,
                        LOSS_DATE,
                        CLAIM_TYPE,
                        CLAIM_AMOUNT,
                        APPROVED_AMOUNT,
                        CLAIM_STATUS,
                        ASSESSOR_ID,
                        BRANCH_ID
                    )
                ),
                256
            ),

            COALESCE(
                SOURCE_UPDATED_TS,
                _LOAD_TS,
                CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
            ),

            _FILE_NAME,
            _LOAD_TS,
            _BATCH_ID

        FROM (
            SELECT
                CLAIM_ID,
                POLICY_ID,
                CUSTOMER_ID,
                TRY_TO_DATE(CLAIM_REGISTRATION_DATE)
                    AS CLAIM_REGISTRATION_DATE,
                TRY_TO_DATE(LOSS_DATE)
                    AS LOSS_DATE,
                CLAIM_TYPE,
                TRY_TO_DECIMAL(CLAIM_AMOUNT, 18, 2)
                    AS CLAIM_AMOUNT,
                TRY_TO_DECIMAL(APPROVED_AMOUNT, 18, 2)
                    AS APPROVED_AMOUNT,
                CLAIM_STATUS,
                ASSESSOR_ID,
                BRANCH_ID,
                TRY_TO_TIMESTAMP_NTZ(SOURCE_UPDATED_TS)
                    AS SOURCE_UPDATED_TS,
                _FILE_NAME,
                _LOAD_TS,
                _BATCH_ID,

                ROW_NUMBER() OVER (
                    PARTITION BY CLAIM_ID
                    ORDER BY
                        TRY_TO_TIMESTAMP_NTZ(SOURCE_UPDATED_TS)
                            DESC NULLS LAST,
                        _LOAD_TS DESC
                ) AS RN

            FROM BRONZE.STREAM_CLAIMS
            WHERE CLAIM_ID IS NOT NULL
        )
        WHERE RN = 1;

    END IF;

    V_ROWS := SQLROWCOUNT;

    -- 4. Stop if no incoming records
    IF (V_ROWS = 0) THEN

        COMMIT;
        V_TXN_STARTED := FALSE;

        RETURN 'No new claims available for processing.';

    END IF;


    -- 5. Expire existing versions when hash changes

    UPDATE SILVER.CLAIMS_SCD2 T

    SET
        EFFECTIVE_END_DATE =
            CASE
                WHEN S.EFFECTIVE_START_DATE > T.EFFECTIVE_START_DATE
                    THEN S.EFFECTIVE_START_DATE
                ELSE DATEADD(
                    MILLISECOND,
                    1,
                    T.EFFECTIVE_START_DATE
                )
            END,

        IS_CURRENT = FALSE

    FROM TMP_CLAIMS_SCD2 S

    WHERE T.CLAIM_ID = S.CLAIM_ID
      AND T.IS_CURRENT = TRUE
      AND T.RECORD_HASH <> S.RECORD_HASH;


    -- 6. Insert new claims and changed versions

    INSERT INTO SILVER.CLAIMS_SCD2 (
        CLAIM_ID,
        POLICY_ID,
        CUSTOMER_ID,
        CLAIM_REGISTRATION_DATE,
        LOSS_DATE,
        CLAIM_TYPE,
        CLAIM_AMOUNT,
        APPROVED_AMOUNT,
        CLAIM_STATUS,
        ASSESSOR_ID,
        BRANCH_ID,
        SOURCE_UPDATED_TS,
        RECORD_HASH,
        EFFECTIVE_START_DATE,
        EFFECTIVE_END_DATE,
        IS_CURRENT,
        VERSION_NUMBER,
        IS_DELETED,
        _FILE_NAME,
        _LOAD_TS,
        _BATCH_ID
    )

    SELECT
        S.CLAIM_ID,
        S.POLICY_ID,
        S.CUSTOMER_ID,
        S.CLAIM_REGISTRATION_DATE,
        S.LOSS_DATE,
        S.CLAIM_TYPE,
        S.CLAIM_AMOUNT,
        S.APPROVED_AMOUNT,
        S.CLAIM_STATUS,
        S.ASSESSOR_ID,
        S.BRANCH_ID,
        S.SOURCE_UPDATED_TS,
        S.RECORD_HASH,

        CASE
            WHEN H.MAX_EFFECTIVE_START_DATE IS NOT NULL
             AND S.EFFECTIVE_START_DATE <= H.MAX_EFFECTIVE_START_DATE
            THEN DATEADD(
                MILLISECOND,
                1,
                H.MAX_EFFECTIVE_START_DATE
            )
            ELSE S.EFFECTIVE_START_DATE
        END,

        '9999-12-31 23:59:59'::TIMESTAMP_NTZ,

        TRUE,

        COALESCE(H.MAX_VERSION, 0) + 1,

        FALSE,

        S._FILE_NAME,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
        S._BATCH_ID

    FROM TMP_CLAIMS_SCD2 S

    LEFT JOIN (
        SELECT
            CLAIM_ID,
            MAX(VERSION_NUMBER) AS MAX_VERSION,
            MAX(EFFECTIVE_START_DATE) AS MAX_EFFECTIVE_START_DATE
        FROM SILVER.CLAIMS_SCD2
        GROUP BY CLAIM_ID
    ) H
        ON S.CLAIM_ID = H.CLAIM_ID

    WHERE NOT EXISTS (
        SELECT 1
        FROM SILVER.CLAIMS_SCD2 C
        WHERE C.CLAIM_ID = S.CLAIM_ID
          AND C.IS_CURRENT = TRUE
          AND C.RECORD_HASH = S.RECORD_HASH
    );


    -- 7. Commit transaction

    COMMIT;
    V_TXN_STARTED := FALSE;

    RETURN
        'SCD2 processing completed successfully. Incoming records: '
        || V_ROWS;

EXCEPTION
    WHEN OTHER THEN

        IF (V_TXN_STARTED) THEN
            ROLLBACK;
        END IF;

        RAISE;

END;
$$;

CREATE OR REPLACE STREAM BRONZE.STREAM_CLAIMS
ON TABLE BRONZE.CLAIMS
APPEND_ONLY = TRUE;

SELECT * FROM BRONZE.STREAM_CLAIMS;

CALL SILVER.SP_LOAD_CLAIMS_SCD2(FALSE);

SELECT * FROM SILVER.CLAIMS_SCD2; 