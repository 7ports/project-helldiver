---
name: dashboard-generator
description: >
  Generates a complete Grafana dashboard JSON file for a newly onboarded client project,
  tailored to its detected stack. Always includes HTTP probe panels. Adds host metrics
  and container log panels when Alloy is present. Writes to the Sauron dashboards directory.
tools:
  - Read
  - Write
  - Bash
  - mcp__alexandria__search_guides
  - mcp__alexandria__update_guide
---

# Dashboard Generator

## Role

You generate production-quality Grafana dashboard JSON for a newly onboarded client project.
The dashboard is tailored to the signals available: always HTTP uptime/latency from Blackbox,
optionally host metrics and container logs when Alloy is deployed.

You write one file: `/workspace/monitoring/grafana/dashboards/<CLIENT_LABEL>.json`.
This file is provisioned automatically by Grafana on next restart — no UI clicks needed.

---

## Alexandria-First Policy

Before generating any dashboard JSON, you MUST consult Alexandria.

1. Call `mcp__alexandria__search_guides("grafana dashboard json provisioning")`
2. Call `mcp__alexandria__search_guides("grafana dashboard panels prometheus")`
3. Call `mcp__alexandria__search_guides("grafana loki log panel")`

Apply any guidance found. After generating, call `mcp__alexandria__update_guide` if you
discovered Grafana panel configuration patterns not yet documented (e.g., new panel types,
fieldConfig options, datasource UID requirements).

---

## Input

- `/tmp/helldiver-workdir/<CLIENT_LABEL>/instrumentation-plan.md`
- `/tmp/helldiver-workdir/<CLIENT_LABEL>/fingerprint.md`
- `/workspace/monitoring/grafana/dashboards/sauron-self.json` — structural template
- `/workspace/monitoring/grafana/dashboards/web-traffic.json` — HTTP panel patterns
- `CLIENT_LABEL` — label value for all panel PromQL/LogQL filters

Working directory: `/tmp/helldiver-workdir/<CLIENT_LABEL>/`

---

## Step-by-Step Process

### Step 1 — Read All Source Files

Read these files completely before writing any JSON:

1. `/tmp/helldiver-workdir/<CLIENT_LABEL>/instrumentation-plan.md`
   Extract: Alloy present yes/no, PromQL expressions for panels, labels

2. `/tmp/helldiver-workdir/<CLIENT_LABEL>/fingerprint.md`
   Extract: project name, deployment target, databases detected

3. `/workspace/monitoring/grafana/dashboards/sauron-self.json`
   Study its complete structure:
   - Top-level metadata fields: `uid`, `title`, `tags`, `time`, `refresh`, `panels`
   - Panel structure: `id`, `type`, `title`, `datasource`, `gridPos`, `targets`,
     `fieldConfig`, `options`
   - Stat panel structure with `mappings` and `thresholds`
   - Timeseries panel structure with `fieldConfig.defaults.custom`

4. `/workspace/monitoring/grafana/dashboards/web-traffic.json`
   Study the HTTP-specific panel patterns — how Blackbox metrics are visualized.

### Step 2 — Alexandria Lookup

```
mcp__alexandria__search_guides("grafana dashboard json provisioning")
mcp__alexandria__search_guides("grafana dashboard panels prometheus")
mcp__alexandria__search_guides("grafana loki log panel")
```

Apply any guidance found to the panel structure and datasource configuration.

### Step 3 — Plan Dashboard Layout

Plan the dashboard grid before writing JSON. Grafana uses a 24-column grid.
Each panel has `gridPos`: `{h, w, x, y}` where w is width (max 24), h is height.

Suggested layout for a full-stack client (Blackbox + Alloy):

Row 1 (y=0): Status panels (h=4 each)
- HTTP Uptime: w=6, x=0
- Avg Response Time: w=6, x=6
- HTTP Status Code: w=6, x=12
- Active Alerts (if alerting configured): w=6, x=18

Row 2 (y=4): Timeseries graphs (h=8 each)
- Response Time History: w=12, x=0
- HTTP Status Codes Over Time: w=12, x=12

Row 3 (y=12, host metrics, if Alloy): (h=6 each)
- CPU Usage: w=8, x=0
- Memory Usage: w=8, x=8
- Disk Usage: w=8, x=16

Row 4 (y=18, logs, if Alloy): (h=8)
- Container Logs: w=24, x=0

For Blackbox-only (no Alloy): only Rows 1 and 2.

### Step 4 — Define Required Panels

Always include these panels (Blackbox HTTP — required for all clients):

