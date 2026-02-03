# Spec Delta: database-link

## ADDED Requirements

### Requirement: Invoke remote functions via @dblink without local definitions
The system SHALL allow invoking remote scalar functions using Oracle-style `function_name@dblink(arglist...)` syntax.

When a remote routine requires a schema qualifier, the system SHALL support `schema.function_name@dblink(arglist...)`.

The invocation MUST NOT require creating a local `CREATE FUNCTION` wrapper or otherwise predefining the remote routine signature locally.

The system MUST resolve the remote routine signature and return type using the FDW driver configured for the database link.

#### Scenario: Basic remote scalar function call
- **GIVEN** a database link `mylink` configured to use an FDW that supports remote routine invocation (e.g., `oracle_fdw`)
- **WHEN** a user executes `SELECT remote_func@mylink(42)`
- **THEN** the system resolves `remote_func` on the remote side using the link
- **AND** returns a single scalar value with a concrete PostgreSQL type

#### Scenario: Schema-qualified remote scalar function call
- **GIVEN** a database link `mylink` configured to use an FDW that supports remote routine invocation (e.g., `oracle_fdw`)
- **WHEN** a user executes `SELECT hr.remote_func@mylink(42)`
- **THEN** the system resolves `hr.remote_func` on the remote side using the link
- **AND** returns a single scalar value with a concrete PostgreSQL type

#### Scenario: Ambiguous overload requires explicit casts
- **GIVEN** a database link `mylink` configured to use an FDW that supports remote routine invocation
- **AND** the remote database defines multiple overloads of `remote_func` that differ only by argument type
- **WHEN** a user executes `SELECT remote_func@mylink('1')`
- **THEN** the system errors with a message indicating ambiguous remote overload resolution
- **AND** the error advises adding an explicit cast (e.g., `SELECT remote_func@mylink('1'::int4)`)

### Requirement: Initial release supports remote routine calls in SELECT targetlists only
In the initial release, the system SHALL support `func@dblink(...)` only when it appears in a SELECT targetlist.

#### Scenario: Non-targetlist usage is rejected
- **GIVEN** a database link `mylink` configured to use an FDW that supports remote routine invocation
- **WHEN** a user executes `SELECT 1 WHERE remote_func@mylink(1) = 1`
- **THEN** the system errors indicating remote routine invocation is only supported in SELECT targetlists in this release

### Requirement: Volatility and snapshot semantics follow remote execution behavior
The system SHALL treat `func@dblink(...)` as a remote execution whose result depends on remote-side semantics and FDW transaction behavior.

For planning purposes, the system SHOULD model `func@dblink(...)` as VOLATILE and PARALLEL UNSAFE.

#### Scenario: Planner does not fold remote call as a constant
- **GIVEN** a database link `mylink` configured to use an FDW that supports remote routine invocation
- **WHEN** a user executes `EXPLAIN SELECT remote_func@mylink(1)`
- **THEN** the plan does not treat the remote call as a locally immutable constant

### Requirement: Clear errors when FDW does not support remote routine invocation
If the selected FDW driver does not implement the required remote routine hook(s), the system SHALL reject `func@dblink(...)` with a clear error.

#### Scenario: Missing FDW hook
- **GIVEN** a database link `mylink` configured to use an FDW that does not support remote routine invocation
- **WHEN** a user executes `SELECT remote_func@mylink(1)`
- **THEN** the system errors indicating the FDW does not support DBLINK remote routine invocation

### Requirement: Deparse and EXPLAIN preserve func@dblink syntax
The system SHALL preserve user-written `func@dblink(...)` in deparse output and SHOULD present the same form in `EXPLAIN`.

#### Scenario: View definition keeps remote routine syntax
- **GIVEN** a view is created using `CREATE VIEW v AS SELECT remote_func@mylink(42)`
- **WHEN** a user queries `SELECT pg_get_viewdef('v'::regclass)`
- **THEN** the output contains `remote_func@mylink(42)` (or an equivalent semantically identical form)

### Requirement: Cache resolved remote routine metadata
The system SHALL maintain a session-level cache of resolved remote routine metadata used for typing and planning `func@dblink(...)`.

At minimum, the cache key MUST include: foreign server identity, effective user identity, database link name, remote routine identity, and an argument-signature discriminator.

#### Scenario: Cache hit avoids repeated remote dictionary lookups
- **GIVEN** a session has already resolved metadata for `remote_func@mylink(int4)`
- **WHEN** the session executes the same call again
- **THEN** the system uses cached routine metadata and avoids redundant remote metadata lookups within the configured TTL
