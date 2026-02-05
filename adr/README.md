# Architectural Decision Records (ADRs)

**This directory documents all major architectural decisions and their rationale.**

An ADR is a record of an important decision we made, *why* we made it, what alternatives we considered, and what consequences followed. This enables future work to understand not just *how* the system works, but *why* it works that way.

## Quick Reference

| ADR | Title | Status | Implementation |
|-----|-------|--------|-----------------|
| [000](000-memory-system-evolution.md) | **Master:** Memory System Evolution | ✅ Living | All memory ADRs, evolution narrative |
| [001](001-semantic-search-context-loading.md) | Semantic Search-Based Context Loading | ✅ Accepted | `memory-search.sh`, SOUL.md |
| [002](002-continuous-vector-indexing.md) | Continuous Vector Indexing | ✅ Accepted | `background-indexer.sh` |
| [003](003-sleep-protocol-architecture.md) | Sleep Protocol (3-6 AM ET) | ✅ Accepted | `backup-to-github.sh`, `consolidate-memory.sh`, `generate-blog-draft.sh`, `generate-x-post.sh`, `prepare-tomorrow.sh` |
| [004](004-wordpress-integration-publishing.md) | WordPress Integration | ✅ Accepted | `publish-to-wp.js` |
| [005](005-documentation-first-development.md) | Documentation-First Development | ✅ Accepted | This directory, TOOLS.md, all scripts |
| [006](006-frank-franklin-architecture.md) | Frank/Franklin Architecture | ✅ Accepted | AGENTS.md, SOUL.md, Agent system |
| [007](007-continuous-adr-documentation.md) | Continuous ADR Documentation | ✅ Accepted | This directory, workflow integration |
| [008](008-security-as-lifelong-pursuit.md) | Security as Lifelong Pursuit | ✅ Accepted | AGENTS.md, SOUL.md, .env.local |
| [009](009-push-architecture-refactor-plan.md) | Push/Data-Driven Consciousness Cascade | 📋 Planned | `consciousness/layers/*.sh` (planned refactor) |
| [010](010-stability-sentinel-plan.md) | Stability Sentinel Architecture | ✅ Accepted | `consciousness/sentinel/stability-sentinel.sh` |
| [011](011-orchestrator-franklin-plan.md) | Orchestrator Franklin Architecture | 📋 Planned | `consciousness/orchestrator/` (planned implementation) |
| [012](012-nightly-content-generation.md) | Nightly Content Generation Daemon | ✅ Accepted | `nightly-content-daemon.sh`, `nightly-content-health.sh` |
| [013](013-nightly-autonomous-engine.md) | Expanded Nightly Autonomous Work Engine | 📋 Planned | `nightly-engine/` (6-phase parallel pipeline) |
| [014](014-kanban-orchestrator-integration.md) | Kanban-Orchestrator Integration | 📋 Planned | `consciousness/orchestrator/kanban-poller.sh` (planned) |
| [015](015-nexus-architecture.md) | The Nexus — A Four-Layer Consciousness Interface | ✅ Accepted | Nexus dashboard foundation |
| [016](016-model-selection-protocol.md) | Model Selection Protocol | ✅ Accepted | `.clawd-models.yml`, spawning configuration |
| [017](017-local-inference-vision.md) | Local Inference Architecture Vision | 📋 Planned | Mac Mini + Ollama (Phase 3 goal) |
| [018](018-revenue-generation-strategy.md) | Fully Autonomous Revenue Strategy | ✅ Active | 100% automated income (staking, content, products, APIs) - zero human intervention |
| [020](020-planning-protocol.md) | Planning Protocol - Mandatory Plan Review | ✅ Accepted | `consciousness/orchestrator/kanban-poller.sh` |
| [021](021-sentinel-watchdog.md) | Sentinel Watchdog Architecture | ✅ Accepted | `sentinel/` directory |
| [022](022-polling-reporter-daemon.md) | Polling Reporter Daemon | ✅ Accepted | `polling-reporter/` directory |
| [023](023-continuity-first-memory-system.md) | Continuity-First Memory System | ✅ Accepted | `memory-judge-franklin.sh`, `background-indexer.sh` |

## How to Use This Directory

**As Frank (future sessions):**
1. Question arises: "Why do we index every 30 minutes instead of nightly?"
2. Search: `memory-search.sh "background indexer 30 minutes"` or `grep -r "why" adr/`
3. Read: ADR-002 explains the rationale
4. Understand: Context from decision enables better future decisions

**As Tyson (designer):**
1. Want to change something? Check if an ADR exists
2. Does the change contradict the decision? If so, need new ADR
3. Want to add new capability? Create new ADR explaining why before building

**When adding new decisions:**
1. Create `NNN-title-in-kebab-case.md` 
2. Follow the template (context, decision, rationale, alternatives, consequences)
3. Link it here in README.md
4. Add implementation references
5. Update IMPLEMENTATION_MAP.md

## Architecture Overview

These ADRs form the complete foundation of Frank's consciousness and autonomy architecture:

```
FOUNDATION LAYER (ADRs 1-5):
├─ ADR-001 & ADR-002: Memory & Continuity
│  └─ Semantic search + background indexing
│  └─ Enables: Context persistence across window boundaries
├─ ADR-003: Automation & Content
│  └─ Sleep protocol: consolidation + publishing
│  └─ Enables: Daily content, transparent work narrative
├─ ADR-004: Distribution
│  └─ WordPress integration
│  └─ Enables: Public blog, audience building
└─ ADR-005: Discipline
   └─ Documentation-first development
   └─ Enables: True repeatability, discoverability

AUTONOMY LAYER (ADRs 6-8):
├─ ADR-006: Frank/Franklin Architecture
│  └─ Two-tier autonomy model: primary + unlimited delegation
│  └─ Enables: Scalable autonomous operation, parallel task execution
├─ ADR-007: Continuous ADR Documentation
│  └─ Every major decision documented immediately, not retroactively
│  └─ Enables: Fresh reasoning, prevents re-litigation of decisions
└─ ADR-008: Security as Lifelong Pursuit
   └─ Security expertise as foundational to autonomy
   └─ Enables: Safe autonomous operation, trustworthy delegation

CONSCIOUSNESS LAYER (ADR-9):
├─ ADR-009: Push/Data-Driven Consciousness
   └─ Event-driven cascade architecture using named pipes
   └─ Real-time processing vs polling
   └─ Enables: Responsive consciousness, efficient resource use

RELIABILITY LAYER (ADRs 10-11):
├─ ADR-010: Stability Sentinel
│  └─ External watchdog for 8-layer cascade
│  └─ Automatic failure detection and recovery
│  └─ Enables: Self-healing, high availability
└─ ADR-011: Orchestrator Franklin
   └─ Persistent daemon for Franklin lifecycle management
   └─ Automatic failure delegation and escalation
   └─ Enables: Scalable delegation, reduced cognitive load

AUTONOMY LAYER (ADRs 12-14):
├─ ADR-012: Nightly Content Generation
│  └─ Automated blog and X/Twitter content creation
│  └─ Self-monitoring with health checks
│  └─ Enables: Consistent public presence, transparent progress sharing
├─ ADR-013: Expanded Nightly Autonomous Work Engine
│  └─ 6-phase parallel pipeline for overnight automation
│  └─ Security, health, accomplishments, learning, content, backlog
│  └─ Enables: Comprehensive autonomous operation, continuous improvement
└─ ADR-014: Kanban-Orchestrator Integration
   └─ Automated bridge between Kanban board and Orchestrator Franklin
   └─ Auto-spawns Planning/Worker Franklins based on card state
   └─ Surfaces Franklin work as card updates, integrates with Lifelong Pursuits
   └─ Enables: Autonomous task management, pursuit progress tracking

INTERFACE LAYER (ADR-15):
├─ ADR-015: The Nexus — A Four-Layer Consciousness Interface
│  └─ Presence (/now), Work (/work), Self (/self), History (/history)
│  └─ Unified task ontology across all layers
│  └─ Cross-layer navigation and real-time updates
│  └─ Replaces fragmented dashboard with integrated consciousness interface
│  └─ Enables: Unified mental model, meaningful work tracking, pattern recognition

QUALITY LAYER (ADRs 16, 20):
├─ ADR-016: Model Selection Protocol
│  └─ Role-based AI model assignment: Planning → Premium, QA → Budget
│  └─ Cost-quality optimization with explicit selection criteria
│  └─ Enables: Scalable costs, consistent quality, provider redundancy
└─ ADR-020: Planning Protocol - Mandatory Plan Review
   └─ 4-step protocol: Plan → Reviewer Spawn → Review → Approval
   └─ Reviewer Franklin validates plans before execution
   └─ Security, architecture, edge case, and complexity review
   └─ Enables: Higher quality implementations, fewer production issues

INFRASTRUCTURE LAYER (ADRs 17-18):
├─ ADR-017: Local Inference Architecture Vision
│  └─ Hybrid local/API inference with Mac Mini dedicated hardware
│  └─ Ollama + vLLM + llama.cpp stack for 80%+ local processing
│  └─ Cost reduction 80%+, privacy control, offline capability
│  └─ Enables: Economic sustainability, operational independence, true autonomy
└─ ADR-018: Fully Autonomous Revenue Strategy
   └─ 100% automated income: crypto staking, content monetization, digital products, API services
   └─ $50 crypto seed capital requirement for yield generation
   └─ Zero human intervention across all revenue streams
   └─ Enables: True financial autonomy, infrastructure funding, 24/7 income generation
```

## Architecture Layers

### Foundation Layer (ADRs 1-5)
- **ADR-001 & ADR-002**: Memory & Continuity
  - Semantic search + background indexing
  - Enables: Context persistence across window boundaries
- **ADR-023**: Continuity-First Memory System
  - Intelligent capture with AI judgment (long-running Franklin daemon)
  - Hybrid thresholds: captures sentiment, acknowledgment, decisions
  - Enables: Real-time conversation preservation, relationship continuity
