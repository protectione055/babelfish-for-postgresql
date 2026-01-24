# Spec Delta: database-link

## MODIFIED Requirements

### Requirement: Create and manage database links
The system SHALL provide DDL to create, alter, and drop database links.

#### Scenario: Create a private fixed-user database link
- **GIVEN** a user with privilege to create database links
- **WHEN** they execute `CREATE DATABASE LINK mylink CONNECT TO remote_user IDENTIFIED BY 'secret' USING 'connstr'` with `FDW postgres_fdw`
- **THEN** the system creates a `pg_dblink` entry for `mylink`
- **AND** creates/updates the corresponding `FOREIGN SERVER` and `USER MAPPING`
- **AND** the system does NOT create a per-link `pg_class` placeholder anchor relation

#### Scenario: Drop a database link
- **GIVEN** a database link named `mylink` exists
- **WHEN** the user executes `DROP DATABASE LINK mylink`
- **THEN** the system removes the `pg_dblink` entry
- **AND** reconciles dependent `FOREIGN SERVER`/`USER MAPPING` objects according to documented rules
- **AND** the statement does NOT rely on dropping any per-link anchor relation

## ADDED Requirements

### Requirement: Isolate @dblink relations as RTE_DBLINK
The system SHALL represent `object@dblink` relations as a distinct range table entry kind (`RTE_DBLINK`) rather than overloading `RTE_RELATION`.

#### Scenario: Planning and execution treat remote objects distinctly
- **GIVEN** a database link `mylink`
- **WHEN** the user executes `SELECT * FROM employees@mylink`
- **THEN** the system constructs a query tree that represents `employees@mylink` as a dedicated DBLINK relation entry
- **AND** the planner/executor do not treat the remote object as a `pg_class` relation

#### Scenario: User-visible output does not expose legacy anchors
- **GIVEN** a database link `mylink`
- **WHEN** the user executes `EXPLAIN SELECT * FROM employees@mylink`
- **THEN** the output identifies the scanned relation as `employees@mylink` (or equivalent remote-identifying form)
- **AND** does not mention any per-link anchor relation name
