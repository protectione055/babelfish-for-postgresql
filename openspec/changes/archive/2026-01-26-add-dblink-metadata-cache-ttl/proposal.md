# Change: Add session TupleDesc cache for @dblink metadata (TTL)

## Why
Planning-time metadata refresh for `object@dblink` currently requires calling the FDW hook `GetDblinkTableMetadata()` each time the planner needs remote table definition. This can add significant latency and load (especially for views that are executed frequently), even when the remote schema is stable.

A session-level cache with a configurable TTL can reduce repeated remote metadata fetches while keeping schema drift handling bounded.

## What Changes
- Add a session-level cache for remote `TupleDesc` (and signature) used by `@dblink` planning/execution.
- Before calling `GetDblinkTableMetadata()`, the system checks the session cache:
  - If a matching entry exists and is within its validity period, reuse it and skip the remote callback.
  - Otherwise, call `GetDblinkTableMetadata()`, then populate/refresh the cache entry.
- Allow users to configure the metadata cache TTL when creating a database link via a reserved parameter in `USING '<connect_string>'`.
  - Default TTL: 60 seconds.
  - The TTL parameter is consumed by the database-link layer and MUST NOT be forwarded to the FDW/server connection options.

## Non-Goals
- Cross-session/shared metadata cache.
- Strong remote-DDL invalidation without remote contact (TTL remains the primary validity rule).
- Changing the semantics of `fdw=<fdwname>` selection.

## Impact
- Affected specs: `database-link`
- Affected code (expected):
  - Planner metadata injection for dblink (e.g. `src/backend/optimizer/util/plancat.c` dblink path)
  - DBLink DDL parsing to extract reserved parameters from `USING` connect string (e.g. `src/backend/commands/foreigncmds.c`)
  - FDW callers that currently depend on always-fresh remote metadata

## Compatibility
- Default behavior changes from “always fetch remote metadata” to “cache metadata for up to 60s per session”.
- Remote DDL changes may become visible with a delay bounded by TTL (unless the cache is bypassed/expired).
- Setting TTL to 0 (or a minimal value) can approximate the previous always-refresh behavior.
