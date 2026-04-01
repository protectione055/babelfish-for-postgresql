-- ===================================================================
-- dblink access coverage derived from postgres_fdw.sql use cases
-- ===================================================================

SELECT current_database() AS current_database,
  current_setting('port') AS current_port
\gset

SELECT btrim(split_part(current_setting('unix_socket_directories'), ',', 1)) AS current_sockdir
\gset

\set dblink_connstr 'dbname=' :current_database ' port=' :current_port ' host=' :current_sockdir ' meta_ttl=0'

SET client_min_messages = warning;

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SCHEMA "dblink_fdw_s";
CREATE TABLE "dblink_fdw_s"."T 1" (
	c1 int NOT NULL,
	c2 int NOT NULL,
	c3 text,
	CONSTRAINT t1_pkey PRIMARY KEY (c1)
);
CREATE TABLE "dblink_fdw_s"."T 2" (
	c1 int NOT NULL,
	c2 int NOT NULL,
	c3 text,
	CONSTRAINT t2_pkey PRIMARY KEY (c1)
);

INSERT INTO "dblink_fdw_s"."T 1"
	SELECT id,
	       id % 5,
	       'AAA' || to_char(id, 'FM000')
	FROM generate_series(1, 20) id;
INSERT INTO "dblink_fdw_s"."T 2"
	SELECT id,
	       id % 7,
	       'BBB' || to_char(id, 'FM000')
	FROM generate_series(1, 20) id;

ANALYZE "dblink_fdw_s"."T 1";
ANALYZE "dblink_fdw_s"."T 2";

CREATE DATABASE LINK dblink_fdw_case CONNECT TO CURRENT_USER
	USING :'dblink_connstr';

SELECT count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case;
SELECT min(c1), max(c1), count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case;

-- simple query shapes (derived from postgres_fdw.sql)
SELECT c1, c3
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	ORDER BY c3, c1 OFFSET 5 LIMIT 3;

SELECT count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE false;

SELECT c1, c2, c3
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c1 = 10 AND c2 = 0 AND c3 >= 'AAA010';

-- aggregates
SELECT count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case;

SELECT c2, count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	GROUP BY c2
	ORDER BY c2;

SELECT c2, count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	GROUP BY c2
	HAVING count(*) > 3
	ORDER BY c2;

-- subqueries
SELECT c1
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c1 IN (SELECT c1 FROM "dblink_fdw_s"."T 2"@dblink_fdw_case WHERE c1 <= 3)
	ORDER BY c1;

SELECT c1
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c1 = (SELECT max(c1) FROM "dblink_fdw_s"."T 2"@dblink_fdw_case)
	ORDER BY c1;

-- parameterized / correlated shapes
PREPARE dblink_p1(int) AS
	SELECT count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 = $1;
EXECUTE dblink_p1(10);

PREPARE dblink_p2(int) AS
	SELECT count(*)
		FROM "dblink_fdw_s"."T 1"@dblink_fdw_case t1
		JOIN "dblink_fdw_s"."T 2"@dblink_fdw_case t2
		ON t1.c1 = t2.c1
		WHERE t1.c1 <= $1;
EXECUTE dblink_p2(3);
DEALLOCATE dblink_p1;
DEALLOCATE dblink_p2;

SELECT count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case t1
	WHERE EXISTS (
		SELECT 1
			FROM "dblink_fdw_s"."T 2"@dblink_fdw_case t2
			WHERE t2.c1 = t1.c1 AND t2.c1 <= 3
	);

SELECT count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c1 = ANY (ARRAY(
		SELECT c1 FROM "dblink_fdw_s"."T 2"@dblink_fdw_case WHERE c1 < 5
	));

SELECT count(*)
	FROM "dblink_fdw_s"."T 2"@dblink_fdw_case
	WHERE c1 = ANY (ARRAY(
		SELECT c1 FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 < 5
	));

-- used in CTE
WITH t AS (
	SELECT c1 FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 <= 3
)
SELECT t.c1, r.c3
	FROM t
	JOIN "dblink_fdw_s"."T 2"@dblink_fdw_case r
	ON t.c1 = r.c1
	ORDER BY t.c1;

-- fixed values + NULL
SELECT 'fixed' AS tag, NULL::int AS n, c1
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c1 = 1;

-- check special chars in shippable expressions
SELECT count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c3 = E'foo''s\\bar';

