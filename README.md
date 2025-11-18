# Thinkube Documentation

Internal documentation, specifications, and developer guides for the Thinkube platform.

**License**: Apache License 2.0
**Copyright**: 2025 Alejandro Martínez Corriá

## Purpose

This repository serves as the **source of truth** for:
- Active technical specifications
- Architecture documentation
- Deployment procedures and dependencies
- Development standards and guidelines
- Architecture decision records

## Documentation Structure

### 📋 [specs/](specs/)
**Active Specifications** - Current technical specifications (v1.0)

These are ACTIVE specifications that define core Thinkube platform functionality:
- [thinkube-yaml-v1.0.md](specs/thinkube-yaml-v1.0.md) - Application deployment descriptor specification
- [template-manifest-v1.0.md](specs/template-manifest-v1.0.md) - Template repository structure
- [template-variables-v1.0.md](specs/template-variables-v1.0.md) - Template variable specification
- [health-endpoints-v1.0.md](specs/health-endpoints-v1.0.md) - Health check endpoint standards

### 🏗️ [architecture/](architecture/)
**System Architecture** - Platform design and structure

- [deployment-dependency-graph.md](architecture/deployment-dependency-graph.md) - Component deployment order and dependencies
- [diagrams/](architecture/diagrams/) - D2 diagram sources for architecture visualizations

### 🔧 [operations/](operations/)
**Operational Guides** - Deployment and maintenance procedures

- Component deployment matrix
- Troubleshooting guides
- Backup and restore procedures

### 💻 [development/](development/)
**Developer Guides** - Standards and conventions

- [component-readme-template.md](development/component-readme-template.md) - Standard template for component READMEs
- [documentation-standards.md](development/documentation-standards.md) - Documentation writing guidelines
- Ansible playbook standards
- Testing strategies

### 📝 [decisions/](decisions/)
**Architecture Decision Records (ADRs)** - Historical context for design choices

- Major architectural decisions
- Technology choices
- Migration rationale

### 📦 [archive/](archive/)
**Historical Reference** - Legacy documentation for context

## Relationship to Other Documentation

### thinkube-documentation (This Repo)
**Audience**: Developers, operators, contributors
**Purpose**: Technical specs, architecture, development standards

### [thinkube.org](https://github.com/thinkube/thinkube.org)
**Audience**: End users, new users
**Purpose**: Getting started guides, tutorials, user documentation

### Component READMEs
**Location**: `thinkube/ansible/40_thinkube/core/{component}/README.md`
**Audience**: Someone deploying/maintaining that specific component
**Purpose**: Component-specific deployment and configuration

## Quick Navigation

**Looking for...**
- How to deploy a component? → See component README in [thinkube repo](https://github.com/thinkube/thinkube)
- Platform architecture? → See [architecture/](architecture/)
- Specification details? → See [specs/](specs/)
- Development standards? → See [development/](development/)
- User guides? → See [thinkube.org](https://github.com/thinkube/thinkube.org)

## Contributing

When adding documentation:
1. Follow the [documentation standards](development/documentation-standards.md)
2. Use D2 for diagrams (sources in `architecture/diagrams/`)
3. Keep specifications versioned
4. Update cross-references when moving content

## Documentation Principles

1. **Co-location**: Component-specific docs live with the component code
2. **Single Source of Truth**: Avoid duplicating content across repos
3. **Audience-Based**: Organize by who needs the information
4. **Versioned Specs**: Specifications are versioned and immutable
5. **Living Documentation**: Architecture and operational docs evolve with the platform
