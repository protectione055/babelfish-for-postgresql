# Spec Delta: database-link

## ADDED Requirements

### Requirement: Create and manage database links
The system SHALL provide DDL to create, alter, and drop database links.

#### Scenario: Create a private fixed-user database link
- **GIVEN** a user with privilege to create database links
- **WHEN** they execute `CREATE DATABASE LINK mylink CONNECT TO remote_user IDENTIFIED BY 'secret' USING 'connstr'` with `FDW postgres_fdw`
- **THEN** the system creates a `pg_dblink` entry for `mylink`
- **AND** creates/updates the corresponding `FOREIGN SERVER` and `USER MAPPING`
- **AND** creates a `pg_class` placeholder anchor relation tied to `mylink`

#### Scenario: Create database link if not exists
- **GIVEN** a database link named `mylink` already exists
- **WHEN** the user executes `CREATE DATABASE LINK IF NOT EXISTS mylink ...`
- **THEN** the statement succeeds without creating a duplicate link

#### Scenario: Drop a database link
- **GIVEN** a database link named `mylink` exists
- **WHEN** the user executes `DROP DATABASE LINK mylink`
- **THEN** the system removes the `pg_dblink` entry
- **AND** reconciles dependent `FOREIGN SERVER`/`USER MAPPING` objects according to documented rules

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

#### Scenario: Additive remote schema change
- **GIVEN** a view `v` defined as `SELECT * FROM employees@mylink`
- **WHEN** the remote `employees` table adds a new column
- **THEN** executing `SELECT * FROM v` triggers remote schema refresh at planning time
- **AND** the query replans using the updated remote schema

#### Scenario: Breaking remote schema change
- **GIVEN** a view `v` references a specific column `salary` from `employees@mylink`
- **WHEN** the remote `salary` column is dropped or its type changes incompatibly
- **THEN** executing the view fails with an error describing the schema drift and remediation

### Requirement: Error handling and diagnostics
The system SHALL emit clear errors for unknown links, permission failures, and remote metadata fetch failures.

#### Scenario: Unknown database link
- **WHEN** a user executes `SELECT * FROM employees@no_such_link`
- **THEN** the system errors with a message indicating the missing database link