-- CASE / COALESCE / NULLIF patterns (stable, deterministic)
SELECT count(*)
	FROM "dblink_fdw_s"."T 2"@dblink_fdw_case
	WHERE (CASE WHEN c1 > 15 THEN c1 END) < 20;

SELECT count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c1 > (CASE mod(c1, 4) WHEN 0 THEN 1 WHEN 2 THEN 50 ELSE 100 END);

-- WHERE patterns inspired by postgres_fdw.sql remotely-executable conditions
ALTER TABLE "dblink_fdw_s"."T 1" ADD COLUMN c4 int;
UPDATE "dblink_fdw_s"."T 1" SET c4 = c1;
UPDATE "dblink_fdw_s"."T 1" SET c4 = NULL WHERE c1 % 4 = 0;
ANALYZE "dblink_fdw_s"."T 1";

SELECT count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c4 IS NULL;
SELECT count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c4 IS NOT NULL;
SELECT count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE round(abs(c1)::numeric, 0) = 1;
SELECT count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 = -c1;
SELECT count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 = ANY(ARRAY[c2, 1, c1 + 0]);
SELECT count(*) FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 = (ARRAY[c1, c2, 3])[1];

SELECT count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE (c4 IS NULL) IS DISTINCT FROM true;

SELECT sum(coalesce(c4, 0))
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case;

SELECT count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE NULLIF(c2, 0) IS NULL;

SELECT count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case t1
	JOIN "dblink_fdw_s"."T 2"@dblink_fdw_case t2
	ON t1.c1 = t2.c1;

SELECT t1.c1, t1.c3 AS t1_c3, t2.c3 AS t2_c3
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case t1
	JOIN "dblink_fdw_s"."T 2"@dblink_fdw_case t2
	ON t1.c1 = t2.c1
	WHERE t1.c1 <= 3
	ORDER BY t1.c1;

-- deeper shapes mined from postgres_fdw.sql: set operations and join variants
SELECT c1
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c1 <= 3
UNION ALL
SELECT c1
	FROM "dblink_fdw_s"."T 2"@dblink_fdw_case
	WHERE c1 <= 2
ORDER BY 1;

SELECT c2
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c1 <= 5
UNION
SELECT c2
	FROM "dblink_fdw_s"."T 2"@dblink_fdw_case
	WHERE c1 <= 5
ORDER BY 1;

SELECT c1
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c1 <= 5
INTERSECT
SELECT c1
	FROM "dblink_fdw_s"."T 2"@dblink_fdw_case
	WHERE c1 BETWEEN 3 AND 7
ORDER BY 1;

SELECT c1
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case
	WHERE c1 <= 5
EXCEPT
SELECT c1
	FROM "dblink_fdw_s"."T 2"@dblink_fdw_case
	WHERE c1 <= 2
ORDER BY 1;

-- CROSS JOIN shape with ORDER BY/OFFSET/LIMIT patterns
SELECT t1.c1 AS t1_c1, t2.c1 AS t2_c1
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case t1
	CROSS JOIN (
		SELECT c1 FROM "dblink_fdw_s"."T 2"@dblink_fdw_case WHERE c1 <= 3
	) t2
	ORDER BY t1.c1, t2.c1
	LIMIT 5;

-- ANTI JOIN shape via NOT EXISTS (non-key join condition)
SELECT count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case t1
	WHERE NOT EXISTS (
		SELECT 1
			FROM "dblink_fdw_s"."T 2"@dblink_fdw_case t2
			WHERE t1.c1 = t2.c2
	);

-- outer join + placement of clauses (nullable-side derived table)
SELECT t1.c1, t1.c2, t2.c1 AS t2_c1, t2.c2 AS t2_c2
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case t1
	LEFT JOIN (
		SELECT * FROM "dblink_fdw_s"."T 2"@dblink_fdw_case WHERE c1 < 3
	) t2
	ON t1.c1 = t2.c1
	WHERE t1.c1 < 5
	ORDER BY t1.c1;

-- variant: top-level clause on nullable side kept outside
SELECT count(*)
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case t1
	LEFT JOIN (
		SELECT * FROM "dblink_fdw_s"."T 2"@dblink_fdw_case WHERE c1 < 3
	) t2
	ON t1.c1 = t2.c1
	WHERE (t2.c1 < 3 OR t2.c1 IS NULL) AND t1.c1 < 5;

