# Docs

The design of DocBridge, from DocBridge PAS-002, split by purpose. Keep it current as the code
changes: a decision that changes goes in a new ADR, and progress goes in `milestones.md`.

```
docs/
├── requirements.md     functional and non-functional requirements, scope, success metrics
├── blueprint.md        the problem and why, job stories, user flows with sequence diagrams
├── architecture/       system design, technical design, database schema, API, reliability and testing
├── adr/                decision records (ADR-001 to ADR-009 from the PAS, 010 onwards since)
└── milestones.md       the implementation plan: status, checklists, decisions, divergences
```

Diagrams are Mermaid where possible, so they can be reviewed in diffs; the PAS originals are in
`architecture/diagrams/`.
