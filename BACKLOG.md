# Backlog

## Infrastructure: long-lived cluster

Needed once the stack runs on a cluster that is updated in place (EKS) instead of being recreated like the local kind cluster. Goal: every change reaches a running cluster without downtime or data loss.

### Change management

#### Separate state per layer

Split OpenTofu state into `infra` (VPC, EKS, node groups) and `platform` (helm releases), so a failing helm release cannot touch the cluster itself.

- [ ] `infra` and `platform` are separate root modules with separate state
- [ ] `platform` reads cluster connection data from `infra` outputs (remote state or data sources), not from shared variables
- [ ] Destroying or re-applying `platform` leaves `infra` untouched

#### Remote state

- [ ] State stored in S3 with locking (`use_lockfile = true`)
- [ ] OpenTofu state encryption enabled, key in KMS
- [ ] Bucket versioning on, public access blocked, access limited to CI and admins

#### Protection against deletion

Mark resources holding the cluster or data with `lifecycle { prevent_destroy = true }`.

- [ ] EKS cluster
- [ ] S3 buckets with models and results
- [ ] RDS instances for Temporal and MLflow
- [ ] A plan that would destroy any of them fails

#### Plan review before apply

No `-auto-approve` outside the local environment.

- [ ] `make` targets for cloud environments run `plan` and `apply` as separate steps
- [ ] Apply uses a saved plan file (`tofu plan -out`, then `tofu apply <file>`), so what was reviewed is what gets applied
- [ ] Review checklist in the PR template: look for `must be replaced` and `destroy`

#### Apply from CI

Changes reach cloud environments only through CI, which also gives an audit log.

- [ ] On pull request: `fmt -check`, `validate`, `plan`, plan posted as a PR comment
- [ ] On merge to main: `apply` of the reviewed plan
- [ ] Cloud credentials available only to CI (OIDC role), not to laptops
- [ ] Applies are serialized (one at a time per environment)

### Data and backups

The cluster is disposable only when data lives outside it.

- [ ] Models and results in S3 instead of in-cluster MinIO
- [ ] Temporal and MLflow databases on RDS Postgres (or Temporal Cloud), Multi-AZ, automated snapshots
- [ ] Secrets in AWS Secrets Manager, synced into the cluster by External Secrets Operator
- [ ] Kubernetes objects and volumes backed up with Velero on a schedule
- [ ] Restore is tested: a scheduled drill restores RDS and Velero backups into a scratch environment

### Kubernetes upgrades

- [ ] Upgrade procedure: control plane first, then nodes, one minor version at a time
- [ ] Deprecated API check (`pluto` or `kubent`) runs in CI against rendered manifests and charts, and before every upgrade
- [ ] Nodes replaced gradually: Karpenter drift for Karpenter-managed nodes, rolling update for managed node groups
- [ ] Upgrade rehearsed on a staging cluster before production

### Disruption tolerance

Node drains during upgrades and spot interruptions must not take services down.

- [ ] Temporal (frontend, history, matching, worker), MLflow and pipeline workers run at least 2 replicas
- [ ] PodDisruptionBudget for each of them (`maxUnavailable: 1`)
- [ ] Topology spread constraints across availability zones
- [ ] Readiness and liveness probes on every service
- [ ] Resource requests and limits on every container

### Helm charts and CRDs

- [ ] Every chart version pinned, upgrades go through a PR with the changelog linked
- [ ] For each chart, document how it ships CRDs. `helm upgrade` does not update CRDs placed in the chart's `crds/` directory, so those are applied as a separate step before the chart upgrade
- [ ] CRDs for Kueue and any Temporal operator covered by the step above

### Stack-specific upgrades

#### Temporal workflow versioning

Long-running workflows outlive worker deployments. Changed workflow code replaying an old history fails with a non-determinism error.

- [ ] Workflow changes guarded with `workflow.patched()` or Temporal Worker Versioning
- [ ] CI replay test: recorded workflow histories replayed against the new worker code
- [ ] Deployment procedure keeps old workers until workflows started on old code finish (or are migrated)

#### Database schema migrations

- [ ] Temporal server upgrades run schema migrations (`temporal-sql-tool` or the chart's schema update job) before new server pods start
- [ ] MLflow upgrades run `mlflow db upgrade` as a Job before the new server starts
- [ ] Database snapshot taken before every migration

#### Kueue

- [ ] Before upgrading, check release notes for API version changes and deprecations of Kueue resources
- [ ] Kueue manifests in the repo use the current API version

### Drift detection

On a long-lived cluster someone will run `kubectl edit` "for a minute".

- [ ] GitOps: OpenTofu creates the infrastructure and installs Argo CD (or Flux), Argo CD deploys platform and applications from the repo and reverts manual changes
- [ ] Scheduled `tofu plan` in CI, alert when the plan is not empty

### Access and security

- [ ] No shared admin kubeconfig: access through IAM / SSO (EKS access entries) and RBAC roles
- [ ] NetworkPolicy: deny by default between namespaces, explicit allows
- [ ] Node images (AMI) updated on a schedule
- [ ] Container images scanned in CI, builds fail on critical vulnerabilities
- [ ] Workloads run as non-root, Pod Security Standards `restricted` where possible
- [ ] Audit logs of the Kubernetes API enabled

### Observability

- [ ] Metrics: Prometheus, Grafana dashboards for cluster, Temporal, Kueue queues, GPU (DCGM)
- [ ] Alerts in Alertmanager with runbook links: node not ready, pending pods, Kueue backlog, Temporal task queue backlog, failed workflows, disk and memory pressure
- [ ] Centralized logs with retention
- [ ] Tracing through workflows (OpenTelemetry)

### Cost

- [ ] OpenCost (or Kubecost) with cost per namespace and per pipeline
- [ ] Cost per processed match tracked as a metric
- [ ] Budget alerts in the cloud account

### Runbooks

Stored in `docs/runbooks/`, each with steps, checks and rollback.

- [ ] Upgrade Kubernetes
- [ ] Upgrade a helm chart with CRDs
- [ ] Restore from backup (RDS, Velero)
- [ ] Temporal is down
- [ ] Spot capacity exhausted
- [ ] Rotate credentials and secrets
