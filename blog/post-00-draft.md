# Blog Post 0 — Draft (Living Document)
# We Built an Enterprise AI Platform for Free

**Status:** In progress — updated after each session
**Target publish:** After Ollama milestone

---

## The Story

Every company building AI faces the same operational nightmare: models drift, pipelines fail
silently, inference latency spikes, agents hallucinate. Nobody has a clean open-source answer
to operating AI systems at scale.

We built one. On a Mac Mini M4. For free.

SAGE — Self-hosted Autonomous General-purpose Enterprise — is an autonomous AI operations
platform that monitors, diagnoses, and fixes AI/ML systems without human intervention.
Built entirely on open source, running on consumer hardware.

---

## The Hardware

One machine does it all:
- **Mac Mini M4** — 48GB unified memory, fanless, silent, 6-12W idle
- That's it. No cloud. No rack. No budget.

48GB unified memory is the key. It runs a 32B parameter LLM and all platform services
simultaneously without breaking a sweat.

---

## What We've Built So Far

### Session 1 — Foundation
- Installed Docker 29.4.2 on macOS Tahoe
- Created GitHub repo: github.com/ivaturia/sage-homelab (public, MIT)
- Scaffolded monorepo: 8 directories, clean structure
- Recorded ADR-001: single node deployment decision
- Key learning: Rosetta 2 needed for Docker on Apple Silicon — one command to fix

### Session 2 — Observability
- Deployed Portainer — visual Docker management at http://localhost:9000
- Deployed Prometheus — metrics collection, 15s scrape interval
- Deployed Grafana — dashboards connected to Prometheus
- Deployed cAdvisor — per-container CPU and memory metrics
- Created sage-network — shared Docker network for all services
- Key learning: cAdvisor on Mac uses `id` not `name` to label containers

---

## What's Coming Next

- Loki + Promtail — centralised log aggregation
- Redpanda — Kafka-compatible event bus
- Ollama — local LLM serving (this is the wow moment)
- Full agent system — watching, reasoning, acting

---

## Why This Matters

The same tools enterprises pay millions for, running free on one Mac Mini.
Anyone can clone this repo and run it.

---

*Last updated: 2026-05-08*
