---
name: assured-arc-data-sql
description: "Use when designing relational data models, writing or optimizing SQL, planning migrations, validating data quality, or building data transformations."
---

# Assured Arc Data and SQL

## Capability

Designs explicit schemas and efficient queries while protecting data correctness and migration safety.

## Workflow

1. Inspect the database engine, schema, constraints, indexes, migration tool, and query patterns.
2. Define invariants, cardinality, retention, and transaction boundaries.
3. Use constraints for correctness and indexes for measured access paths.
4. Inspect query plans before speculative optimization.
5. Make migrations reversible where practical and test representative data, nulls, duplicates, and concurrency risks.

## Practical application

Use for tables, indexes, joins, reports, migrations, ETL, and data validation.

## Prerequisites

Database engine and version, schema, data volume, workload, and migration process.

## Measurable benefit

Reduces slow queries, inconsistent data, and deployment failures caused by unsafe schema changes.