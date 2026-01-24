# database-link Specification

## Purpose
TBD - created by archiving change add-database-link. Update Purpose after archive.
## Requirements
### Requirement: Create and manage database links
The system SHALL provide DDL to create, alter, and drop database links.

A `CREATE DATABASE LINK` statement SHALL allow selecting the FDW driver used by the link.

**Syntax (proposed):**
- The FDW driver is selected by providing a reserved key `fdw=<fdw_name>` inside the `USING '<connect_string>'` string.
- Example: `CREATE DATABASE LINK <name> ... USING '... fdw=oracle_fdw'`

If the `USING` connect string does not provide `fdw=<fdw_name>`, the system SHOULD default to `postgres_fdw` (to preserve demo/regression compatibility).

#### Scenario: Create a database link with explicit FDW driver
- **GIVEN** `oracle_fdw` is installed and the user has USAGE privilege on the foreign-data wrapper
- **WHEN** they execute `CREATE DATABASE LINK mylink CONNECT TO remote_user IDENTIFIED BY 'secret' USING 'connstr fdw=oracle_fdw'`
- **THEN** the system stores `oracle_fdw` as the driver for `mylink`
- **AND** creates/updates the corresponding FDW objects using `oracle_fdw`

#### Scenario: Create a database link without FDW clause (default)
- **GIVEN** the environment supports `postgres_fdw`
- **WHEN** the user executes `CREATE DATABASE LINK mylink CONNECT TO remote_user IDENTIFIED BY 'secret' USING 'connstr'`
- **THEN** the system binds `mylink` to `postgres_fdw` by default

### Requirement: Use @dblink syntax in queries
The system SHALL support referencing remote objects using `object_name@dblink` syntax.

#### Scenario: Basic remote select
- **GIVEN** a database link `mylink`
- **WHEN** the user executes `SELECT * FROM employees@mylink`
- **THEN** the query plans a foreign access using the FDW driver configured for `mylink`
- **AND** returns rows from the remote `employees` object

### Requirement: FDW metadata hook for column discovery
The system SHALL allow FDW plugins to provide remote column definitions for `object@dblink` via a dedicated hook.

#### Scenario: FDW supplies column metadata
- **GIVEN** a database link `mylink` bound to `postgres_fdw`
- **WHEN** the user executes `SELECT * FROM employees@mylink`
- **THEN** the FDW hook returns the column list and types for `employees`
- **AND** the planner uses those columns to type-check and plan the query

### Requirement: Predicate pushdown through FDW
The system SHALL enable predicate pushdown for `@dblink` relations via the configured FDW driver.

#### Scenario: Push down simple filter
- **GIVEN** a database link `mylink` configured to use `postgres_fdw`
- **WHEN** the user executes `SELECT * FROM employees@mylink WHERE employee_id = 42`
- **THEN** the FDW receives the restriction clause for remote evaluation where supported

### Requirement: Security and effective user mapping
The system SHALL determine remote credentials based on the database link authentication mode and the effective execution identity.

#### Scenario: CURRENT_USER mapping in a view
- **GIVEN** a view defined with an `@dblink` reference
- **AND** the view has `security_invoker = true`
- **WHEN** role `alice` queries the view
- **THEN** the system chooses remote credentials corresponding to `alice` for `CONNECT TO CURRENT_USER`

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

### Requirement: Error handling and diagnostics
The system SHALL emit clear errors for unknown links, permission failures, and remote metadata fetch failures.

#### Scenario: Unknown database link
- **WHEN** a user executes `SELECT * FROM employees@no_such_link`
- **THEN** the system errors with a message indicating the missing database link

### Requirement: Validate FDW driver selection
The system SHALL validate the selected FDW driver at `CREATE DATABASE LINK` time.

Validation MUST include:
- The FDW exists (installed/visible in `pg_foreign_data_wrapper`).
- The user has required privileges to use the FDW.
- The FDW supports dblink execution and remote metadata discovery required by `object@dblink`.

#### Scenario: FDW does not exist
- **WHEN** a user executes `CREATE DATABASE LINK mylink ... USING 'connstr fdw=no_such_fdw'`
- **THEN** the statement fails with an error indicating the FDW does not exist

#### Scenario: FDW exists but does not support dblink hooks
- **GIVEN** a foreign-data wrapper `some_fdw` exists
- **AND** `some_fdw` does not implement the dblink-required hook(s)
- **WHEN** a user executes `CREATE DATABASE LINK mylink ... USING 'connstr fdw=some_fdw'`
- **THEN** the statement fails with an error indicating the FDW is not supported for `DATABASE LINK`

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

