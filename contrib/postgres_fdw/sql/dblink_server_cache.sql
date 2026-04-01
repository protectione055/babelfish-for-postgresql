--
-- Regression test: dblink metadata cache must not be shared across servers
--

SELECT current_database() AS current_database,
  current_setting('port') AS current_port
\gset

SELECT btrim(split_part(current_setting('unix_socket_directories'), ',', 1)) AS current_sockdir
\gset

SET client_min_messages = warning;

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Setup two remote databases with same-named tables but different shapes
DROP DATABASE IF EXISTS dblink_db1;
DROP DATABASE IF EXISTS dblink_db2;
CREATE DATABASE dblink_db1;
CREATE DATABASE dblink_db2;

\connect dblink_db1
CREATE SCHEMA dblink_cache;
CREATE TABLE dblink_cache.test_remote_table (id int, data text);
INSERT INTO dblink_cache.test_remote_table VALUES (1, 'db1');

\connect dblink_db2
CREATE SCHEMA dblink_cache;
CREATE TABLE dblink_cache.test_remote_table (id int, payload text, extra int);
INSERT INTO dblink_cache.test_remote_table VALUES (1, 'db2', 42);

-- Back to the original database for link creation and queries
\connect :current_database

DO $d$
BEGIN
    EXECUTE format(
        'CREATE DATABASE LINK link_db1 CONNECT TO CURRENT_USER USING %L',
        'dbname=dblink_db1 port=' || current_setting('port') ||
        ' host=' || btrim(split_part(current_setting('unix_socket_directories'), ',', 1)) ||
        ' fdw=postgres_fdw meta_ttl=60'
    );
END;
$d$;

DO $d$
BEGIN
    EXECUTE format(
        'CREATE DATABASE LINK link_db2 CONNECT TO CURRENT_USER USING %L',
        'dbname=dblink_db2 port=' || current_setting('port') ||
        ' host=' || btrim(split_part(current_setting('unix_socket_directories'), ',', 1)) ||
        ' fdw=postgres_fdw meta_ttl=60'
    );
END;
$d$;

-- Populate per-server cache
SELECT * FROM dblink_cache.test_remote_table@link_db1 ORDER BY id;
SELECT * FROM dblink_cache.test_remote_table@link_db2 ORDER BY id;

-- Ensure link_db1 cache is not polluted by link_db2
SELECT * FROM dblink_cache.test_remote_table@link_db1 ORDER BY id;

-- Change remote schema in db1 and verify only link_db1 is affected
\connect dblink_db1
ALTER TABLE dblink_cache.test_remote_table RENAME COLUMN data TO data_v2;

\connect :current_database
SELECT * FROM dblink_cache.test_remote_table@link_db1 ORDER BY id;
SELECT * FROM dblink_cache.test_remote_table@link_db2 ORDER BY id;

-- Cleanup
DROP DATABASE LINK link_db1;
DROP DATABASE LINK link_db2;
DROP DATABASE dblink_db1;
DROP DATABASE dblink_db2;