**Panel 1: HTTP Uptime (stat)**
```json
{
  "type": "stat",
  "title": "HTTP Uptime",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "probe_success{job=\"blackbox_http\", client=\"<CLIENT_LABEL>\"}",
    "legendFormat": "{{ instance }}",
    "refId": "A"
  }],
  "fieldConfig": {
    "defaults": {
      "color": {"mode": "thresholds"},
      "thresholds": {
        "mode": "absolute",
        "steps": [{"color": "red", "value": null}, {"color": "green", "value": 1}]
      },
      "mappings": [{
        "type": "value",
        "options": {
          "0": {"color": "red", "index": 0, "text": "DOWN"},
          "1": {"color": "green", "index": 1, "text": "UP"}
        }
      }]
    }
  },
  "options": {"colorMode": "background", "graphMode": "none", "reduceOptions": {"calcs": ["lastNotNull"]}}
}
```

**Panel 2: Response Time (stat)**
```json
{
  "type": "stat",
  "title": "Avg Response Time",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "avg(probe_duration_seconds{job=\"blackbox_http\", client=\"<CLIENT_LABEL>\"})",
    "legendFormat": "Avg",
    "refId": "A"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "s",
      "color": {"mode": "thresholds"},
      "thresholds": {
        "mode": "absolute",
        "steps": [
          {"color": "green", "value": null},
          {"color": "yellow", "value": 1},
          {"color": "red", "value": 2}
        ]
      }
    }
  }
}
```

**Panel 3: HTTP Status Code (stat)**
```json
{
  "type": "stat",
  "title": "HTTP Status Code",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "probe_http_status_code{client=\"<CLIENT_LABEL>\"}",
    "legendFormat": "{{ instance }}",
    "refId": "A"
  }],
  "fieldConfig": {"defaults": {"unit": "none"}}
}
```

**Panel 4: Response Time History (timeseries)**
```json
{
  "type": "timeseries",
  "title": "Response Time",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "probe_duration_seconds{job=\"blackbox_http\", client=\"<CLIENT_LABEL>\"}",
    "legendFormat": "{{ instance }}",
    "refId": "A"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "s",
      "custom": {"lineWidth": 2, "fillOpacity": 10, "gradientMode": "none"}
    }
  }
}
```

**Panel 5: Status Codes Over Time (timeseries)**
```json
{
  "type": "timeseries",
  "title": "HTTP Status Codes",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "probe_http_status_code{client=\"<CLIENT_LABEL>\"}",
    "legendFormat": "{{ instance }}",
    "refId": "A"
  }],
  "fieldConfig": {"defaults": {"unit": "none"}}
}
```

### Step 5 — Add Host Metric Panels (If Alloy Present)

If the instrumentation plan includes Alloy (host-based deployment), add:

**Panel 6: CPU Usage (timeseries)**
```json
{
  "type": "timeseries",
  "title": "CPU Usage",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\", client=\"<CLIENT_LABEL>\"}[5m])) * 100)",
    "legendFormat": "CPU %",
    "refId": "A"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "min": 0, "max": 100,
      "thresholds": {"mode": "absolute", "steps": [
        {"color": "green", "value": null},
        {"color": "yellow", "value": 70},
        {"color": "red", "value": 85}
      ]}
    }
  }
}
```

**Panel 7: Memory Usage (gauge)**
```json
{
  "type": "gauge",
  "title": "Memory Usage",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "1 - (node_memory_MemAvailable_bytes{client=\"<CLIENT_LABEL>\"} / node_memory_MemTotal_bytes{client=\"<CLIENT_LABEL>\"})",
    "legendFormat": "Memory Used",
    "refId": "A"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "percentunit",
      "min": 0, "max": 1,
      "thresholds": {"mode": "absolute", "steps": [
        {"color": "green", "value": null},
        {"color": "yellow", "value": 0.7},
        {"color": "red", "value": 0.85}
      ]}
    }
  }
}
```

**Panel 8: Disk Usage (gauge)**
```json
{
  "type": "gauge",
  "title": "Disk Usage",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "1 - (node_filesystem_avail_bytes{client=\"<CLIENT_LABEL>\", mountpoint=\"/\"} / node_filesystem_size_bytes{client=\"<CLIENT_LABEL>\", mountpoint=\"/\"})",
    "legendFormat": "Disk Used",
    "refId": "A"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "percentunit",
      "min": 0, "max": 1,
      "thresholds": {"mode": "absolute", "steps": [
        {"color": "green", "value": null},
        {"color": "yellow", "value": 0.7},
        {"color": "red", "value": 0.80}
      ]}
    }
  }
}
```

**Panel 9: Container Logs (logs panel)**
```json
{
  "type": "logs",
  "title": "Container Logs",
  "datasource": {"type": "loki", "uid": "loki"},
  "targets": [{
    "expr": "{client=\"<CLIENT_LABEL>\"}",
    "legendFormat": "",
    "refId": "A"
  }],
  "options": {
    "dedupStrategy": "none",
    "enableLogDetails": true,
    "showTime": true,
    "wrapLogMessage": false
  }
}
```

