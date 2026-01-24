# Design: Oracle-style DATABASE LINK on PostgreSQL

## Overview
This change adds an Oracle-compatible `DATABASE LINK` user experience (notably `object@dblink`) while delegating execution, pushdown, and connectivity to PostgreSQL FDWs.

Key ideas:
- A `pg_dblink` catalog stores link definitions and maps them to FDW objects.
- Each dblink owns a placeholder relation in `pg_class` whose OID acts as a stable anchor for planner/executor invariants.
- Query parsing recognizes `object@dblink` and injects a relation reference that carries remote coordinates (dblink name + remote object name) and a cached column signature.
- Planning binds the placeholder relation to the FDW driver selected by the dblink and produces a foreign scan (or equivalent FDW plan) enabling predicate pushdown.

## DDL mapping to PostgreSQL objects
### CREATE DATABASE LINK
- Creates a `pg_dblink` row.
- Creates a `FOREIGN SERVER` using the chosen FDW driver.
- Creates `USER MAPPING` entries depending on auth mode:
  - fixed-user: link-level mapping stored as a mapping for a designated local role or as a shared mapping mechanism.
  - current-user/connected-user: relies on per-user mappings keyed off the effective execution identity.
- Creates a `pg_class` placeholder relation (relkind TBD; treated as a foreign/virtual relation for planning) and records its OID in `pg_dblink`.

### ALTER/DROP DATABASE LINK
- Updates/removes the `pg_dblink` row and reconciles the dependent FDW objects.

## Name resolution and RTE injection
- Parser/grammar recognizes `object@dblink` and resolves `dblink` through `pg_dblink`.
- The RTE is created with `relid = pg_dblink.anchor_relid` and augmented with remote coordinates.

## FDW metadata hook for column discovery
- Add an FDW-facing hook to resolve remote column definitions for `object@dblink`.
- The hook receives the dblink name, remote object identity, and execution identity,
  and returns a tuple descriptor plus a stable schema signature.
- Core uses the hook during parse/planning to populate RTE column types and to
  detect remote schema drift for view refresh and replanning.

## View support and schema drift refresh
- Views that reference `@dblink` relations are supported.
- Remote table schema is refreshed at planning time when executing the view:
  - fetch remote signature (columns/types)
  - compare with cached signature stored in the view/query metadata
  - if changed: update in-memory mapping and force replanning
- Additive changes should be auto-adapted for star projections; breaking changes should error with clear diagnostics.

## Testing strategy
- Regression tests use `postgres_fdw` to validate:
  - parser syntax `@dblink`
  - FDW pushdown behavior
  - view persistence and refresh
  - permission handling

## Compatibility notes
- Some Oracle features (e.g., `SHARED` connection reuse, global name enforcement) are out of scope initially or may be implemented as best-effort.
