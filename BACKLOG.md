# Backlog

## Local platform

### Highly available Postgres (CloudNativePG)

Postgres is a single instance (`modules/postgres-local`, one replica on one node). If its node goes down, Temporal loses its database. The three `cpu` nodes are already there to spread instances over.

- [ ] CloudNativePG operator installed by its helm chart (CRDs handled as in [Helm charts and CRDs](#helm-charts-and-crds))
- [ ] New module `postgres-cnpg` replaces `postgres-local` in `envs/local`: a `Cluster` with 3 instances, one primary and two replicas
- [ ] Instances spread one per `cpu` node (pod anti-affinity on `kubernetes.io/hostname`), PodDisruptionBudget
- [ ] Automatic failover: when the primary goes down, a replica is promoted within seconds
- [ ] Temporal connects to the `<cluster>-rw` service, which always points to the current primary. `modules/temporal` does not change, only `host`, `user` and `password` in `envs/local`
- [ ] Failover drill: delete the primary pod, check that a replica is promoted and Temporal keeps serving (`temporal operator cluster health`, `temporal workflow list`)
- [ ] Backups and WAL archive to SeaweedFS (S3 API, `modules/seaweedfs-local`). HA does not protect from `DROP TABLE`: it is replicated instantly

### Kueue: queueing pipeline Jobs

`run_job` in de_worker creates Jobs directly, so the scheduler decides alone: with one (simulated) GPU, a second train Job sits `Pending` with no visible queue, priority or quota. Kueue makes the queue explicit and is the same on kind and in the cloud.

- [ ] Kueue installed by its helm chart (CRDs handled as in [Helm charts and CRDs](#helm-charts-and-crds))
- [ ] `ResourceFlavor` per pool from the [cluster contract](README.md#cluster-contract): `cpu` (`node-pool=cpu`) and `gpu` (`node-pool=gpu` + toleration `nvidia.com/gpu`)
- [ ] `ClusterQueue` with quotas for `cpu`, `memory`, `nvidia.com/gpu`; `LocalQueue` in the `de-worker` namespace
- [ ] `run_job` creates Jobs with the label `kueue.x-k8s.io/queue-name` and `suspend: true`, without its own nodeSelector and tolerations: the flavor sets them
- [ ] Priorities: `run` (inference) above `train`
- [ ] Check: two train workflows started together, the second Job waits admitted-but-suspended in the queue, not `Pending` on the scheduler

### Highly available ClickHouse and SeaweedFS

ClickHouse (`modules/clickhouse-local`) and SeaweedFS (`modules/seaweedfs-local`) are single instances, like Postgres before CloudNativePG. Losing their node loses the dataset, predictions and model artifacts.

- [ ] ClickHouse: ClickHouse Keeper (3 instances) + 2 replicas, tables on `ReplicatedMergeTree`, one replica per `cpu` node
- [ ] Migrations in `db/clickhouse/migrations` updated for `ON CLUSTER` and replicated engines
- [ ] SeaweedFS: master (3 for raft), volume servers and filer split into separate StatefulSets over the `cpu` nodes, replication `001` so a volume survives the loss of one node
- [ ] Failover drill for both: delete a pod during `ingest` and `train`, the workflows finish

### Real GPU on the local gpu node

The `gpu` pool only simulates a GPU: a fake `nvidia.com/gpu` resource, pods run on CPU. Needed once a model step has to run on CUDA locally. Optional per machine: `simulated` stays the default for hosts without an NVIDIA GPU.

A first version was written and never run end to end, then removed. It is in commit `8eaa66d` (`gpu_mode`, `setup-gpu-nodes.sh`, `modules/nvidia-device-plugin`, preflight checks, README section) and can be restored from there.

- [ ] `gpu_mode` variable in `clusters/kind`: `simulated` (default) or `nvidia`, set per machine in the gitignored `local.auto.tfvars`
- [ ] Host prerequisites documented, not automated (they need `sudo`): NVIDIA driver, nvidia-container-toolkit, nvidia as docker's default runtime, `accept-nvidia-visible-devices-as-volume-mounts = true`
- [ ] `make preflight` checks the host prerequisites in `nvidia` mode
- [ ] GPU node gets the host GPUs through the `/dev/null` → `/var/run/nvidia-container-devices/all` mount, the toolkit inside the node, nvidia as the default containerd runtime (steps of NVIDIA's [nvkind](https://github.com/NVIDIA/nvkind))
- [ ] NVIDIA device plugin installed in `envs/local` in `nvidia` mode; GPU nodes labelled `nvidia.com/gpu.present=true`
- [ ] End-to-end check: a pod requesting `nvidia.com/gpu: 1` on the `gpu` pool runs `nvidia-smi` and sees the host GPU
- [ ] Model step manifests unchanged between `simulated` and `nvidia`

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

- [ ] Models and results in S3 instead of in-cluster SeaweedFS
- [ ] Temporal and MLflow databases on RDS Postgres (or Temporal Cloud), Multi-AZ, automated snapshots
- [ ] Secrets in AWS Secrets Manager, synced into the cluster by External Secrets Operator
- [ ] ClickHouse backed up with `BACKUP DATABASE app TO S3(...)` on a schedule (incremental, `base_backup`), retention configured
- [ ] SeaweedFS buckets (`mlflow`, `pipeline`) versioned and replicated to another bucket or S3; once in the cloud, S3 versioning and lifecycle rules instead
- [ ] Kubernetes objects and volumes backed up with Velero on a schedule
- [ ] Restore is tested: a scheduled drill restores RDS, ClickHouse and Velero backups into a scratch environment, and `run` on the restored data gives the same accuracy

### Kubernetes upgrades

- [ ] Upgrade procedure: control plane first, then nodes, one minor version at a time
- [ ] Deprecated API check (`pluto` or `kubent`) runs in CI against rendered manifests and charts, and before every upgrade
- [ ] Nodes replaced gradually: Karpenter drift for Karpenter-managed nodes, rolling update for managed node groups
- [ ] Upgrade rehearsed on a staging cluster before production

### Disruption tolerance

Node drains during upgrades and spot interruptions must not take services down.

- [ ] Temporal (frontend, history, matching, worker), MLflow and pipeline workers run at least 2 replicas
- [ ] PodDisruptionBudget for each of them (`maxUnavailable: 1`)
- [ ] be_service Add data serialized across replicas: today an in-process mutex keeps two batches from reading the same offset, which holds only with one replica. Options: a Postgres advisory lock, or Add data as a Temporal workflow with a fixed ID
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
- [ ] de_worker (Python SDK): workflow code stays deterministic under the SDK sandbox; `workflow.patched("<change-id>")` around changed steps of `Ingest`/`Train`/`Run`, `workflow.deprecate_patch()` once old runs are gone
- [ ] Inputs and results of workflows and `run_job` are versioned dataclasses: new fields only with defaults, so be_service (Rust) and old histories keep decoding
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
- [ ] Authentication on be_service: OIDC login (or a session behind an auth proxy such as oauth2-proxy) before any button; Temporal, ClickHouse and MLflow are reachable only from inside the cluster, never through be_service as a proxy
- [ ] be_service talks to ClickHouse as a read-only user; only mle_models Jobs have write grants
- [ ] NetworkPolicy: deny by default between namespaces, explicit allows
- [ ] Node images (AMI) updated on a schedule
- [ ] Container images scanned in CI, builds fail on critical vulnerabilities
- [ ] Workloads run as non-root, Pod Security Standards `restricted` where possible
- [ ] Audit logs of the Kubernetes API enabled

### Observability

- [ ] Metrics: Prometheus, Grafana dashboards for cluster, Temporal, Kueue queues, GPU (DCGM)
- [ ] Alerts in Alertmanager with runbook links: node not ready, pending pods, Kueue backlog, Temporal task queue backlog, failed workflows, disk and memory pressure
- [ ] Pipeline metrics: duration and outcome of every `run_job` by step (ingest, train, predict), time a Job waits before running, accuracy of each model version, rows in `samples` and `predictions`
- [ ] ClickHouse metrics (built-in Prometheus endpoint) and MLflow server metrics (`--expose-prometheus`) on the same dashboards
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
