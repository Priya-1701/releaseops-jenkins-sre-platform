# ReleaseOps — Production Release Operations Platform

ReleaseOps is a production-grade Jenkins SRE CI/CD platform that builds, tests, scans, deploys, validates, promotes, and rolls back Kubernetes releases using reliability signals.

This project is designed to demonstrate how modern SRE teams treat CI/CD pipelines as release safety systems, not just deployment automation.

## Core Idea

A normal CI/CD pipeline deploys code.

ReleaseOps decides whether the code is safe enough to reach production.

## Platform Capabilities

- Jenkins Pipeline as Code
- Docker image build and versioned tagging
- Container image vulnerability scanning
- Kubernetes dev, staging, and production environments
- Smoke testing after deployment
- Prometheus-based reliability gates
- Grafana release observability dashboards
- Production canary deployment
- Automated rollback
- Release audit reporting

## Application

The platform deploys an SRE-focused FastAPI workload called `incident-api`.

The app will expose:

- `/health`
- `/ready`
- `/metrics`
- `/incidents`
- `/simulate/error`
- `/simulate/latency`

## Production Release Flow

```text
GitHub
  ↓
Jenkins
  ↓
Lint and Unit Test
  ↓
Docker Build
  ↓
Image Security Scan
  ↓
Docker Registry Push
  ↓
Deploy to Dev
  ↓
Smoke Test Dev
  ↓
Deploy to Staging
  ↓
Smoke Test Staging
  ↓
Prometheus Reliability Gate
  ↓
Manual Approval
  ↓
Production Canary
  ↓
Promote or Rollback
