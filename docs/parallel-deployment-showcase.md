---
layout: default
title: Parallel Deployment Showcase
nav_order: 3
description: "Two Helldiver squadrons onboard two real projects simultaneously — a live demonstration of autonomous observability onboarding at scale."
---

# Parallel Deployment Showcase

Two Helldiver squadrons. Two real projects. Zero human interventions after launch.

This page documents the Phase 4 test run executed on 2026-04-07, in which two independent Helldiver instances ran simultaneously — Squadron Alpha targeting **project-hammer** (a full-stack Toronto Island Ferry Tracker) and Squadron Beta targeting **project-alexandria** (a Node.js MCP knowledge base server). Both squadrons completed their full pipelines autonomously, made independent architectural decisions appropriate to their targets, and merged their commits cleanly into the project-sauron repository.

---

## Overview

**Project Helldiver** is an AI-powered observability onboarding team composed of 7 specialized agents. Given any GitHub repository, Helldiver analyzes the project's stack, selects the correct monitoring strategy, generates Prometheus scrape configs and alert rules, creates Grafana dashboards, pushes configuration changes to the Sauron hub, and delivers onboarding documentation to the client repository — without any human involvement after the initial launch command.

A **squadron** is a single end-to-end execution of the full Helldiver pipeline:

```
recon → instrument → sauron-config → client-onboard → dashboard → validate → docs
```

Each squadron runs in its own Docker container, orchestrated by the scrum-master. Multiple squadrons can run in parallel, each targeting a different project. They share the same project-sauron repository as their destination, with merge conflicts resolved via rebase.

This showcase ran two squadrons simultaneously — one for project-hammer and one for project-alexandria — demonstrating that Helldiver scales horizontally and makes correct, context-appropriate decisions for radically different project types.

---

## Architecture: The Helldiver Pipeline

### Pipeline Diagram

```
                    ┌──────────────────────────────────┐
                    │         scrum-master              │
                    │  (orchestrates, launches Docker   │
                    │   containers, coordinates merge)  │
                    └──────────────┬───────────────────┘
                                   │
                    ┌──────────────▼───────────────────┐
                    │          recon-agent              │
                    │  Stack fingerprinting: language,  │
                    │  framework, deployment target,    │
                    │  HTTP surface discovery           │
                    └──────────────┬───────────────────┘
                                   │
                    ┌──────────────▼───────────────────┐
                    │   instrumentation-engineer        │
                    │  Selects monitoring strategy:     │
                    │  Alloy sidecar / Blackbox probe / │
                    │  CloudWatch / docs proxy          │
                    └──────────┬───────────────────────┘
                               │
               ┌───────────────┴────────────────┐
               │                                │
┌──────────────▼───────────┐    ┌───────────────▼──────────────┐
│   sauron-config-writer   │    │   client-onboarding-agent    │
│  Writes prometheus.yml   │    │  Writes ONBOARDING.md and    │
│  scrape targets, alert   │    │  any client-side config       │
│  rules to project-sauron │    │  to the client repository    │
└──────────────┬───────────┘    └───────────────┬──────────────┘
               │                                │
┌──────────────▼───────────┐                   │
│    dashboard-generator   │                   │
│  Creates Grafana JSON    │                   │
│  dashboard with panels   │                   │
│  appropriate to strategy │                   │
└──────────────┬───────────┘                   │
               │                               │
               └──────────────┬────────────────┘
                              │
               ┌──────────────▼───────────────────┐
               │        validation-agent           │
               │  Syntax-checks prometheus.yml,    │
               │  confirms scrape targets resolve, │
               │  verifies dashboard JSON          │
               └──────────────┬───────────────────┘
                              │
               ┌──────────────▼───────────────────┐
               │           docs-agent              │
               │  Updates project docs (this page),│
               │  CLAUDE.md active work section,   │
               │  client ONBOARDING.md final pass  │
               └──────────────────────────────────┘
```

### Agent Roles