-- multi-LEFT JOIN chain with nullable side propagation
SELECT t1.c1, t2.c2 AS t2_c2, t3.c3 AS t3_c3
	FROM (SELECT c1 FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 <= 5) t1
	LEFT JOIN (SELECT c1, c2 FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 <= 2) t2
	ON t1.c1 = t2.c1
	LEFT JOIN (SELECT c1, c3 FROM "dblink_fdw_s"."T 2"@dblink_fdw_case WHERE c1 <= 2) t3
	ON t2.c1 = t3.c1
	ORDER BY t1.c1;

-- RIGHT JOIN with derived relations to expose NULL-extended rows
SELECT t2.c1 AS right_c1, t1.c1 AS left_c1
	FROM (SELECT c1 FROM "dblink_fdw_s"."T 2"@dblink_fdw_case WHERE c1 <= 2) t1
	RIGHT JOIN (SELECT c1 FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 <= 5) t2
	ON t1.c1 = t2.c1
	ORDER BY t2.c1;

-- FULL JOIN with restrictions on joining relations (stable via coalesce ordering)
SELECT coalesce(t1.c1, t2.c1) AS k, t1.c1 AS a, t2.c1 AS b
	FROM (SELECT c1 FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 BETWEEN 5 AND 8) t1
	FULL JOIN (SELECT c1 FROM "dblink_fdw_s"."T 2"@dblink_fdw_case WHERE c1 BETWEEN 7 AND 10) t2
	ON t1.c1 = t2.c1
	ORDER BY k;

-- join in MATERIALIZED CTE with ORDER/OFFSET/LIMIT
WITH t (c1_1, c1_3, c2_1) AS MATERIALIZED (
	SELECT t1.c1, t1.c3, t2.c1
		FROM "dblink_fdw_s"."T 1"@dblink_fdw_case t1
		JOIN "dblink_fdw_s"."T 2"@dblink_fdw_case t2
		ON t1.c1 = t2.c1
)
SELECT c1_1, c2_1
	FROM t
	ORDER BY c1_3, c1_1
	OFFSET 10 LIMIT 5;

-- join two tables with ORDER/OFFSET/LIMIT (mirrors postgres_fdw.sql patterns)
SELECT t1.c1, t2.c2
	FROM "dblink_fdw_s"."T 1"@dblink_fdw_case t1
	JOIN "dblink_fdw_s"."T 2"@dblink_fdw_case t2
	ON t1.c1 = t2.c1
	ORDER BY t1.c1
	OFFSET 10 LIMIT 5;

-- outer join patterns (mirrors postgres_fdw.sql outer join coverage)
CREATE TABLE "dblink_fdw_s"."T 3" (
	c1 int NOT NULL,
	c2 int NOT NULL,
	CONSTRAINT t3_pkey PRIMARY KEY (c1)
);
CREATE TABLE "dblink_fdw_s"."T 4" (
	c1 int NOT NULL,
	c2 int NOT NULL,
	CONSTRAINT t4_pkey PRIMARY KEY (c1)
);

INSERT INTO "dblink_fdw_s"."T 3"
	SELECT id, id + 1 FROM generate_series(1, 12) id;
DELETE FROM "dblink_fdw_s"."T 3" WHERE c1 % 2 != 0;

INSERT INTO "dblink_fdw_s"."T 4"
	SELECT id, id + 1 FROM generate_series(1, 12) id;
DELETE FROM "dblink_fdw_s"."T 4" WHERE c1 % 3 != 0;

ANALYZE "dblink_fdw_s"."T 3";
ANALYZE "dblink_fdw_s"."T 4";

SELECT count(*)
	FROM "dblink_fdw_s"."T 3"@dblink_fdw_case t3
	JOIN "dblink_fdw_s"."T 4"@dblink_fdw_case t4
	ON t3.c1 = t4.c1;

SELECT count(*) AS left_rows,
	count(t4.c1) AS matched_rows
	FROM "dblink_fdw_s"."T 3"@dblink_fdw_case t3
	LEFT JOIN "dblink_fdw_s"."T 4"@dblink_fdw_case t4
	ON t3.c1 = t4.c1;

