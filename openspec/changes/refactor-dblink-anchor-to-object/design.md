## Context
The current implementation models `object@dblink` by creating a per-link placeholder “anchor” foreign table and parsing remote references into `RTE_RELATION` entries pointing at that anchor relation. Remote metadata (columns/types) is fetched via the FDW hook `GetDblinkTableMetadata`, and stored on the `RangeTblEntry` (`dblinkname`, `dblinknamespace`, `dblinkrelname`, `dblink_signature`, and `coltypes/typmods/collations`).

## Goals / Non-Goals
- Goals:
  - Represent remote `@dblink` relations as a dedicated RTE kind (`RTE_DBLINK`) to isolate them from ordinary relations.
  - Remove reliance on a per-link placeholder anchor relation, avoiding extra `pg_class` objects and reducing accidental coupling to relation semantics.
  - Preserve existing SQL surface syntax (`CREATE/DROP DATABASE LINK`, `object@dblink`).
  - Preserve existing FDW metadata hook contract.
- Non-Goals:
  - Changing or redesigning the FDW API beyond what is required for representing the new RTE kind.
  - Introducing a new SQL syntax for database links.

## Decisions
- Decision: Add a new `RTEKind` value `RTE_DBLINK`.
  - Rationale: Avoid ambiguous “`RTE_RELATION` + extra fields” encoding; force explicit handling and reduce accidental assumptions.

- Decision: Remove `pg_dblink.dblrelid` from the `pg_dblink` system catalog.
  - Rationale: The anchor relation is an implementation artifact; keeping a hard dependency on `pg_class` prevents clean isolation.
  - Consequence: This is a breaking system-catalog change and requires `initdb` (or an equivalent catalog-rebuild upgrade path).

- Decision: Make `EXPLAIN`/deparse prefer `remote_schema.remote_table@dblink` (or `remote_table@dblink` when schema is omitted) rather than anchor relation names.
  - Rationale: User-visible surfaces should reflect the user-written remote object reference.

### Alternatives considered
- Keep anchor relations but only add `RTE_DBLINK`:
  - Pro: Smaller change.
  - Con: Does not address catalog object proliferation and dependency coupling.

- Replace anchor with a generated foreign table on-the-fly per query:
  - Pro: Avoid persistent objects.
  - Con: Still abuses `pg_class`/relcache semantics; harder to reason about caching and permissions.

## Risks / Trade-offs
- Risk: Adding a new `RTEKind` touches many walker/switch statements.
  - Mitigation: Compile-time exhaustiveness via `switch` audits and targeted regression tests; prefer a single helper predicate (e.g., `rte_is_dblink(rte)`) used consistently.

- Risk: Some code paths may still rely on `rte->relid` being a valid `pg_class` OID.
  - Mitigation: Ensure `RTE_DBLINK` uses explicit planning/execution paths and does not enter code that assumes a real relation unless intentionally mediated.

## Migration Plan
- This change requires a cluster initialized with the new catalog definition.
- Existing clusters created with the old `pg_dblink` catalog layout are out of scope (no forward compatibility / in-place upgrade).

## Open Questions
- What is the desired `EXPLAIN` output text for `RTE_DBLINK` (e.g., `Foreign Scan on employees@mylink` vs `Foreign Scan on dblink(mylink, employees)`)?