| Agent | Role |
|---|---|
| **recon-agent** | Clones or fetches the target repository, fingerprints the stack (language, framework, deployment platform, presence of `/metrics` or `/health` endpoints, HTTP surface), and produces a structured recon report consumed by all downstream agents. |
| **instrumentation-engineer** | Reads the recon report and selects the appropriate monitoring strategy: Alloy sidecar for self-hosted apps with a persistent host, Blackbox HTTP probing for CDN/managed frontends and APIs, CloudWatch exporter for AWS-native services, or a docs-site proxy for stdio-only services with no HTTP surface. |
| **sauron-config-writer** | Writes hub-side configuration — edits `monitoring/prometheus/prometheus.yml` with new scrape targets and alert rules, and places dashboard JSON in `monitoring/grafana/dashboards/`. Commits directly to project-sauron. |
| **client-onboarding-agent** | Pushes `ONBOARDING.md` (and any client-side Alloy config, if applicable) to the target project's repository. Provides a self-contained runbook for the client project's maintainer. |
| **dashboard-generator** | Generates Grafana dashboard JSON panels appropriate to the chosen monitoring strategy: uptime panels for Blackbox targets, resource panels for host-exported metrics, or a mix plus a text panel for architectural context. |
| **validation-agent** | Validates prometheus.yml syntax (via `promtool check config` or live endpoint check), confirms scrape target URLs are reachable, and verifies Grafana dashboard JSON parses correctly. |
| **docs-agent** | Updates project-helldiver docs and CLAUDE.md to record what was onboarded, what strategy was used, and any platform-specific lessons learned. Ensures the knowledge loop closes. |

All agents are implemented as Claude Code subagents running in Docker containers, orchestrated by the scrum-master using the `run_agent_in_docker` MCP tool. Each container runs with `--dangerously-skip-permissions` for fully autonomous execution within its defined scope.

---

## The Parallel Deployment Timeline

Both squadrons launched simultaneously from separate Docker containers. The scrum-master coordinated their git operations to prevent merge conflicts.

```
T+0:00   Alpha container starts targeting project-hammer
         Beta container starts targeting project-alexandria

T+0:30   Alpha: recon-agent clones project-hammer, begins stack fingerprinting
         Beta:  recon-agent clones project-alexandria, begins stack fingerprinting

T+2:00   Alpha: No /metrics endpoint found. CloudFront CDN + Fly.io API detected.
                Blackbox HTTP probing strategy selected.
         Beta:  stdio MCP transport detected. No HTTP surface found.
                Docs-site proxy strategy selected (GitHub Pages).

T+3:00   Alpha: instrumentation-engineer finalizes thresholds —
                3s latency threshold selected (not 2s) to account for
                Fly.io auto_stop_machines cold start spikes.
         Beta:  instrumentation-engineer confirms GitHub Pages as only
                probeable endpoint; text panel planned for dashboard.

T+4:00   Alpha: sauron-config-writer edits prometheus.yml — 2 Blackbox targets added,
                3 alert rules written (FrontendDown, BackendDown, HighLatency).
         Beta:  sauron-config-writer edits prometheus.yml — 1 Blackbox target added,
                2 alert rules written (AlexandriaDocsDown, AlexandriaDocsHighLatency).

T+5:00   Alpha: client-onboarding-agent pushes ONBOARDING.md to project-hammer repo.
         Beta:  client-onboarding-agent pushes ONBOARDING.md to project-alexandria repo.

T+6:00   Alpha: dashboard-generator creates 4-panel Grafana dashboard
                (frontend uptime, backend uptime, response time, status codes).
         Beta:  dashboard-generator creates 5-panel Grafana dashboard
                (uptime, response time, status code, response time history,
                 architecture explanation text panel).

T+7:00   Alpha: validation-agent checks prometheus.yml syntax, confirms both
                target URLs return 200 OK.
         Beta:  validation-agent checks prometheus.yml syntax, confirms GitHub
                Pages URL returns 200 OK.

T+8:00   Alpha: docs-agent finalizes ONBOARDING.md, records lessons in CLAUDE.md.
         Beta:  docs-agent finalizes ONBOARDING.md, records stdio proxy pattern.

T+9:00   Alpha: commits pushed to project-sauron main branch.

T+10:00  Beta:  rebased onto Alpha's commits. Commits pushed cleanly.
                No merge conflicts.

T+10:30  GitHub Actions CI/CD pipeline triggers on push to main.
         Auto-deploys updated Prometheus config and Grafana dashboards to EC2.
         Both projects are now live in Sauron.
```

---

## Squadron Alpha: Project Hammer (Toronto Island Ferry Tracker)

### What Was Discovered

**Recon report summary:**

- **Frontend:** React SPA hosted on CloudFront + S3, served at `https://ferries.yyz.live`
- **Backend API:** Node.js service deployed on Fly.io at `https://project-hammer-api.fly.dev`
- **No `/metrics` endpoint** on either service
- **No persistent host** available for deploying a sidecar agent
- **CloudFront** manages the frontend — no server-level instrumentation possible
- **Fly.io** manages the backend with `auto_stop_machines = true` — machines spin down when idle

