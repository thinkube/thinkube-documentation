# Documentation Standards

Guidelines for writing and maintaining documentation in the Thinkube ecosystem.

## Documentation Principles

### 1. Co-location
**Documentation lives with what it documents**

- Component READMEs stay in `thinkube/ansible/40_thinkube/core/{component}/README.md`
- Architecture docs in `thinkube-documentation/architecture/`
- User guides in `thinkube.org`

### 2. Single Source of Truth
**Avoid duplicating content across repositories**

- Reference other docs via links, don't copy content
- If content needs to exist in multiple places, one is the source, others link to it

### 3. Audience-Based Organization
**Structure by who needs the information**

- **Developers/Operators**: thinkube-documentation
- **End Users**: thinkube.org
- **Component Maintainers**: Component READMEs

### 4. Actionable Documentation
**Every doc should enable someone to DO something**

Ask: "If someone reads this, will they be able to DO something they couldn't before?"

Good documentation answers:
- How do I deploy this?
- How do I configure this?
- How do I troubleshoot this?
- Why was this decision made?

### 5. Living Documentation
**Documentation evolves with the code**

- Update docs in the same commit as code changes
- Review docs during code review
- Mark outdated docs clearly or delete them

## Documentation Types

### 1. Orientation Documentation
**Purpose**: Help someone understand where they are and where to go

**Location**: Top-level READMEs, navigation docs
**Examples**:
- `thinkube-documentation/README.md`
- `thinkube/CLAUDE.md`
- `thinkube-platform/CLAUDE.md`

**Required Elements**:
- Purpose of the repository/directory
- Quick navigation to key documents
- Relationship to other documentation

### 2. Operational Documentation
**Purpose**: Enable someone to deploy, configure, or maintain a component

**Location**: Component READMEs, operations guides
**Examples**:
- `thinkube/ansible/40_thinkube/core/postgresql/README.md`
- `thinkube-documentation/operations/`

**Required Elements**:
- Prerequisites
- Step-by-step procedures
- Configuration options
- Testing/validation
- Troubleshooting

### 3. Reference Documentation
**Purpose**: Provide complete technical details

**Location**: Specifications, API docs
**Examples**:
- `thinkube-documentation/specs/thinkube-yaml-v1.0.md`
- API documentation

**Required Elements**:
- Complete parameter/option descriptions
- Examples
- Version information
- Constraints and limitations

### 4. Conceptual Documentation
**Purpose**: Explain how something works and why

**Location**: Architecture docs, design docs
**Examples**:
- `thinkube-documentation/architecture/deployment-dependency-graph.md`
- `thinkube-documentation/decisions/`

**Required Elements**:
- Problem being solved
- Solution approach
- Trade-offs and alternatives
- Diagrams (D2 preferred)

### 5. Contribution Documentation
**Purpose**: Enable someone to contribute effectively

**Location**: Developer guides, standards docs
**Examples**:
- `thinkube-documentation/development/component-readme-template.md`
- This document

**Required Elements**:
- Standards and conventions
- Templates
- Review process
- Examples of good work

## Writing Guidelines

### Style

**Be Concise**
- Get to the point quickly
- Use short sentences
- Break up long paragraphs

**Be Specific**
- Use concrete examples
- Provide exact commands
- Show expected output

**Be Consistent**
- Follow templates where they exist
- Use consistent terminology
- Match the style of existing docs in that category

### Structure

**Use Headings Effectively**
```markdown
# Top-level (title)
## Major sections
### Subsections
```

**Use Lists**
- For items in a sequence
- For options or alternatives
- For requirements or prerequisites

**Use Code Blocks with Language Tags**
```yaml
# Example YAML
key: value
```

```bash
# Example bash command
kubectl get pods
```

### Markdown Conventions

**Links**
- Use descriptive link text: [deployment guide](link), not [click here](link)
- Use relative links within same repo: `[README](../README.md)`
- Use absolute GitHub URLs for cross-repo: `[thinkube](https://github.com/thinkube/thinkube)`

**Emphasis**
- **Bold** for UI elements, important warnings, key terms
- *Italic* for emphasis in running text
- `Code font` for commands, file names, variables, code elements

**Admonitions**
Use bold markers for callouts:
- **Important**: Critical information
- **Warning**: Potential problems
- **Note**: Additional context
- **Tip**: Helpful suggestions

## Component README Standards

### Required Sections
Every component README MUST have:
1. Overview
2. Dependencies
3. Prerequisites
4. Playbooks
5. Deployment
6. Testing
7. Rollback

### Optional Sections (use when relevant)
- Configuration
- Accessing the Component
- Troubleshooting
- Integration
- Architecture Notes
- Platform-Specific Notes

