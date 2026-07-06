# Rollback Strategy

ReleaseOps supports rollback when a release becomes unsafe.

## Rollback Triggers

- Unit test failure
- Security scan failure
- Smoke test failure
- Readiness probe failure
- High error rate
- High latency
- Pod restart spike
- Canary analysis failure
- Manual rejection

## Rollback Flow

Jenkins detects failure
  ↓
Jenkins stops promotion
  ↓
Rollback command is executed
  ↓
Previous stable version is restored
  ↓
Pipeline is marked failed
  ↓
Release audit report is generated