This combination — CDN-fronted SPA plus serverless-style Fly.io API — means there is no viable path for installing Grafana Alloy or Prometheus exporters. The instrumentation-engineer correctly classified this as a **Blackbox-only** scenario.

### Monitoring Strategy: Blackbox HTTP Probing

Blackbox probing sends synthetic HTTP requests from the Sauron server to the target URLs on a regular interval, recording probe success, response time, and HTTP status code. It requires no changes to the target application and no persistent process on the client side.

This is the correct strategy for:
- CDN-fronted frontends (no server-level access)
- Managed API platforms with no persistent host (Fly.io, Railway, Render)
- Any externally-accessible HTTP endpoint

### Key Engineering Decision: 3-Second Latency Threshold

Standard Blackbox latency thresholds are typically 1–2 seconds. However, Fly.io's `auto_stop_machines = true` configuration puts idle machines to sleep. A cold start when the machine wakes can add 1–2 seconds of latency above normal. Applying a 2-second threshold would generate false-positive `HighLatency` alerts during normal cold-start behavior.

The instrumentation-engineer set the `HighLatency` alert threshold to **3 seconds** specifically to account for this, with a 5-minute sustained window to filter out transient spikes. This decision was recorded in the alert rule's annotations.

Similarly, `BackendDown` was given a 5-minute grace period (vs. 2 minutes for the frontend) because a cold-starting Fly.io machine may not respond for the first 30–60 seconds — this is normal behavior, not a true outage.

### What Was Delivered

**Prometheus configuration (added to `monitoring/prometheus/prometheus.yml`):**
- 2 Blackbox scrape targets: `ferries.yyz.live` (frontend) and `project-hammer-api.fly.dev` (backend)
- Scrape interval: 30s
- Module: `http_2xx` (probe succeeds on 2xx response)

**Alert rules (added to `monitoring/prometheus/rules/alerting.yml`):**

| Rule | Threshold | Rationale |
|------|-----------|-----------|
| FrontendDown | probe_success == 0 for 2m | CDN should always respond; 2m eliminates transient blips |
| BackendDown | probe_success == 0 for 5m | Allow Fly.io cold start grace period before alerting |
| HighLatency | probe_duration_seconds > 3 for 5m | Fly.io cold starts can spike to ~2s; 3s threshold prevents false positives |

**Grafana dashboard (`monitoring/grafana/dashboards/hammer-overview.json`):**

4 panels:
1. **Frontend Uptime** — stat panel, probe_success for `ferries.yyz.live`, green/red threshold
2. **Backend Uptime** — stat panel, probe_success for `project-hammer-api.fly.dev`, green/red threshold
3. **Response Time** — time series, probe_duration_seconds for both targets, 3s alert line overlay
4. **HTTP Status Codes** — time series, probe_http_status_code for both targets

**Client documentation:**
- `ONBOARDING.md` pushed to `github.com/7ports/project-hammer` repository
- Explains what Sauron monitors, how to view the dashboard, what the alerts mean, and how to request changes

---

## Squadron Beta: Project Alexandria (MCP Knowledge Base)

### What Was Discovered

**Recon report summary:**

- **Service type:** Node.js MCP (Model Context Protocol) server
- **Transport:** stdio — the server communicates via standard input/output, not over a network socket
- **HTTP surface:** None. The server does not bind to any port.
- **Only public endpoint:** GitHub Pages documentation site at `https://7ports.github.io/project-alexandria/`
- **Deployment model:** Run locally by MCP clients (Claude Code, etc.) — not a hosted service

This is the most challenging scenario for observability: a service with **zero HTTP surface**. There is no port to probe, no `/metrics` endpoint to scrape, no host to install an agent on. Traditional monitoring approaches do not apply.

### The Interesting Challenge

How do you monitor something with no HTTP surface?

Conventional observability requires at least one of:
- A TCP port to probe (Blackbox)
- A `/metrics` endpoint to scrape (Prometheus)
- Host-level access to run an exporter (node-exporter)
- A cloud provider API (CloudWatch)

Project Alexandria has none of these. The service is invoked on-demand by MCP clients via stdio. It has no persistent running process to monitor, no port to reach, and no infrastructure to query.

### The Solution: GitHub Pages Docs Site as Operational Health Proxy

The instrumentation-engineer identified one reachable signal: the GitHub Pages documentation site at `https://7ports.github.io/project-alexandria/`. This site is automatically built and deployed by GitHub Actions whenever code is pushed to the repository.

The reasoning:

1. If the docs site is **up and responding**, the GitHub repository is healthy, Actions pipelines are running, and the codebase is in a deployable state.
2. If the docs site **goes down or becomes unreachable**, something has gone wrong with the repository infrastructure — a failed pipeline, a suspended account, or repository deletion.
3. For an MCP server that is distributed and invoked locally, repository health is the best available proxy for service health.

This is not a perfect monitoring solution — it cannot detect bugs in the MCP tool implementations or failures that occur at runtime for individual users. The dashboard includes an explanatory text panel acknowledging this limitation explicitly.

### Dashboard: The Text Panel Approach

Because the monitoring strategy is non-standard, a 5th panel was added to the dashboard: a **text panel** that explains the architecture in plain language. This serves two purposes:
1. Anyone viewing the dashboard understands immediately why there are no resource metrics
2. The explanation is self-contained — no external documentation is required to interpret the dashboard

This pattern — including an explanatory text panel when the monitoring strategy is non-obvious — is now documented in the Alexandria knowledge base as a recommended practice for MCP and stdio-transport services.

### What Was Delivered

**Prometheus configuration (added to `monitoring/prometheus/prometheus.yml`):**
- 1 Blackbox scrape target: `7ports.github.io/project-alexandria/`
- Scrape interval: 60s (docs site, lower frequency acceptable)
- Module: `http_2xx`

**Alert rules (added to `monitoring/prometheus/rules/alerting.yml`):**

| Rule | Threshold | Rationale |
|------|-----------|-----------|
| AlexandriaDocsDown | probe_success == 0 for 5m | Docs site down signals repository infrastructure problem |
| AlexandriaDocsHighLatency | probe_duration_seconds > 2 for 5m | GitHub Pages is a CDN — sustained latency above 2s is abnormal |

**Grafana dashboard (`monitoring/grafana/dashboards/alexandria-overview.json`):**

5 panels:
1. **Docs Site Uptime** — stat panel, probe_success for GitHub Pages URL, green/red threshold
2. **Response Time** — stat panel, current probe_duration_seconds
3. **HTTP Status Code** — stat panel, probe_http_status_code
4. **Response Time History** — time series, probe_duration_seconds over 24h window
5. **Architecture Note** — text panel explaining the stdio transport, why HTTP probing is used against the docs site, and the limitations of this approach

**Client documentation:**
- `ONBOARDING.md` pushed to `github.com/7ports/project-alexandria` repository
- Explains the monitoring strategy, what the docs-site proxy means, how to view the dashboard, and what the alerts indicate

---

## Integration with Sauron

Both squadrons connect to the Sauron observability hub running at `https://sauron.7ports.ca`.

### Authentication

Sauron push endpoints use Bearer token authentication. Each onboarded project receives a unique `SAURON_PUSH_TOKEN` generated during the onboarding process. The Helldiver scrum-master provisions this token and records it in the project-sauron secrets configuration. Client-side tokens are included in `ONBOARDING.md` as a reference for the client project's maintainer.

### Deployment Flow

Changes to project-sauron (prometheus.yml, alert rules, Grafana dashboards) are deployed via the existing GitHub Actions CI/CD pipeline:

```
git push to project-sauron main
    │
    ▼
GitHub Actions: deploy.yml triggers
    │
    ▼
SSH to EC2 at 52.6.78.46
    │
    ▼
docker compose pull && docker compose up -d
    │
    ▼
Prometheus hot-reloads config (POST /-/reload)
Grafana picks up new dashboard JSON from provisioning volume
```

No manual steps on EC2 are required. Both squadrons' changes were merged to main and deployed in a single GitHub Actions run approximately 30 seconds after the final push.

### Zero Human Intervention

After launching the two Docker containers, no human action was taken until this documentation was reviewed. Specifically:

- No prometheus.yml edits by hand
- No Grafana dashboard imports by hand
- No SSH sessions to EC2
- No git commands executed by a human
- No conflict resolution — Beta rebased onto Alpha automatically

---

## Alexandria Knowledge Base Integration

Every Helldiver agent is required to consult the Alexandria knowledge base before configuring any infrastructure tool or cloud service. This is enforced in each agent's system prompt.

During the Phase 4 test run:

- Both squadrons called `mcp__alexandria__quick_setup` before configuring Blackbox Exporter targets
- The existing `prometheus-grafana-docker-compose` guide documented the correct Blackbox scrape config format, preventing configuration errors
- The GitHub Pages proxy pattern (using a docs site as a health signal for a non-HTTP service) was recorded as a new entry in the guide after Beta completed its onboarding

### Why This Matters

The Alexandria knowledge loop means each onboarding makes the next one faster and more reliable:

