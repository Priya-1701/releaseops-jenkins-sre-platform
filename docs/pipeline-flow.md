# ReleaseOps Pipeline Flow

## End-to-End Flow

1. Developer pushes code to GitHub
2. Jenkins starts pipeline
3. Jenkins checks out source code
4. Jenkins installs dependencies
5. Jenkins runs lint checks
6. Jenkins runs unit tests
7. Jenkins builds Docker image
8. Jenkins scans Docker image
9. Jenkins pushes image to registry
10. Jenkins deploys image to dev
11. Jenkins runs dev smoke test
12. Jenkins deploys image to staging
13. Jenkins runs staging smoke test
14. Jenkins queries Prometheus
15. Jenkins evaluates reliability gate
16. Jenkins waits for manual approval
17. Jenkins starts production canary
18. Jenkins validates canary metrics
19. Jenkins promotes or rolls back
20. Jenkins generates release audit report
