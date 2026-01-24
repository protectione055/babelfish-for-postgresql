# Change: Add Oracle-style DATABASE LINK support

## Why
PostgreSQL lacks an Oracle-compatible `DATABASE LINK` feature (e.g., `SELECT * FROM table@dblink`). Users typically emulate this with explicit `FOREIGN TABLE` objects or ad-hoc `dblink()` calls, which either create catalog bloat and require admin workflows, or lose optimizer pushdown and type safety.

This change introduces a first-class, Oracle-style `DATABASE LINK` user experience while reusing PostgreSQL FDW infrastructure for performance (predicate pushdown) and security (user mappings).

## What Changes
- Add `CREATE DATABASE LINK`, `ALTER DATABASE LINK`, and `DROP DATABASE LINK` statements.
- Add Oracle-style `object@dblink` name resolution in SQL (at minimum for `SELECT`, and for DML where the underlying FDW supports it).
- Introduce a new system catalog `pg_dblink` to store link definitions, including which FDW driver is used (e.g., `postgres_fdw` for regression testing).
- On link creation, create/maintain corresponding `FOREIGN SERVER` and `USER MAPPING` objects based on the chosen driver and authentication mode.
- Use a `pg_class` placeholder relation per dblink object as the stable RelID anchor to satisfy planner/executor invariants while keeping remote table definitions dynamic.
- Support view usage of `@dblink` references with automatic refresh semantics for remote schema drift (best-effort, with defined boundaries).

## Non-Goals (initial scope)
- Full Oracle distributed transaction semantics (2PC) and global name enforcement.
- Complete parity for `SHARED` links (may be unsupported or treated as a no-op initially).
- Arbitrary PL/SQL remote object invocation compatibility.

## Impact
- **New SQL surface**: Parser/grammar extensions and new DDL commands.
- **New catalog**: `pg_dblink` plus dependency/ACL semantics.
- **Planner/executor**: Binding dblink placeholders to FDW paths and ensuring plan invalidation on schema drift.
- **Testing**: Add regression coverage using `postgres_fdw`.

## Affected Areas
- Parser/grammar: `src/backend/parser/gram.y`, lexer/scanner as needed.
- Name resolution / RTE construction: `src/backend/parser/parse_relation.c`.
- Catalog: new `pg_dblink` definitions and SQL-visible views/functions as needed.
- Planner: `src/backend/optimizer/util/plancat.c` and/or hooks for FDW bridging.
- Node serialization: `src/backend/nodes/outfuncs.c`, `src/backend/nodes/readfuncs.c` to persist remote metadata in views.

## Security Considerations
- Must respect `FOREIGN SERVER` ACLs and `USER MAPPING` privileges.
- Credential handling must use existing mechanisms (user mappings or credential objects) and avoid exposing passwords in logs.
- `CONNECT TO CURRENT_USER` must map to PostgreSQL effective user semantics (including view `security_invoker` behavior).
