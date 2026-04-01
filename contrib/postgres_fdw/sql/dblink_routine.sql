-- ===================================================================
-- tests for @dblink remote routine invocation: func@dblink(...)
-- ===================================================================
-- Keep this focused on core functionality:
--  - successful scalar routine invocation via postgres_fdw
--  - overload ambiguity + explicit casts
--  - deterministic parser restrictions/errors
--  - unsupported FDW (missing routine hooks)

SELECT current_database() AS current_database,
  current_setting('port') AS current_port
\gset

SELECT btrim(split_part(current_setting('unix_socket_directories'), ',', 1)) AS current_sockdir
\gset

\set dblink_connstr_fdw 'dbname=' :current_database ' port=' :current_port ' host=' :current_sockdir ' fdw=postgres_fdw meta_ttl=0'

SET client_min_messages = warning;

CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE EXTENSION IF NOT EXISTS file_fdw;

-- ===================================================================
-- Remote database setup (isolate remote routines from local catalog)
-- ===================================================================
DROP DATABASE IF EXISTS dblink_routine_db;
CREATE DATABASE dblink_routine_db;

\connect dblink_routine_db

CREATE SCHEMA dblink_routine_s;

CREATE FUNCTION public.dblink_add1(i int)
RETURNS int
LANGUAGE sql
AS $$ SELECT $1 + 1 $$;

CREATE FUNCTION dblink_routine_s.add1(i int)
RETURNS int
LANGUAGE sql
AS $$ SELECT $1 + 1 $$;

CREATE FUNCTION public.ovl(v varchar)
RETURNS text
LANGUAGE sql
AS $$ SELECT 'varchar' $$;

CREATE FUNCTION public.ovl(v bpchar)
RETURNS text
LANGUAGE sql
AS $$ SELECT 'bpchar' $$;

\connect :current_database

-- ===================================================================
-- 3.1 Successful remote scalar function invocation
-- ===================================================================
DO $d$
BEGIN
    EXECUTE format(
        'CREATE DATABASE LINK dblink_routine CONNECT TO CURRENT_USER USING %L',
        'dbname=dblink_routine_db port=' || current_setting('port') ||
        ' host=' || btrim(split_part(current_setting('unix_socket_directories'), ',', 1)) ||
        ' fdw=postgres_fdw meta_ttl=0'
    );
END;
$d$;

SELECT dblink_add1@dblink_routine(41) AS v;

SELECT dblink_routine_s.add1@dblink_routine(41) AS v;

CREATE VIEW dblink_routine_view AS
	SELECT dblink_routine_s.add1@dblink_routine(41) AS v;

SELECT pg_get_viewdef('dblink_routine_view'::regclass) LIKE '%add1@dblink_routine(41)%' AS view_keeps_syntax;

DROP VIEW dblink_routine_view;

-- ===================================================================
-- 3.2 Overload resolution, explicit casts, deterministic errors
-- ===================================================================
SELECT ovl@dblink_routine(NULL);

SELECT ovl@dblink_routine(NULL::varchar) AS v;

SELECT ovl@dblink_routine(NULL::bpchar) AS v;

SELECT no_such_remote@dblink_routine(1);

SELECT 1 WHERE dblink_add1@dblink_routine(1) = 2;

-- ===================================================================
-- 3.3 Unsupported FDWs / missing hooks
-- ===================================================================
-- Use an existing FDW that doesn't implement DBLINK metadata hooks.
CREATE DATABASE LINK dblink_routine_unsupported CONNECT TO CURRENT_USER
	USING 'fdw=file_fdw';

-- cleanup
DROP DATABASE LINK dblink_routine;
DROP EXTENSION file_fdw;

DROP DATABASE dblink_routine_db;