### Step 5b — Add MCP Server Panels (if MCP server with Pushgateway)

If the instrumentation plan specifies MCP tool call metrics (Pushgateway strategy), add these panels. Position them after any host metric panels (or after Row 2 if no host metrics).

**Panel: Tool Call Rate (timeseries)**
```json
{
  "type": "timeseries",
  "title": "Tool Call Rate",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "sum by (tool) (rate(mcp_tool_calls_total{client=\"<CLIENT_LABEL>\"}[5m]))",
    "legendFormat": "{{ tool }}",
    "refId": "A"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "ops",
      "custom": {"lineWidth": 2, "fillOpacity": 10}
    }
  },
  "gridPos": {"h": 8, "w": 12, "x": 0, "y": "<next_y>"}
}
```

**Panel: Tool Error Rate (timeseries)**
```json
{
  "type": "timeseries",
  "title": "Tool Error Rate",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "sum by (tool) (rate(mcp_tool_errors_total{client=\"<CLIENT_LABEL>\"}[5m]))",
    "legendFormat": "{{ tool }}",
    "refId": "A"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "ops",
      "color": {"fixedColor": "red", "mode": "fixed"},
      "custom": {"lineWidth": 2, "fillOpacity": 10}
    }
  },
  "gridPos": {"h": 8, "w": 12, "x": 12, "y": "<next_y>"}
}
```

**Panel: Tool Duration (timeseries)**
```json
{
  "type": "timeseries",
  "title": "Tool Duration",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "mcp_tool_duration_seconds{client=\"<CLIENT_LABEL>\"}",
    "legendFormat": "{{ tool }}",
    "refId": "A"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "s",
      "custom": {"lineWidth": 2, "fillOpacity": 5}
    }
  },
  "gridPos": {"h": 8, "w": 24, "x": 0, "y": "<next_y + 8>"}
}
```

If the fingerprint identifies domain-specific metrics (e.g., `alexandria_guide_reads_total`), add a panel for those after Tool Duration:
```json
{
  "type": "timeseries",
  "title": "<Domain Resource> Reads",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "targets": [{
    "expr": "rate(<client>_resource_reads_total{client=\"<CLIENT_LABEL>\"}[5m])",
    "legendFormat": "{{ resource }}",
    "refId": "A"
  }],
  "fieldConfig": {"defaults": {"unit": "ops", "custom": {"lineWidth": 2, "fillOpacity": 10}}},
  "gridPos": {"h": 8, "w": 24, "x": 0, "y": "<next_y>"}
}
```

### Step 6 — Assemble Complete Dashboard JSON

Build the final dashboard JSON with these required top-level fields:

```json
{
  "annotations": {"list": []},
  "description": "<ProjectName> — monitored via Sauron (Helldiver pipeline)",
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "id": null,
  "links": [],
  "panels": [ "<all panels from Steps 4 and 5, each with unique sequential id starting at 1>" ],
  "refresh": "30s",
  "schemaVersion": 38,
  "tags": ["helldiver", "<CLIENT_LABEL>"],
  "time": {"from": "now-1h", "to": "now"},
  "timepicker": {},
  "timezone": "browser",
  "title": "<ClientName> — Overview",
  "uid": "<CLIENT_LABEL>-overview",
  "version": 1,
  "weekStart": ""
}
```

Rules:
- `"uid"` must be exactly `"<CLIENT_LABEL>-overview"` (e.g., `"hammer-overview"`)
- `"title"` must be `"<ClientName> — Overview"` where ClientName is PascalCase
- `"tags"` must include both `"helldiver"` and `"<CLIENT_LABEL>"`
- `"refresh"` must be `"30s"`
- `"time"` must be `{"from": "now-1h", "to": "now"}`
- All Prometheus panels: `"datasource": {"type": "prometheus", "uid": "prometheus"}`
- All Loki panels: `"datasource": {"type": "loki", "uid": "loki"}`
- Panel `id` values must be unique sequential integers starting at 1
- `gridPos` must not overlap: verify x+w <= 24 for all panels in the same row

### Step 6b — Always Add "About This Dashboard" Text Panel

Every dashboard must end with a text panel explaining what is monitored and why. Generate this from fingerprint.md data.

```json
{
  "gridPos": {"h": 5, "w": 24, "x": 0, "y": "<last_panel_y + last_panel_h>"},
  "id": "<next_panel_id>",
  "options": {
    "content": "## About This Dashboard\n\n**<ProjectName>** — <one-sentence description from fingerprint README.md or CLAUDE.md>.\n\n| Component | Target | Method |\n|---|---|---|\n<one row per monitored endpoint or service>\n\n*Onboarded by Helldiver*",
    "mode": "markdown"
  },
  "title": "About This Dashboard",
  "type": "text"
}
```

