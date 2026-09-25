# Runbook: ContainerMemoryLimitThrashing

| | |
|---|---|
| **Alert** | `ContainerMemoryLimitThrashing` (ticket): a container hits its memory limit > 10×/s for 10 min |
| **Why it matters** | Too-tight limits usually **don't OOM-kill**. The kernel reclaims page cache, **including the program's own code**, which it then re-reads from disk. Result: **latency and node-wide I/O pressure, no restarts, no OOM alerts** |
| **Signal** | `container_memory_failcnt` = cgroup v2 `memory.events: max`. Major page faults alone aren't enough (load-generator: 31/s while far below its limit) |

## Diagnose
```bash
# Which containers are hitting their limit?
curl -s -G localhost:9090/api/v1/query --data-urlencode \
 'query=topk(5, sum by (namespace,container) (rate(container_memory_failcnt{container!=""}[5m])))'
# How close to the limit?
curl -s -G localhost:9090/api/v1/query --data-urlencode \
 'query=topk(5, max by (namespace,pod,container) (container_memory_working_set_bytes{container!=""}) / on(namespace,pod,container) max by (namespace,pod,container) (kube_pod_container_resource_limits{resource="memory"}))'
# Ground truth inside the node (if Prometheus itself is degraded):
docker exec sre-lab-worker sh -c 'for d in $(find /sys/fs/cgroup/kubelet.slice -name "cri-containerd-*.scope" -type d); do
  echo "$(grep "^max " $d/memory.events|cut -d" " -f2) $(grep "^pgmajfault " $d/memory.stat|cut -d" " -f2) $(basename $d|cut -c16-27)"; done' | sort -rn | head
```

## Mitigate
Raise the limit **from measured data** in `apps/astronomy-shop/values.yaml` (`components.<svc>.resources`), `make deploy`, then check that `failcnt` goes flat.
Phase 2 example: product-catalog 20Mi → 128Mi took the checkout latency SLI from 100% errors to 0%.
