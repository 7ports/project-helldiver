# Onboarding Guide

## Prerequisites

1. A running Sauron instance (see [project-sauron](https://github.com/7ports/project-sauron))
2. A bearer token for the client project: `openssl rand -base64 32`
3. GitHub access to the target project repo
4. Docker installed and running

## Running Helldiver

1. Clone this repo
2. Copy `.env.example` to `.env` and fill in values
3. Run the scrum-master: `./scripts/voltron-run.sh`
4. The scrum-master will invoke all 7 agents in sequence

## What Gets Created

**In project-sauron:**
- `monitoring/prometheus/rules/<client-name>.yml`
- `monitoring/grafana/dashboards/<client-name>.json`
- `docs/clients/<client-name>.md`

**Delivered to the target project:**
- `config.alloy`
- `docker-compose.monitoring.yml`
- `.env.monitoring.example`
- `ONBOARDING.md`
