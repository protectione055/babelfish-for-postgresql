# database-link Specification (Delta)

## MODIFIED Requirements

### Requirement: View persistence and remote schema auto-refresh
The system SHALL support storing and executing views that reference `@dblink` relations, and SHALL refresh remote schema metadata at planning time.

With metadata caching enabled, the system MUST bound staleness by the configured TTL:
- Within TTL, the planner MAY reuse cached remote metadata and skip remote refresh.
- After TTL expiry, the planner MUST refresh remote metadata before planning/executing `@dblink` references.

#### Scenario: View uses cached metadata within TTL
- **GIVEN** a database link `mylink` exists with metadata TTL = 60s
- **AND** a view `v` references `remote_table@mylink`
- **WHEN** the same session executes `SELECT * FROM v` repeatedly within 60 seconds
- **THEN** the system reuses cached remote metadata without calling the FDW metadata hook each time

#### Scenario: Metadata refresh occurs after TTL
- **GIVEN** a database link `mylink` exists with metadata TTL = 1s
- **AND** a view `v` references `remote_table@mylink`
- **WHEN** the remote table schema changes
- **AND** the session executes `SELECT * FROM v` after the TTL has expired
- **THEN** the system refreshes remote metadata before planning/executing and uses the updated definition

## ADDED Requirements

### Requirement: Session-level TupleDesc cache for @dblink metadata
The system SHALL maintain a session-level cache of remote metadata (`TupleDesc` and remote signature) used for `@dblink` planning/execution.

- The cache key MUST include enough identity to avoid unsafe reuse across different remote bindings.
- At minimum, the key MUST include: foreign server identity, effective user identity, remote namespace, and remote relation name.

#### Scenario: Cache hit avoids remote callback
- **GIVEN** the session has a valid cache entry for (`serverid`, `userid`, `nspname`, `relname`)
- **WHEN** the planner needs remote metadata for `relname@dblink` again
- **THEN** it uses the cached `TupleDesc` and does not call `GetDblinkTableMetadata()`

### Requirement: Configurable TTL via USING connect string
A `CREATE DATABASE LINK` statement SHALL allow configuring the metadata cache TTL via a reserved key inside the `USING '<connect_string>'` string.

- Proposed syntax: `meta_ttl=<seconds>` (integer seconds)
- Default TTL: 60 seconds
- **Storage**: The TTL value SHALL be persisted in the `pg_dblink` catalog (or underlying storage) as a persistent attribute of the link.
- **Consumption**: The TTL parameter MUST be consumed by the database-link layer and MUST NOT be forwarded to the FDW/server connection options.

#### Scenario: Create link with explicit TTL
- **WHEN** a user executes `CREATE DATABASE LINK mylink CONNECT TO CURRENT_USER USING 'dbname=... fdw=postgres_fdw meta_ttl=10'`
- **THEN** the link uses a 10-second TTL for metadata caching

#### Scenario: Invalid TTL value
- **WHEN** a user executes `CREATE DATABASE LINK mylink ... USING '... meta_ttl=-1'`
- **THEN** the statement fails with an error indicating invalid TTL

### Requirement: Modifying TTL via ALTER DATABASE LINK
The system SHALL support modifying the metadata cache TTL via `ALTER DATABASE LINK`.

- **Mechanism**: Updating the `USING` clause string to include a new `meta_ttl` value.
- **Persistence**: The updated TTL is stored in the catalog.
- **Runtime Effect**: 
  - New sessions MUST use the updated TTL.
  - Active sessions MAY use the updated TTL immediately if they reload the link definition, but strictly enforcing immediate update in existing sessions is not required.

#### Scenario: Update TTL via ALTER
- **GIVEN** a database link `mylink` configured with `meta_ttl=60`
- **WHEN** the user executes `ALTER DATABASE LINK mylink USING '... meta_ttl=300 ...'`
- **THEN** the persisted TTL for `mylink` becomes 300 seconds

