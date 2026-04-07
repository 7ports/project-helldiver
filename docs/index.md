# Project Helldiver

Project Helldiver is an AI-powered observability onboarding squad — a team of 7 specialized agents that analyzes any project and wires it into a [Sauron](https://7ports.github.io/project-sauron) observability hub.

## What Helldiver Does

Given a GitHub repository, Helldiver:
1. Fingerprints the stack (language, framework, databases, deployment target)
2. Selects the right exporters and Grafana Alloy configuration
3. Generates hub-side Prometheus rules and Grafana dashboards
4. Generates client-side Alloy config and Docker Compose override
5. Validates all configurations before committing
6. Writes onboarding documentation

## Flagship Demonstration

**[Parallel Deployment Showcase](parallel-deployment-showcase)** — Two Helldiver squadrons onboarded two real projects simultaneously on 2026-04-07, with zero human interventions after launch:

- **Squadron Alpha** onboarded project-hammer (React SPA on CloudFront + Fly.io API) using Blackbox HTTP probing with a 3-second cold-start threshold
- **Squadron Beta** onboarded project-alexandria (stdio MCP server with no HTTP surface) using a GitHub Pages docs-site proxy strategy

2 projects. 0 conflicts. ~10 minutes end-to-end. Read the full breakdown in the [Parallel Deployment Showcase](parallel-deployment-showcase).

## Quick Start

See [Onboarding Guide](onboarding-guide) to run Helldiver against a project.

## Agent Team

See [Agents](agents) for the full pipeline description.