### Template Usage
1. Copy [component-readme-template.md](component-readme-template.md)
2. Fill in all required sections
3. Add optional sections as needed
4. Remove sections that don't apply with a note explaining why
5. Keep examples and code blocks updated

## Diagram Standards

### Use D2 for Technical Diagrams

**Why D2?**
- Version controllable (text-based)
- Clean, professional output
- Good for technical/architecture diagrams

**D2 Files**
- Store in `architecture/diagrams/*.d2`
- Commit both `.d2` source and rendered output
- Include alt text when embedding

**Example**:
```d2
component A -> component B: depends on
component B -> component C: depends on
```

### When to Use Diagrams
- Component dependencies
- Architecture overview
- Data flow
- State machines
- Complex relationships

### When NOT to Use Diagrams
- Simple lists (use markdown lists)
- Linear sequences (use numbered lists)
- Single relationships (use text)

## Versioning

### Specifications
- Specifications are versioned (e.g., v1.0, v2.0)
- Include version in filename: `spec-name-v1.0.md`
- Old versions remain for reference
- Mark old versions with deprecation notice

### Other Documentation
- Not explicitly versioned
- Lives in `main` branch
- Updated as platform evolves
- Git history provides version trail

## Maintenance

### Updating Documentation

**When Code Changes**:
- Update related docs in same PR/commit
- Check for cross-references that need updating
- Update examples to match new behavior

**When Documentation Becomes Outdated**:
- Update it or delete it
- Don't leave outdated docs without clear warning
- Better to have no docs than wrong docs

**When Deprecating Features**:
- Mark docs with deprecation warning
- Provide migration path
- Remove after grace period

### Documentation Review

**In Code Reviews**:
- Verify docs updated with code changes
- Check for clarity and completeness
- Test commands and examples
- Verify links work

**Periodic Audits**:
- Review TODOs and placeholders
- Check for broken links
- Update outdated information
- Remove obsolete content

## Common Patterns

### Deployment Instructions
```markdown
## Deployment

```bash
cd ~/thinkube
export REQUIRED_VAR="value"
./scripts/run_ansible.sh ansible/path/to/playbook.yaml
```
```

### Configuration Examples
```markdown
## Configuration

From `inventory/group_vars/k8s.yml`:
```yaml
variable_name: value  # Clear description
```
```

### Troubleshooting Entries
```markdown
### Issue Name

**Symptoms**: What the user sees

**Root Cause**: Why it happens

**Solution**:
```bash
# Commands to fix
```
```

### Cross-References
```markdown
See [Component Name](../component/README.md) for deployment instructions.

For architecture details, see [Deployment Dependencies](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md).
```

## Quality Checklist

Before committing documentation:

- [ ] Follows appropriate template (if applicable)
- [ ] All code examples are tested and work
- [ ] Links are valid and point to correct locations
- [ ] Spelling and grammar are correct
- [ ] Appropriate audience level
- [ ] Answers the "so what?" question
- [ ] Enables reader to take action
- [ ] Consistent with existing documentation style
- [ ] Version information included (for specs)
- [ ] Cross-references updated (if moving content)

## Examples of Good Documentation

### Good Component README
See: `thinkube/ansible/40_thinkube/core/postgresql/README.md`
- Clear structure
- Complete deployment instructions
- Tested examples
- Troubleshooting section

### Good Architecture Doc
See: `thinkube/ansible/40_thinkube/core/infrastructure/k8s/README.md`
- Explains prerequisites clearly
- Includes migration guidance
- Platform-specific notes
- Comprehensive troubleshooting

### Good Specification
See: `thinkube-documentation/specs/thinkube-yaml-v1.0.md`
- Versioned
- Complete reference
- Examples throughout
- Clear constraints

## Documentation Anti-Patterns

### ❌ Don't Do This

**Orphaned TODOs**
```markdown
## TODO: Fill this in later
```
→ Either fill it in or remove it

**Vague Instructions**
```markdown
Deploy the component using the normal process.
```
→ Provide specific commands

**Outdated Examples**
```markdown
# Using the old API (deprecated in v2.0)
```
→ Update or remove

**Broken Links**
```markdown
See [the documentation](broken-link.md)
```
→ Verify links work

**Command Without Context**
```markdown
Run: `kubectl delete pod xyz`
```
→ Explain when and why to run it

### ✅ Do This Instead

**Clear, Actionable Content**
```markdown
## Deployment

1. Ensure prerequisites are met (see above)
2. Deploy with:
```bash
./scripts/run_ansible.sh ansible/path/to/playbook.yaml
```
3. Verify deployment:
```bash
kubectl get pods -n namespace
```
```

## Getting Help

- Questions about documentation standards: Create issue in thinkube-documentation
- Template improvements: Submit PR to thinkube-documentation
- Component-specific docs: Ask component maintainer

---

**Version**: 1.0
**Last Updated**: 2025-11-18
