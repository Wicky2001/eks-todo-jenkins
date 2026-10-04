# Argo CD sync waves: running the migration before the backend

## In one minute

- The database migration must finish **before** the new backend starts. Otherwise the backend could run against old tables.
- Argo CD does **not** follow the order of files or folders. Without extra settings it applies everything at the same time.
- A **sync wave** is a number on a resource. Argo CD applies the lowest number first and **waits until that wave is healthy** before it starts the next one.
- Our order: **-2** the ServiceAccount and ConfigMap, **-1** the migration Job, **0** the backend and frontend.

---

## Job, Deployment and init container

| | **Deployment** (backend, frontend) | **Job** (migration) | **Init container** |
|---|---|---|---|
| Purpose | runs **forever** (a server) | runs **once until finished** (a task) | runs **before** the main container in the same pod |
| When the program exits | Kubernetes **restarts** it | succeeded: done, never runs again. Failed: retry (`backoffLimit: 1`) | the main container starts only after it succeeded |
| How often | always running | once per change | on **every** pod start |

A migration is a task, so it is a **Job**.

**Why not an init container?** It runs on every backend pod start. With 2 replicas, two migrations would run **at the same time** and can collide. It would also run again on every restart, scale-up or node move. Init containers are fine for harmless checks like "wait until the database is reachable", not for migrations.

## What a sync wave is

A sync wave is one annotation:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
```

- No annotation means wave **0**.
- Lower numbers go first. Negative numbers are allowed.
- Argo CD waits until every resource in a wave is **healthy** before the next wave. A Job is healthy when it is **Complete**. A Deployment is healthy when its pods are ready.
- If a wave fails, Argo CD **stops** there. Later waves are not applied.

## Sync wave or PreSync hook?

Argo CD has two ways to run something first.

| | **Sync wave** (we use this) | **PreSync hook** |
|---|---|---|
| Setting | `argocd.argoproj.io/sync-wave: "-1"` | `argocd.argoproj.io/hook: PreSync` |
| What it does | applies resources in numbered order | runs the Job at the start of **every** sync, before everything else |
| When our migration runs | only when `migration-job.yaml` changes | on **every** deploy, even a backend-only or frontend-only change |

**Why we chose the sync wave:** a backend-only change should not run the migration again. Jenkins only edits `migration-job.yaml` when `migration/**` changed. An unchanged, completed Job stays healthy, so Argo CD skips it and moves straight on to the backend.

## How Argo CD decides the order

Argo CD **never reads inside a resource** to see what it uses. It does not notice that the Job says `serviceAccountName: backend-sa`. It sorts by these rules, in this priority:

```
1. Phase         PreSync → Sync → PostSync (hooks)
2. Wave number   lowest first                       ← strongest rule we use
3. Kind          a fixed list (see below)
4. Name          alphabetical, as a tie-breaker
```

The fixed kind list puts, among others, **ServiceAccount and ConfigMap** before **Service**, then **Deployment**, then **Job**, then **Ingress**. Inside **one** wave, a ServiceAccount is therefore always created before a Deployment or Job. This looks like automatic detection, but it is only that list.

## Why the ServiceAccount and ConfigMap got wave -2

The migration Job **names** two resources in its pod settings. Kubernetes checks them **before** it starts the container:

| Referenced by the Job | If it does not exist yet |
|---|---|
| `serviceAccountName: backend-sa` | the pod is **refused** ("serviceaccount not found") |
| `configMapRef: backend-config-map` | the container **won't start** (`CreateContainerConfigError`) |

The **wave number beats the kind list**. When only the Job had wave -1, it jumped ahead of `backend-sa` and `backend-config-map`, which were still in wave 0:

```
Only the Job had a wave:
  Wave -1   migration Job          ← runs first
  Wave  0   backend-sa, backend-config-map, deployments
  → the Job starts before backend-sa exists → fails

Now:
  Wave -2   backend-sa, backend-config-map
  Wave -1   migration Job          ← both exist now
  Wave  0   backend, frontend
```

Putting them in wave **-1** (the same wave as the Job) would also work, because inside one wave the kind list creates them first. We use **-2** so the order is visible from the numbers alone, without knowing Argo CD's hidden kind list.

## Why the Services have no wave

A Service never names a Deployment. It only says "send traffic to pods with this label" (`selector: app: backend`). Either one can be created first, and they connect automatically. The Deployment does not mention the Service either, so nothing fails. The Services stay in the default wave 0, and the kind list creates them before the Deployments anyway.

`backend-db-config` (the database address) is created by **Terraform** before Argo CD runs, so it needs no wave.

## Our waves

| Wave | File | Why |
|---|---|---|
| -2 | [`k8s/app/backend/service-account.yaml`](../k8s/app/backend/service-account.yaml) | the migration Job runs as this ServiceAccount |
| -2 | [`k8s/app/backend/config-map.yaml`](../k8s/app/backend/config-map.yaml) | the migration Job reads these settings |
| -1 | [`k8s/app/migration/migration-job.yaml`](../k8s/app/migration/migration-job.yaml) | the migration must finish before the backend updates |
| 0 | [`k8s/app/backend/deployment.yaml`](../k8s/app/backend/deployment.yaml) | runs after the migration |
| 0 | [`k8s/app/frontend/deployment.yaml`](../k8s/app/frontend/deployment.yaml) | runs after the migration |
| 0 (no annotation) | Services, Ingress | order does not matter for them |

## What happens on each kind of deploy

```
Backend-only change
  Jenkins updates only k8s/app/backend/deployment.yaml
  Wave -2   unchanged → skip
  Wave -1   Job unchanged and Complete → skip
  Wave  0   backend updated

Migration change
  Jenkins updates migration-job.yaml with the new image tag
  Wave -1   Argo CD deletes and recreates the Job (Force=true,Replace=true) → it runs
            waits until Complete
  Wave  0   backend updated

Migration fails
  Wave -1   Job Failed → Argo CD stops
  Wave  0   never applied → the old backend keeps running
```

## Running the migration twice is safe

[`migration/migrate.js`](../migration/migrate.js) keeps a `migrations` table with every file already applied. On a second run it skips those files and only applies new ones. So even an unplanned extra run changes nothing.

## Gotchas

- **Waves only order resources inside one Argo CD Application.** They do not order two different Applications.
- **A deleted Job runs again.** If the completed Job is removed (by hand, or by a `ttlSecondsAfterFinished` setting), Argo CD sees it missing and creates it again, so the migration runs again. We do not set a TTL.
- **The Job is immutable.** A new image tag cannot be applied in place, which is why `migration-job.yaml` has `argocd.argoproj.io/sync-options: Force=true,Replace=true`.

## Check it on the real cluster

```bash
# did the migration finish? COMPLETIONS should be 1/1
kubectl get jobs -n app

# what did the migration print?
kubectl logs job/migrate-db -n app

# run it again by hand (Argo CD recreates the Job by itself)
kubectl delete job migrate-db -n app
```

## Sources

- [Sync phases and waves (Argo CD docs)](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Resource hooks (Argo CD docs)](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/)
- [Jobs (Kubernetes docs)](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Init containers (Kubernetes docs)](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
