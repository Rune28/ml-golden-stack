# Example scheme: pods per node

A snapshot of the local cluster taken on 2026-10-12 with `kubectl get pods -A -o wide`.

Only the pool of a pod is fixed (`cpu` or `gpu`, by node selector and taints). The node inside the pool is chosen by the scheduler, so the placement below changes every time the cluster or a pod is recreated. For the stable picture see [Services](../README.md#services) in the README.

```mermaid
flowchart TB
    host(["Host: 32 CPU, ~15 GiB RAM<br/>every kind node is a docker container on it"])

    subgraph kind["kind cluster gold · 5 nodes"]
        direction TB

        subgraph cp["gold-control-plane · taint control-plane"]
            direction LR
            apiserver["kube-apiserver"]
            etcd[("etcd")]
            sched["kube-scheduler"]
            ctrl["kube-controller-manager"]
            dns["coredns ×2"]
            lpp["local-path-provisioner<br/>volumes for PVCs"]
            sys0["kube-proxy · kindnet"]
        end

        subgraph cpu["cpu pool · on-demand · 3 nodes"]
            direction LR

            subgraph w1["gold-worker"]
                fe["temporal-frontend"]
                web["temporal-web"]
                sys1["kube-proxy · kindnet"]
            end

            subgraph w2["gold-worker2"]
                pg[("postgres-0")]
                match["temporal-matching"]
                admin["temporal-admintools"]
                nsjob[["temporal-namespace<br/>Job, completed"]]
                sys2["kube-proxy · kindnet"]
            end

            subgraph w3["gold-worker3"]
                hist["temporal-history"]
                tworker["temporal-worker"]
                sys3["kube-proxy · kindnet"]
            end
        end

        subgraph gpu["gpu pool · spot · 1 node"]
            subgraph w4["gold-worker4 · taint nvidia.com/gpu · simulated nvidia.com/gpu: 1"]
                models["model steps (planned)"]:::planned
                sys4["kube-proxy · kindnet"]
            end
        end
    end

    host --- kind

    classDef planned stroke-dasharray: 5 5,opacity:0.7
    classDef system fill:#eee,stroke:#bbb,color:#555
    class sys0,sys1,sys2,sys3,sys4 system
```

## What to read from it

- **control-plane** runs only Kubernetes system components. Platform pods never land there because of its taint.
- **cpu pool** runs Postgres and the six Temporal components, spread over the three nodes by the scheduler.
- **gpu pool** has only the per-node system pods. Platform pods have no toleration for `nvidia.com/gpu` and select `node-pool=cpu`, so the node stays free for model steps.
- **Resources are shared.** Every node reports 32 CPU and ~15 GiB, but these are the same CPUs and memory of one laptop, not five machines.
- `kube-proxy` and `kindnet` run on every node as DaemonSets: service routing and pod networking.

## Refresh the snapshot

```bash
export KUBECONFIG=$PWD/infra/clusters/kind/.kubeconfig
kubectl get pods -A -o custom-columns='NODE:.spec.nodeName,NS:.metadata.namespace,POD:.metadata.name' | sort
```
