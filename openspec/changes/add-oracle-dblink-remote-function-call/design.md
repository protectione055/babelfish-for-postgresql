## Context
The existing DBLINK implementation supports `object@dblink` by representing the remote object as `RTE_DBLINK` and fetching remote table metadata via an FDW hook (`GetDblinkTableMetadata`). There is no first-class representation for remote routine invocation in expression position.

Oracle compatibility commonly relies on `routine@dblink(...)` where routine metadata is resolved remotely and no local wrapper is required.

## Goals / Non-Goals
- Goals:
  - Support `remote_function@dblink(arglist...)` in SQL expressions.
  - Support schema-qualified remote routines using `schema.function_name@dblink(arglist...)`.
  - In the initial release, support remote routine calls only when the call appears in a SELECT targetlist.
  - Avoid requiring local routine definitions.
  - Delegate remote routine resolution and SQL generation to the configured FDW driver.
  - Cache resolved routine metadata to avoid repeated remote dictionary round-trips.
  - Preserve stable user-facing deparse/EXPLAIN output.
- Non-Goals (initially):
  - Executing remote procedures in the initial release (no return, OUT parameters, ref cursors).
  - Supporting remote routine calls in WHERE/JOIN/ON/HAVING/GROUP BY, or other non-targetlist expression positions in the initial release.
  - Cross-dialect syntax beyond `@dblink` (e.g., SQL Server linked-server syntax).

## Decisions
- Decision: Add a dedicated FDW hook for remote routine resolution.
  - Rationale: Only the FDW knows how to interrogate the remote system catalogs and how to encode a routine call in the remote dialect.

- Decision: Make the routine-resolution hook forward-compatible with remote procedure support.
  - Rationale: We want the v1 implementation to be extensible without redesign when adding procedures.
  - Consequence: The hook contract should be able to represent:
    - Routine kind: function vs procedure
    - Return shape: scalar return type for functions; zero-return for procedures
    - Future extension: OUT parameters / composite returns / ref cursors (driver-specific)

- Decision: Require the planner/analyzer to obtain a concrete return type (a PostgreSQL type Oid) during analysis/planning.
  - Rationale: PostgreSQL needs a concrete type for expression planning, targetlist typing, and tuple descriptor construction.
  - Consequence: If the FDW cannot resolve a return type (e.g., ambiguous overload), the query errors with a deterministic message.

- Decision: Cache resolved routine metadata similarly to the existing TupleDesc cache for `object@dblink`.
  - Rationale: Remote dictionary queries are expensive; caching reduces latency and avoids repeated calls within TTL.

## Alternatives considered
- Add a built-in function like `dblink_call(link, name, args...)` returning TEXT/JSONB:
  - Pro: Avoids grammar changes and return-type resolution.
  - Con: Does not satisfy Oracle-style SQL surface and shifts typing burden onto users.

- Require explicit return-type casts for all remote routine calls:
  - Pro: Simpler typing.
  - Con: Poor usability; not aligned with Oracle behavior and makes simple calls cumbersome.

## Risks / Trade-offs
- Risk: Type mapping from Oracle types to PostgreSQL types can be lossy.
  - Mitigation: Keep mapping within the FDW; document limitations; allow explicit casts where needed.

- Risk: Overload resolution can be ambiguous when argument types are unknown (e.g., untyped string literals).
  - Mitigation: Define deterministic rules (e.g., require explicit casts in ambiguous cases) and return actionable errors.

- Risk: Security and user mapping for remote calls must match `object@dblink` semantics.
  - Mitigation: Reuse the same effective-user resolution and credential selection path used for `@dblink` scans.

- Risk: Volatility/snapshot semantics of remote execution do not match PostgreSQL local function classes.
  - Background: PostgreSQL STABLE functions are expected to return results that are stable within a statement/transaction snapshot.
  - For DBLINK routine calls, the FDW is expected to execute the call remotely and the observed value depends on remote-side behavior.
    - In practice, the time at which the remote transaction/snapshot is established is FDW-specific and commonly aligns with the scan/connection initialization (e.g., around `BeginIterateForeignScan`).
  - Mitigation: Treat remote routine calls as VOLATILE for planning purposes and document that result stability is governed by the remote system and FDW transaction behavior.

## Open Questions
- Should we support functions returning a row set (table functions) in a follow-up, and if so what is the preferred SQL surface and executor shape?
- For procedures, what is the preferred SQL surface (e.g., `CALL schema.proc@link(args...)`) and how should OUT/ref cursor be represented to the caller?
- What error taxonomy do we want for remote routine resolution failures (not found vs ambiguous vs permission), and should we standardize error codes per FDW?

## Migration Plan
- No catalog changes are expected for the proposal stage.
- The new feature is opt-in by using the new syntax.
