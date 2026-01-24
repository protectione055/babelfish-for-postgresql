# Tasks: Add Oracle-style DATABASE LINK support

## 1. Catalog and DDL
- [ ] Define new system catalog `pg_dblink` (columns, indexes, ACL/ownership, dependencies).
- [ ] Implement `CREATE DATABASE LINK` with:
  - [ ] driver selection (FDW name)
  - [ ] connect string/options storage
  - [ ] authentication modes: fixed-user, current-user, connected-user
  - [ ] public vs private link visibility
  - [ ] `IF NOT EXISTS`
- [ ] Implement `ALTER DATABASE LINK` for updating connect options / credentials.
- [ ] Implement `DROP DATABASE LINK` and cleanup of linked FDW objects.

## 2. Parser and Name Resolution
- [ ] Extend grammar to parse `object@dblink` references.
- [ ] In Parser/RTE construction, resolve `@dblink` into a placeholder `pg_class` relid plus stored remote coordinates.
- [ ] Implement error reporting for unknown dblink / unknown remote object.

## 3. Planner/FDW Bridging
- [ ] Ensure `@dblink` relations plan using FDW routines for the selected driver.
- [ ] Implement predicate pushdown through the FDW path generation.
- [ ] Ensure plan invalidation when remote schema signature changes.
- [ ] Add FDW hook to fetch remote column metadata for `object@dblink`.
- [ ] Populate RTE column definitions from the FDW hook during parse/planning.

## 4. View Support and Auto-refresh
- [ ] Ensure view definitions containing `@dblink` references can be stored and restored.
- [ ] Implement runtime refresh of remote schema metadata at planning time.
- [ ] Define/implement boundaries for additive vs breaking schema changes.

## 5. Regression Tests
- [ ] Add regression tests using `postgres_fdw`:
  - [ ] basic `SELECT * FROM table@dblink`
  - [ ] join and predicate pushdown behavior
  - [ ] view creation + execution
  - [ ] schema drift: add column vs drop/rename/type change
  - [ ] error cases and permissions

## 6. Documentation
- [ ] Add user-facing docs for `DATABASE LINK` and `@dblink` usage.
- [ ] Document compatibility differences vs Oracle.
