--# Copyright IBM Corp. All Rights Reserved.
--# SPDX-License-Identifier: Apache-2.0

/*
 * Count the number of rows in each table by data slice and insert range.
 * 
 * Usefull for investigating synopsis table size, as that depend on the number of data slices and insert ranges in a table
 * 
 */

CREATE TABLE DB_ROW_COUNTS_BY_SLICE_BY_INSERT_RANGE (
    TABSCHEMA  VARCHAR(128) NOT NULL
,   TABNAME    VARCHAR(128) NOT NULL
,   DATA_SLICE    SMALLINT NOT NULL
,   INSERT_RANGE  SMALLINT NOT NULL
,   ROW_COUNT   BIGINT
,   TS      TIMESTAMP NOT NULL
--,   PRIMARY KEY (TABSCHEMA, TABNAME, DATA_SLICE, INSERT_RANGE) ENFORCED
)
@

BEGIN
    FOR C AS cur CURSOR WITH HOLD FOR
        SELECT 'INSERT INTO DB_ROW_COUNTS_BY_SLICE_BY_INSERT_RANGE SELECT ''' || TABSCHEMA || ''',''' || TABNAME || ''', DS, IR, COUNT(*), CURRENT TIMESTAMP FROM '
            || '( SELECT DATASLICEID AS DS, DB.DB_INSERT_RANGE(ROWID) AS IR FROM "' ||  TABSCHEMA || '"."' || TABNAME || '") GROUP BY DS, IR WITH UR' AS S
        FROM SYSCAT.TABLES 
        WHERE TYPE = 'T'
        AND   TABLEORG = 'C'
        AND   TABNAME <> 'DB_ROW_COUNTS_BY_SLICE_BY_INSERT_RANGE'
        AND TABNAME LIKE '%TI_FCAAVP%'
        AND     (TABSCHEMA, TABNAME) NOT IN (SELECT TABSCHEMA, TABNAME FROM DB_ROW_COUNTS_BY_SLICE_BY_INSERT_RANGE)
        ORDER BY TABSCHEMA, TABNAME
        WITH UR
    DO
          EXECUTE IMMEDIATE C.S;
          COMMIT;
    END FOR;
END
@

-- Now query the table
SELECT
    TABSCHEMA
,   TABNAME
,   TS
,   COUNT(DISTINCT DATA_SLICE)    AS SLICES
,   COUNT(DISTINCT INSERT_RANGE)  AS RANGES
,   SUM(ROW_COUNT) AS ROW_COUNT
FROM
    DB_ROW_COUNTS_BY_SLICE_BY_INSERT_RANGE
GROUP BY
    TABSCHEMA
,   TABNAME
,   TS