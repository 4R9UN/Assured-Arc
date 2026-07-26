---
name: assured-arc-git-ci
description: "Use when configuring Git workflows, pull requests, commits, branches, GitHub Actions, continuous integration, release checks, or deployment gates."
---

# Assured Arc Git and CI

## Capability

Creates reviewable source control and continuous integration workflows with least privilege and reproducible checks.

## Workflow

1. Inspect repository conventions, protected branches, current workflows, and available validation commands.
2. Keep commits and pull requests focused on one outcome.
3. Pin trusted actions appropriately and grant minimum workflow permissions.
4. Cache only safe reproducible dependencies and never expose secrets to untrusted contributions.
5. Make local validation and CI validation consistent.

## Practical application

Use for test workflows, release checks, pull request templates, branch policies, and deployment gates.

## Prerequisites

Repository host, branch strategy, build and test commands, secret model, and deployment environment.

## Measurable benefit

Reduces integration failures and shortens feedback time without granting excessive automation permissions.