1. Beta's stdio-proxy pattern is now documented — future MCP server onboardings will find it immediately
2. Alpha's Fly.io cold-start threshold decision is documented — future Fly.io onboardings will apply 3s thresholds by default
3. No human needs to remember these decisions — they are encoded in a searchable knowledge base that all agents query automatically

As more projects are onboarded, the knowledge base accumulates platform-specific patterns, reducing the instrumentation-engineer's decision time and improving the consistency of alert thresholds across similar deployments.

---

## Results Summary

| | Squadron Alpha (Hammer) | Squadron Beta (Alexandria) |
|---|---|---|
| Project type | Full-stack web app | Node.js MCP server |
| Deployment | CloudFront + Fly.io | stdio (no HTTP surface) |
| Monitoring strategy | Blackbox HTTP probing | GitHub Pages docs-site proxy |
| Targets monitored | 2 (frontend + backend) | 1 (GitHub Pages) |
| Alert rules | 3 | 2 |
| Dashboard panels | 4 | 5 |
| Client-side agent required | No | No |
| Commits to project-sauron | 2 | 2 |
| Files pushed to client repo | ONBOARDING.md | ONBOARDING.md |
| Merge conflicts | — | None (rebased cleanly) |
| Human interventions | 0 | 0 |
| Total elapsed time | ~10 minutes | ~10 minutes |

---

## How to Run Helldiver on Your Project

### Prerequisites

1. project-helldiver cloned locally
2. Docker installed and running (Rancher Desktop or Docker Desktop)
3. `Dockerfile.voltron` present in the project root
4. Required environment variables set (see `.env.example`):
   - `SAURON_URL` — your Sauron instance URL
   - `SAURON_PUSH_TOKEN` — bearer token for push authentication
   - `GITHUB_TOKEN` — for reading target repo and pushing to project-sauron
   - `TARGET_REPO` — GitHub URL of the project to onboard

### Launch Command

The scrum-master coordinates the full pipeline. Invoke it with:

```bash
# From the project-helldiver root
claude --agent scrum-master \
  "Onboard TARGET_REPO=https://github.com/your-org/your-project into Sauron"
```

The scrum-master will:
1. Launch the recon-agent in a Docker container
2. Pass the recon report to the instrumentation-engineer
3. Coordinate parallel execution of sauron-config-writer and client-onboarding-agent
4. Launch the dashboard-generator
5. Run the validation-agent
6. Complete with the docs-agent updating project records

### Expected Outputs

After a successful run:

- `monitoring/prometheus/prometheus.yml` — updated with new scrape targets
- `monitoring/prometheus/rules/alerting.yml` — updated with new alert rules
- `monitoring/grafana/dashboards/<project>-overview.json` — new dashboard
- `github.com/your-org/your-project/ONBOARDING.md` — onboarding runbook
- `docs/parallel-deployment-showcase.md` — updated if this is a notable run

### Agent Documentation

| Agent | Documentation |
|---|---|
| scrum-master | [Agents](agents#scrum-master) |
| recon-agent | [Agents](agents#recon-agent) |
| instrumentation-engineer | [Agents](agents#instrumentation-engineer) |
| sauron-config-writer | [Agents](agents#sauron-config-writer) |
| client-onboarding-agent | [Agents](agents#client-onboarding-agent) |
| dashboard-generator | [Agents](agents#dashboard-generator) |
| validation-agent | [Agents](agents#validation-agent) |
| docs-agent | [Agents](agents#docs-agent) |

---

## Conclusion

The Phase 4 parallel deployment test demonstrated three things:

**1. Helldiver scales horizontally.** Two independent squadrons ran simultaneously in separate Docker containers, made independent decisions appropriate to their targets, and merged their work cleanly into the shared project-sauron repository without conflicts or human intervention.

**2. Autonomous decision-making works across radically different project types.** A CDN-fronted React SPA with a Fly.io API (Squadron Alpha) and a stdio-transport MCP server with no HTTP surface (Squadron Beta) require completely different monitoring strategies. Helldiver's instrumentation-engineer selected the correct strategy in each case — Blackbox probing for Alpha, docs-site proxy for Beta — and applied appropriate thresholds (3s for Fly.io cold starts, 2s for GitHub Pages CDN).

**3. The Alexandria knowledge loop compounds value over time.** Each onboarding produces new documented patterns — the Fly.io cold-start threshold, the stdio proxy approach — that future squadrons will find and apply automatically. Two projects onboarded today means future projects are onboarded faster and more consistently. The system improves with use.

**2 projects. 2 squadrons. 0 human interventions. ~10 minutes end-to-end.**

That is the Helldiver promise.
