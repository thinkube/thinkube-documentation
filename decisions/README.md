# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records (ADRs) for the Thinkube platform. ADRs document significant architectural and design decisions, providing context for future maintainers.

## What is an ADR?

An Architecture Decision Record captures a single architectural decision along with its context and consequences. ADRs help teams:

- Understand **why** decisions were made, not just **what** was decided
- Avoid revisiting the same debates repeatedly
- Onboard new team members with historical context
- Track the evolution of system design over time

## ADR Format

Each ADR follows this template:

```markdown
# ADR-XXX: [Title]

**Status**: [Proposed | Accepted | Deprecated | Superseded by ADR-YYY]
**Date**: YYYY-MM-DD
**Deciders**: [Names or roles]
**Technical Story**: [Ticket/issue reference if applicable]

## Context

What is the issue we're seeing that is motivating this decision or change?

## Decision

What is the change that we're proposing and/or doing?

## Consequences

### Positive
- What becomes easier?
- What improvements do we gain?

### Negative
- What becomes harder?
- What trade-offs are we accepting?

### Neutral
- What changes but is neither clearly positive nor negative?

## Alternatives Considered

### Alternative 1: [Name]
**Description**: ...
**Pros**: ...
**Cons**: ...
**Rejected because**: ...

### Alternative 2: [Name]
...

## References

- Links to related documentation
- External resources that informed the decision
- Related ADRs
```

## Naming Convention

ADRs are numbered sequentially and named:

```
XXX-descriptive-title.md
```

Examples:
- `001-kubernetes-distribution.md`
- `002-authentication-provider.md`
- `003-container-registry.md`

## Status Definitions

- **Proposed**: Decision under discussion
- **Accepted**: Decision approved and being implemented
- **Deprecated**: No longer relevant but kept for historical context
- **Superseded**: Replaced by a newer decision (reference the new ADR)

## Current ADRs

| # | Title | Status | Date |
|---|-------|--------|------|
| 001 | [Kubernetes Distribution Selection](001-kubernetes-distribution.md) | Accepted | 2025-11 |
| 002 | [Dual VPN Support (ZeroTier + Tailscale)](002-dual-vpn-support.md) | Accepted | 2025-10 |
| 003 | [Authentication Provider Selection](003-authentication-provider.md) | Accepted | 2024 |
| 004 | [Container Registry Selection](004-container-registry.md) | Accepted | 2024 |
| 005 | [Signed Certificates Only (No Self-Signed)](005-signed-certificates-only.md) | Accepted | 2024 |

## How to Create an ADR

1. **Copy the template** above
2. **Assign the next number** in sequence
3. **Fill in all sections** - especially Context and Consequences
4. **Get review** from relevant stakeholders
5. **Update this README** with the new ADR in the table
6. **Mark as Accepted** once implemented

## Guidelines

### Do
- Write for someone joining the project in 6 months
- Explain the problem before the solution
- Document alternatives that were considered
- Be specific about trade-offs
- Link to related resources

### Don't
- Skip the consequences section
- Assume readers know the context
- Make it too short (aim for 1-2 pages)
- Wait too long - document decisions when they're made
- Update ADRs after acceptance (create a new ADR instead)

## References

- [Michael Nygard's ADR template](https://github.com/joelparkerhenderson/architecture-decision-record)
- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
- [ADR GitHub Organization](https://adr.github.io/)
