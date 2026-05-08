# Architecture Decisions

## ADR-001: Single Node Deployment on Mac Mini M4

**Date:** 2026-05-08

**Decision:** SAGE runs entirely on a single Mac Mini M4 (48GB RAM).

**Reasoning:**
- 48GB unified memory is sufficient to run all platform services, AI models up to 32B parameters, and all agents simultaneously
- Simplifies networking, deployment, and reproducibility
- Makes the project accessible to anyone with a single powerful machine
- The Mac Mini M4 is purpose-built for sustained workloads — fanless, efficient, reliable

**What this means:**
- All Docker services run on 192.168.1.10
- Model serving (Ollama) runs on the same node
- No distributed networking complexity in Phase 1-3
- Worker nodes can be added later without architectural changes

**Trade-offs accepted:**
- No high availability — if the Mac Mini goes down, SAGE goes down
- This is a home lab, not a production system — acceptable
