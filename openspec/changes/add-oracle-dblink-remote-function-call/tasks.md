## 1. Proposal alignment
- [x] 1.1 Confirm intended SQL surface: `schema.func@dblink(args...)` (schema-qualified when required).
- [x] 1.2 Confirm initial scope: scalar-return functions only (procedures / OUT / ref cursors deferred).
- [x] 1.3 Confirm context limitation: support only in SELECT targetlists in the initial release.

## 2. Implementation
- [x] 2.1 Extend grammar / parse analysis to recognize remote routine references (function-name annotated with DBLINK name).
- [x] 2.2 Add an internal expression representation for remote routine invocation (new node or existing node with DBLINK fields) that survives parse/analyze/deparse.
- [x] 2.3 Add a new FDW API hook to resolve remote routine metadata (overload resolution, return type, remote SQL template).
- [x] 2.4 Add a session-level cache for resolved routine metadata (keyed by server/user/dblink + routine identity + arg signature + remote signature).
- [x] 2.5 Teach planner/executor/FDW integration to execute remote routine invocations through the selected FDW driver.
- [x] 2.6 Update deparser and EXPLAIN for stable output (`func@dblink(...)`).

## 3. Tests
- [x] 3.1 Add regression tests for successful remote scalar function invocation.
- [x] 3.2 Add tests for overload resolution, explicit casts, and deterministic errors.
- [x] 3.3 Add tests for unsupported FDWs / missing hooks.

## 4. Validation
- [x] 4.1 Run: `openspec validate add-oracle-dblink-remote-function-call --strict --no-interactive`
