---
name: assured-arc-configuration-management
description: "Use when designing or modifying application settings, environment variables, feature flags, config files, profiles, defaults, secrets references, or environment-specific behavior."
---

# Assured Arc Configuration Management

## Capability

Creates predictable, validated configuration with safe defaults and explicit precedence.

## Workflow

1. Identify configuration consumers, sources, precedence, and environment differences.
2. Separate nonsecret defaults from secret references.
3. Validate configuration at startup or the earliest safe boundary with actionable errors.
4. Preserve unknown user settings during merges unless explicit replacement is requested.
5. Document examples, migration, rollback, and platform-specific behavior.

## Practical application

Use for JSON, YAML, environment variables, profiles, installer options, feature flags, and MCP settings.

## Prerequisites

Current config schema, supported environments, and ownership of each value.

## Measurable benefit

Reduces environment drift, silent fallback errors, accidental secret exposure, and destructive configuration updates.