SELECT t3.c1 AS t3_c1, t4.c1 AS t4_c1
	FROM "dblink_fdw_s"."T 3"@dblink_fdw_case t3
	LEFT JOIN "dblink_fdw_s"."T 4"@dblink_fdw_case t4
	ON t3.c1 = t4.c1
	ORDER BY t3.c1;

-- additional join shapes (RIGHT/FULL, join with expressions, mixed local/remote)
SELECT count(*)
	FROM "dblink_fdw_s"."T 3"@dblink_fdw_case t3
	RIGHT JOIN "dblink_fdw_s"."T 4"@dblink_fdw_case t4
	ON t3.c1 = t4.c1;

SELECT count(*)
	FROM "dblink_fdw_s"."T 3"@dblink_fdw_case t3
	FULL JOIN "dblink_fdw_s"."T 4"@dblink_fdw_case t4
	ON t3.c1 = t4.c1;

-- FULL JOIN + WHERE clause, only matched/right-side rows
SELECT count(*)
	FROM "dblink_fdw_s"."T 3"@dblink_fdw_case t3
	FULL JOIN "dblink_fdw_s"."T 4"@dblink_fdw_case t4
	ON t3.c1 = t4.c1
	WHERE (t3.c1 = t4.c1 OR t3.c1 IS NULL);

SELECT count(*)
	FROM "dblink_fdw_s"."T 4"@dblink_fdw_case t4
	JOIN "dblink_fdw_s"."T 3"@dblink_fdw_case t3
	ON t3.c1 = t4.c1 + 1;

CREATE TABLE "dblink_fdw_s"."loc_ids"(id int PRIMARY KEY);
INSERT INTO "dblink_fdw_s"."loc_ids" VALUES (1), (2), (3), (30);

SELECT count(*)
	FROM "dblink_fdw_s"."loc_ids" l
	JOIN "dblink_fdw_s"."T 1"@dblink_fdw_case r
	ON r.c1 = l.id;

CREATE VIEW dblink_fdw_view AS
	SELECT c1, c3 FROM "dblink_fdw_s"."T 1"@dblink_fdw_case WHERE c1 <= 4;

-- verify view deparsing keeps object@dblink
SELECT pg_get_viewdef('dblink_fdw_view'::regclass);

SELECT count(*) FROM dblink_fdw_view;
SELECT * FROM dblink_fdw_view ORDER BY c1;

-- type/edge coverage (keep output stable via counts and explicit formatting)
SET TIME ZONE 'UTC';
SET datestyle = 'ISO, YMD';

CREATE TABLE "dblink_fdw_s"."T_types" (
	i_small int2 NOT NULL,
	i int NOT NULL,
	i_big int8 NOT NULL,
	n numeric(12,2) NOT NULL,
	t text,
	b boolean,
	ts timestamptz,
	ba bytea,
	ia int[]
);

INSERT INTO "dblink_fdw_s"."T_types" VALUES
	(-32768, -1, 2147483648, -1.25, 'neg', false, '2000-01-01 00:00:00+00', decode('00ff', 'hex'), ARRAY[1,2]),
	(0, 0, 0, 0.00, NULL, NULL, NULL, NULL, NULL),
	(32767, 2147483647, 9223372036854775807, 123456.78, 'max', true, '2038-01-19 03:14:07+00', decode('deadbeef', 'hex'), ARRAY[2,3,4]);

ANALYZE "dblink_fdw_s"."T_types";

SELECT count(*) FROM "dblink_fdw_s"."T_types"@dblink_fdw_case;
SELECT min(i_small), max(i_small), min(i), max(i) FROM "dblink_fdw_s"."T_types"@dblink_fdw_case;
SELECT count(*) FROM "dblink_fdw_s"."T_types"@dblink_fdw_case WHERE 2 = ANY(ia);

SELECT i, encode(ba, 'hex') AS ba_hex
	FROM "dblink_fdw_s"."T_types"@dblink_fdw_case
	ORDER BY i;

SELECT i,
	to_char(ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') AS ts_utc
	FROM "dblink_fdw_s"."T_types"@dblink_fdw_case
	WHERE ts IS NOT NULL
	ORDER BY i;

DROP VIEW dblink_fdw_view;
DROP TABLE "dblink_fdw_s"."T_types";
DROP TABLE "dblink_fdw_s"."loc_ids";
DROP DATABASE LINK dblink_fdw_case;
DROP SCHEMA "dblink_fdw_s" CASCADE;
