--
-- Regression tests for DATABASE LINK error handling and connstr parsing
--

SELECT current_database() AS current_database,
  current_setting('port') AS current_port
\gset

SELECT btrim(split_part(current_setting('unix_socket_directories'), ',', 1)) AS current_sockdir
\gset

\set dblink_connstr_base 'dbname=' :current_database ' port=' :current_port ' host=' :current_sockdir
\set dblink_connstr_dupttl :dblink_connstr_base ' fdw=postgres_fdw meta_ttl=1 meta_ttl=2'
\set dblink_connstr_opts :dblink_connstr_base ' fdw=postgres_fdw meta_ttl=5 application_name=dblink_test'

SET client_min_messages = warning;

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- missing database link
SELECT count(*) FROM pg_class@no_such_dblink;

-- invalid fdw value in connection string
CREATE DATABASE LINK bad_fdw USING 'fdw=does_not_exist';

-- duplicate meta_ttl values
CREATE DATABASE LINK dup_ttl USING :'dblink_connstr_dupttl';

-- verify reserved connstr keys (fdw/meta_ttl) are not stored as foreign server options
CREATE DATABASE LINK link_opts CONNECT TO CURRENT_USER
	USING :'dblink_connstr_opts';

SELECT
	array_to_string(s.srvoptions, ',') LIKE '%fdw=%' AS srv_has_fdw,
	array_to_string(s.srvoptions, ',') LIKE '%meta_ttl=%' AS srv_has_meta_ttl
FROM pg_foreign_server s
WHERE s.srvname = 'link_opts';

DROP DATABASE LINK link_opts;
