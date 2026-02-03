# Change: Support remote function invocation over Oracle-style DBLINK without predefining local function signatures

## Why
Oracle users expect to call remote functions and procedures using `name@dblink(args...)` without first creating local wrapper functions. Today, the DBLINK feature only supports remote relations (`object@dblink`) and requires local objects (or explicit wrappers) for invoking remote routines.

Adding first-class remote routine invocation improves Oracle compatibility and removes friction for ad-hoc usage, migrations, and dynamic SQL patterns.

## What Changes
- Add support for Oracle-style remote routine invocation syntax in SQL expressions:
  - `remote_function@dblink(arg1, arg2, ...)`
- In the initial release, the feature is supported only for function expressions in SELECT targetlists.
- Do not require a local `CREATE FUNCTION` / predefined signature for the remote routine.
- Extend the FDW dblink hook surface to allow an FDW (e.g., `oracle_fdw`) to:
  - Resolve remote routine overload based on argument count/types.
  - Provide the remote return type and optional argument coercion guidance.
  - Provide an FDW-specific remote SQL fragment used to execute the routine.
- Add metadata caching for resolved remote routine signatures (similar to the existing table metadata cache for `object@dblink`).
- Ensure `EXPLAIN` and deparse output preserves the user-written `func@dblink(...)` form and never exposes implementation artifacts.

## Impact
- Affected specs:
  - `database-link`
- Affected code areas (expected):
  - Parser/analyzer for function calls: `src/backend/parser/*`
  - FDW API surface: `src/include/foreign/fdwapi.h`
  - DBLINK metadata cache: `src/backend/foreign/foreign.c` and related cache utilities
  - Deparser: `src/backend/utils/adt/ruleutils.c`
  - Regression tests (pg_regress) to cover syntax, typing, and error paths
- Compatibility notes:
  - No behavior change for existing `object@dblink` relation references.
  - New syntax acceptance: `@dblink` in function position.
  - FDWs that do not implement the new routine-metadata hook will reject `func@dblink(...)` with a clear error.
