---
name: assured-arc-security-privacy
description: "Use when handling authentication, authorization, secrets, untrusted input, personal data, dependency risk, file access, network access, or security review."
---

# Assured Arc Security and Privacy

## Capability

Applies practical threat boundaries, least privilege, safe secret handling, and privacy-aware data flow to development tasks.

## Workflow

1. Identify assets, actors, trust boundaries, sensitive data, and external dependencies.
2. Validate untrusted input at the boundary and encode output for its destination.
3. Enforce authorization server side and grant only required filesystem, network, and tool access.
4. Keep secrets out of source, logs, errors, fixtures, and generated documentation.
5. Verify abuse cases, failure behavior, dependency provenance, and rollback.

## Practical application

Use for login flows, API keys, uploads, webhooks, MCP tools, installers, telemetry, and data exports.

## Prerequisites

Data classification, threat model, authentication system, deployment environment, and organizational requirements.

## Measurable benefit

Reduces common security defects and prevents sensitive information from leaking through configuration or diagnostics.