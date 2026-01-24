# Tasks: Add Oracle-style DATABASE LINK support

## 1. Catalog and DDL
- [x] Define new system catalog `pg_dblink` (columns, indexes, ACL/ownership, dependencies).
- [x] Implement `CREATE DATABASE LINK` with:
  - [x] driver selection (FDW name)
  - [x] connect string/options storage
  - [x] authentication modes: fixed-user, current-user, connected-user
  - [x] public vs private link visibility
  - [x] `IF NOT EXISTS`
- [x] Implement `ALTER DATABASE LINK` for updating connect options / credentials.
- [x] Implement `DROP DATABASE LINK` and cleanup of linked FDW objects.

## 2. Parser and Name Resolution
- [x] Extend grammar to parse `object@dblink` references.
- [x] In Parser/RTE construction, resolve `@dblink` into a placeholder `pg_class` relid plus stored remote coordinates.
- [x] Implement error reporting for unknown dblink / unknown remote object.

## 3. Planner/FDW Bridging
- [x] Ensure `@dblink` relations plan using FDW routines for the selected driver.
- [x] Implement predicate pushdown through the FDW path generation.
- [x] Ensure plan invalidation when remote schema signature changes.
- [x] Add FDW hook to fetch remote column metadata for `object@dblink`.
- [x] Populate RTE column definitions from the FDW hook during parse/planning.

## 4. View Support and Auto-refresh
- [x] Ensure view definitions containing `@dblink` references can be stored and restored.
- [x] Implement runtime refresh of remote schema metadata at planning time.
- [x] Define/implement boundaries for additive vs breaking schema changes.

## 5. Regression Tests
- [x] Add regression tests using `postgres_fdw`:
  - [x] basic `SELECT * FROM table@dblink`
  - [x] join and predicate pushdown behavior
  - [x] view creation + execution
  - [x] schema drift: add column vs drop/rename/type change
  - [x] error cases and permissions

## 6. Documentation
- [x] Add user-facing docs for `DATABASE LINK` and `@dblink` usage.
- [x] Document compatibility differences vs Oracle.
