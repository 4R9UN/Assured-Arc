---
name: assured-arc-backend-api
description: "Use when building or modifying backend services, REST or GraphQL APIs, authentication boundaries, request validation, persistence, or background jobs."
---

# Assured Arc Backend and API

## Capability

Builds clear backend boundaries with validated inputs, stable contracts, safe failures, and focused tests.

## Workflow

1. Inspect the framework, routing, configuration, error, and persistence conventions.
2. Define the request and response contract, authorization rule, and failure semantics.
3. Keep transport, business logic, and persistence responsibilities separate only where the repository already benefits from that boundary.
4. Validate untrusted input and avoid secrets in logs or responses.
5. Add focused contract and behavior tests.

## Practical application

Use for API endpoints, workers, webhooks, authentication, database access, and service integrations.

## Prerequisites

Framework documentation, existing service patterns, data model, and security requirements.

## Measurable benefit

Reduces API drift, hidden validation gaps, and tightly coupled request handlers.