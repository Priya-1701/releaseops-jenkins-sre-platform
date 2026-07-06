# Reliability Gates

ReleaseOps uses reliability gates to decide whether a release is safe to continue.

## Metrics Checked

- Application availability
- HTTP error rate
- p95 latency
- Pod restart count
- Kubernetes rollout status
- Canary health

## Example Gate Rules

Availability must be healthy
Error rate must stay below threshold
p95 latency must stay below threshold
Pod restarts must stay below threshold
Canary analysis must pass