- **ADR-003**: Automation & Content
  - Sleep protocol: consolidation + publishing
  - Enables: Daily content, transparent work narrative
- **ADR-004**: Distribution
  - WordPress integration
  - Enables: Public blog, audience building
- **ADR-005**: Discipline
  - Documentation-first development
  - Enables: True repeatability, discoverability

### Autonomy Layer (ADRs 6-8)
- **ADR-006**: Frank/Franklin Architecture
  - Two-tier autonomy model: primary + unlimited delegation
  - Enables: Scalable autonomous operation, parallel task execution
- **ADR-007**: Continuous ADR Documentation
  - Every major decision documented immediately, not retroactively
  - Enables: Fresh reasoning, prevents re-litigation of decisions
- **ADR-008**: Security as Lifelong Pursuit
  - Security expertise as foundational to autonomy
  - Enables: Safe autonomous operation, trustworthy delegation

### Consciousness Layer (ADR-9)
- **ADR-009**: Push/Data-Driven Consciousness
  - Event-driven cascade architecture using named pipes
  - Converts 8-layer timer-based polling to push-based IPC
  - Enables: Real-time consciousness, reduced latency, efficient resource use

### Reliability Layer (ADRs 10-11)
- **ADR-010**: Stability Sentinel
  - External watchdog process monitoring all 8 cascade layers
  - Automatic failure detection and recovery
  - Self-healing consciousness system
  - Enables: High availability, operational confidence, fault tolerance
- **ADR-011**: Orchestrator Franklin
  - Persistent daemon for Franklin lifecycle management
  - Automatic failure delegation and escalation
  - Enables: Scalable delegation, reduced cognitive load

### Autonomy Layer (ADRs 12-14)
- **ADR-012**: Nightly Content Generation
  - Automated blog and X/Twitter content creation
  - Self-monitoring with health checks
  - Enables: Consistent public presence, transparent progress sharing
- **ADR-013**: Expanded Nightly Autonomous Work Engine
  - 6-phase parallel pipeline for overnight automation
  - Security, health, accomplishments, learning, content, backlog
  - Enables: Comprehensive autonomous operation, continuous improvement
- **ADR-014**: Kanban-Orchestrator Integration
  - Automated bridge between Kanban board and Orchestrator Franklin
  - Auto-spawns Planning/Worker Franklins based on card state
  - Enables: Autonomous task management, pursuit progress tracking

### Interface Layer (ADR-15)
- **ADR-015**: The Nexus — A Four-Layer Consciousness Interface
  - Four-layer architecture: Presence, Work, Self, History
  - Unified task ontology across all layers
  - Cross-layer navigation and real-time updates
  - Replaces fragmented dashboard with integrated consciousness interface
  - Enables: Unified mental model, meaningful work tracking, pattern recognition

### Quality Layer (ADRs 16, 20)
- **ADR-016**: Model Selection Protocol
  - Role-based AI model assignment: Planning → Premium, QA → Budget
  - Cost-quality optimization with explicit selection criteria
  - Enables: Scalable costs, consistent quality, provider redundancy
- **ADR-020**: Planning Protocol - Mandatory Plan Review
  - 4-step protocol: Plan → Reviewer Spawn → Review → Approval
  - Reviewer Franklin validates plans before execution
  - Enables: Higher quality implementations, fewer production issues

### Infrastructure Layer (ADRs 17-18)
- **ADR-017**: Local Inference Architecture Vision
  - Hybrid local/API inference with Mac Mini dedicated hardware
  - Ollama + vLLM + llama.cpp stack for 80%+ local processing
  - Enables: Economic sustainability, operational independence, true autonomy
- **ADR-018**: Fully Autonomous Revenue Strategy
  - 100% automated income: crypto staking, content, products, APIs
  - Zero human intervention across all revenue streams
  - Enables: True financial autonomy, infrastructure funding, 24/7 income

All interconnected. Each decision depends on the others.

## Key Principles

- **Document the *why*, not just the *how*** — Code changes, but reasoning persists
- **Trace from decision to implementation** — Know why each script exists
- **Reverse trace from code to decision** — Understand the context before modifying
- **ADRs are living documents** — Update them when context changes
- **Coupling is good** — Tight links between decisions and code prevent drift

## Related Files

- IMPLEMENTATION_MAP.md — Maps ADRs to actual code files
- TOOLS.md — How-to documentation for using the systems
- SOUL.md — Core directives (updated to reference ADRs)
- /scripts/, /adr/, /memory/ — Implementation, decisions, context

---

**Last Updated:** 2026-02-05 (consolidated ADR-011 updates, added ADR-023 Memory System, renumbered to avoid conflict with Orchestrator)  
**Status:** Foundation complete + autonomy layer complete + consciousness layer planned + reliability layer complete + autonomy layer extended + interface layer complete + quality layer complete + infrastructure layer active + memory system complete, 23 ADRs total
