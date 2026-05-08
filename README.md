# SAGE — Self-hosted Autonomous General-purpose Enterprise

An open-source AI Operations Platform built entirely on consumer hardware.

## What is SAGE?

SAGE monitors, operates, and continuously improves AI/ML systems and the infrastructure they run on. It detects model drift, diagnoses root causes autonomously, proposes remediations, and routes them through human approval before acting.

**In one sentence:** SAGE is an autonomous AI operations team — watching, reasoning, acting, and explaining itself — built entirely on open source running on consumer hardware.

## Architecture

SAGE is built in three layers:

- **Layer 1 — Platform Foundation:** Identity, secrets, observability, event bus, databases
- **Layer 2 — AI/ML Plane:** Model serving, RAG pipelines, agent orchestration
- **Layer 3 — Agentic Application:** Multi-agent system with human-in-the-loop control

## Hardware

Built on a 6-node home lab anchored by a Mac Mini M4 with 48GB RAM.

## Repository Structure

sage-homelab/
├── docs/                    # Architecture diagrams, ADRs, design decisions
├── blog/                    # Blog post drafts
├── platform/                # Layer 1: platform foundation services
├── ai-plane/                # Layer 2: model serving, RAG, orchestration
├── agents/                  # Layer 3: all agents and supervisor
├── synthetic-data/          # NeuralOps-Core synthetic load generator
├── control-plane-ui/        # Next.js dashboard
└── scripts/                 # Health checks, teardown, reset utilities

## Status

🚧 Active build — follow along at [blog coming soon]

## License

MIT