# Project Context

## Purpose
This repository contains the PostgreSQL codebase with Babelfish-specific patches. The goal is to provide patched PostgreSQL binaries that enable Babelfish extensions (primarily T-SQL/SQL Server compatibility) while keeping divergence from upstream PostgreSQL minimal.

## Tech Stack
- C (PostgreSQL backend and utilities)
- SQL and PL/pgSQL
- Build systems: GNU Make, Autoconf, Meson
- Testing harnesses: pg_regress, TAP tests (Perl)

## Project Conventions

### Code Style
- Follow existing PostgreSQL coding conventions in each file.
- Keep changes small and localized; avoid reformatting unrelated code.
- Match surrounding indentation and brace style; prefer lower_case_with_underscores for C identifiers and SQL objects unless existing conventions differ.

### Architecture Patterns
- Core server code lives in src/backend; client tools in src/bin; shared headers in src/include.
- Extensions and optional modules are under contrib/.
- PL/pgSQL implementation is under src/pl/plpgsql.
- Babelfish-specific behavior should be isolated and minimal to reduce divergence from upstream PostgreSQL.

### Testing Strategy
- Use pg_regress for SQL-level regression tests.
- Use TAP tests (Perl) where applicable under src/test and contrib/*/t/.
- Update expected output files alongside any test changes.

### Git Workflow
- Work on the current development branch (BABEL_5_X_DEV__PG_17_X) unless instructed otherwise.
- Prefer small, focused commits; keep patches minimal and easy to rebase onto upstream PostgreSQL.

## Domain Context
- Babelfish aims to provide SQL Server compatibility on PostgreSQL. Changes should preserve PostgreSQL semantics unless explicitly required for Babelfish features.
- Many features are implemented in the babelfish_extensions repository; this repo focuses on core engine changes needed to support those extensions.

## Important Constraints
- Maintain compatibility with the target PostgreSQL major version (PG 17).
- Avoid behavioral changes that affect non-Babelfish users unless required.
- Keep patches as upstream-friendly as possible.

## External Dependencies
- babelfish-for-postgresql/babelfish_extensions (extensions that rely on these core patches)
