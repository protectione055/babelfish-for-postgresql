# Change: Refactor database link anchor to a DBLINK object and introduce RTE_DBLINK

## Why
Today, `object@dblink` is implemented by creating a per-link “anchor” foreign table and then parsing `object@dblink` into an `RTE_RELATION` that points at that anchor relation.

This has a few downsides:
- Remote relations are indistinguishable from ordinary relations at the RTE level, so unrelated planner/rewrite/executor code can accidentally apply “pg_class relation” semantics to remote objects.
- The placeholder anchor relation can leak into user-visible surfaces (e.g., `EXPLAIN`, debugging, catalogs) and creates extra persistent catalog objects and dependencies.
- The implementation couples the lifetime and semantics of a database link to a `pg_class` entry, even though a database link is conceptually its own object type.

## What Changes
- Introduce a dedicated range table entry kind `RTE_DBLINK` for `object@dblink` references, so remote objects are isolated from ordinary `RTE_RELATION` entries.
- Treat the current “anchor table” as an implementation detail to be removed in favor of a DBLINK object representation:
  - `CREATE DATABASE LINK` no longer creates a per-link placeholder anchor foreign table.
  - The `pg_dblink` catalog remains the source of truth for the link and its options.
  - The legacy `pg_dblink.dblrelid` will be removed.
- Update parser/planner/executor/deparser to recognize and process `RTE_DBLINK`:
  - Parser constructs `RTE_DBLINK` and stores remote identifiers (dblink name, remote schema/name) and schema signature.
  - Planner refreshes remote metadata at planning time and builds the appropriate `ForeignScan` plan using the configured FDW.
  - Executor builds the scan tuple type from cached remote metadata and uses the same FDW path as before.
- Update other modules that currently special-case `rte->dblinkname` on `RTE_RELATION` to instead handle `RTE_DBLINK` explicitly (e.g., `ruleutils`, rowmark selection, relcache/plancache interactions).

## Impact
- Affected specs:
  - `database-link`
- Affected code areas (non-exhaustive):
  - Parser: `src/backend/parser/parse_relation.c`, `src/include/nodes/parsenodes.h`
  - DDL: `src/backend/commands/foreigncmds.c`, `src/include/catalog/pg_dblink.h`
  - Planner: `src/backend/optimizer/util/plancat.c` and RTE expansion paths
  - Executor: `src/backend/executor/nodeForeignscan.c`
  - Deparser: `src/backend/utils/adt/ruleutils.c`
- Compatibility notes:
  - No SQL surface syntax change: `CREATE/DROP DATABASE LINK` and `object@dblink` remain.
  - **BREAKING**: System catalog layout changes by removing `pg_dblink.dblrelid`.
    - Existing clusters created with the old catalog definition are not supported by this change.
    - Applying the change requires `initdb` (or an equivalent upgrade process that recreates the catalog).
