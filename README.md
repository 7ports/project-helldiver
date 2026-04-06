# Project Helldiver

AI agent team for onboarding projects onto [Sauron](https://github.com/7ports/project-sauron) observability instances.

## What it does

Given a GitHub repository, Helldiver deploys a full observability setup: metrics, logs, dashboards, and alerts — without you writing a single config file.

## Documentation

https://7ports.github.io/project-helldiver

## Architecture

Helldiver runs 7 specialized AI agents in a pipeline:
1. **recon-agent** — fingerprints the target project
2. **instrumentation-engineer** — selects exporters and Alloy components
3. **sauron-config-writer** + **client-onboarding-agent** — generate hub and client configs (parallel)
4. **dashboard-generator** — creates Grafana dashboards
5. **validation-agent** — validates everything before committing
6. **docs-agent** — writes docs and submits reflection

## Requirements

- Docker
- A running [Sauron](https://github.com/7ports/project-sauron) instance
- GitHub CLI (`gh`) authenticated

## Inheritance

Helldiver inherits Voltron's agent orchestration infrastructure. See [CLAUDE.md](CLAUDE.md) for details.
