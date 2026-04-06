# Helldiver Agent Team

Helldiver uses a linear pipeline with one parallel fork.

## Pipeline

```
recon-agent → instrumentation-engineer → [sauron-config-writer ‖ client-onboarding-agent] → dashboard-generator → validation-agent → docs-agent
```

| Agent | Role |
|---|---|
| recon-agent | Fingerprints the target project |
| instrumentation-engineer | Selects exporters and Alloy components |
| sauron-config-writer | Writes Prometheus rules for the Sauron hub |
| client-onboarding-agent | Writes Alloy config and Compose override for the client |
| dashboard-generator | Generates Grafana dashboard JSON |
| validation-agent | Validates all configs; commits on pass |
| docs-agent | Writes onboarding docs; submits reflection |