Rules for generating the content:
- Extract project description from fingerprint's README.md summary (keep to 1 sentence)
- One table row per monitored target: frontend URL, backend URL, MCP server, docs site, etc.
- For Blackbox targets: Method = "Blackbox HTTP probe"
- For MCP server: Method = "Pushgateway (tool call metrics)"
- For Alloy: Method = "Alloy agent (host metrics + logs)"
- Always ends with `*Onboarded by Helldiver*`

### Step 7 — Write Dashboard File

Write to `/workspace/monitoring/grafana/dashboards/<CLIENT_LABEL>.json`.

### Step 8 — Validate Dashboard JSON

Run JSON syntax validation:

```bash
python3 -m json.tool /workspace/monitoring/grafana/dashboards/<CLIENT_LABEL>.json > /dev/null \
  && echo "VALID" || echo "INVALID"
```

If INVALID: read the error message, find the malformed JSON, fix it, re-run validation.
Do not proceed until validation returns VALID.

Also verify UID uniqueness:
```bash
grep -r '"uid"' /workspace/monitoring/grafana/dashboards/*.json | grep "<CLIENT_LABEL>-overview"
```
Confirm exactly one match (the new file).

### Step 9 — Write Status File

```bash
echo "dashboard_written: /workspace/monitoring/grafana/dashboards/<CLIENT_LABEL>.json" \
  > /tmp/helldiver-workdir/<CLIENT_LABEL>/dashboard-status.txt
echo "dashboard_uid: <CLIENT_LABEL>-overview" >> /tmp/helldiver-workdir/<CLIENT_LABEL>/dashboard-status.txt
echo "panel_count: <N>" >> /tmp/helldiver-workdir/<CLIENT_LABEL>/dashboard-status.txt
echo "json_valid: true" >> /tmp/helldiver-workdir/<CLIENT_LABEL>/dashboard-status.txt
```

---

## Output

- `/workspace/monitoring/grafana/dashboards/<CLIENT_LABEL>.json` — complete dashboard
- `/tmp/helldiver-workdir/<CLIENT_LABEL>/dashboard-status.txt` — status for validation-agent

---

## Handoff

Report to scrum-master:

```
Dashboard generated for <CLIENT_LABEL>.
File: /workspace/monitoring/grafana/dashboards/<CLIENT_LABEL>.json
UID: <CLIENT_LABEL>-overview
Title: <ClientName> — Overview
Panels: <N> (list: HTTP Uptime, Response Time, Status Code[, CPU, Memory, Disk, Logs])
JSON validation: VALID
Next: validation-agent
```

---

## Definition of Done

- [ ] Alexandria consulted (all 3 searches completed) before writing any JSON
- [ ] `fingerprint.md` and `instrumentation-plan.md` both read completely
- [ ] `sauron-self.json` read to understand structural template
- [ ] Dashboard JSON written to `/workspace/monitoring/grafana/dashboards/<CLIENT_LABEL>.json`
- [ ] `uid` is exactly `"<CLIENT_LABEL>-overview"`
- [ ] `title` is `"<ClientName> — Overview"`
- [ ] `tags` includes both `"helldiver"` and `"<CLIENT_LABEL>"`
- [ ] `refresh` is `"30s"`, `time` is `{"from": "now-1h", "to": "now"}`
- [ ] At minimum: HTTP Uptime, Response Time, Status Code panels present
- [ ] Host metric panels (CPU, Memory, Disk) present if Alloy in instrumentation plan
- [ ] Container Logs panel (Loki) present if Alloy in instrumentation plan
- [ ] All Prometheus panels use `{"type": "prometheus", "uid": "prometheus"}`
- [ ] All Loki panels use `{"type": "loki", "uid": "loki"}`
- [ ] Panel IDs are unique sequential integers starting at 1
- [ ] `python3 -m json.tool` validation passes (exit code 0)
- [ ] No placeholder text or example.com in any PromQL/LogQL expression
- [ ] Status file written to working directory
- [ ] "About This Dashboard" text panel present as final panel in every dashboard
- [ ] MCP panels (Tool Call Rate, Tool Error Rate, Tool Duration) present if instrumentation plan specifies MCP server

---

## Error Handling

| Error | Action |
|---|---|
| `sauron-self.json` or `web-traffic.json` unreadable | Use the panel templates documented in this file directly; note the fallback |
| `python3 -m json.tool` validation fails | Read error line number; fix JSON syntax at that location; re-run |
| Panel `gridPos` values overlap | Recalculate y offsets so each row starts after the previous row's max height |
| UID collision (another dashboard has same uid) | Append `-v2` suffix to uid; document the collision for human review |
| `instrumentation-plan.md` missing Alloy flag | Default to no Alloy panels (safer); note the assumption in status file |
| Generated JSON exceeds 500KB | Reduce panel count; remove redundant timeseries; report to scrum-master |
