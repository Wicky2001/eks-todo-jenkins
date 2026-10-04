# EKS Todo — Jenkins CI/CD, GitOps with Argo CD, and HTTPS on Amazon EKS

A full-stack Todo app (React + Express + PostgreSQL) deployed to **Amazon EKS**. **Jenkins** builds and scans every change, **Argo CD** deploys from Git, **cert-manager** gets a **Let's Encrypt** certificate for HTTPS, and the backend logs in to **Amazon RDS** with IAM instead of a password. Every pull request is scanned by **SonarCloud**, and GitHub branch protection **blocks the merge** if the Quality Gate fails.

Live at **`https://todo.jawsight.online`** while the stack is running. It is torn down with `terraform destroy` between sessions to save cost.

## Architecture

![EKS Todo architecture](screenshots/eks-todo-jenkins-architecture.png)

- **Terraform** builds everything: the VPC (public, private and intra subnets across two Availability Zones, one NAT gateway), an **EKS 1.33** cluster, the add-ons, **ECR** and **RDS**. State lives in **S3** with native S3 state locking.
- **Karpenter** starts EC2 nodes on demand. A small managed node group (`c7i-flex.large`) runs only the cluster add-ons. The **VPC CNI** runs with **prefix delegation** to fit more pods per node.
- **Argo CD** (installed with Helm) watches the `k8s/app` manifests in this repo and syncs them into the cluster. Jenkins never deploys directly.
- **AWS Network Load Balancer** → **ingress-nginx** routes `/` to the frontend and `/api` to the backend. The NLB sends traffic straight to the nginx pod IPs (IP target mode).
- **cert-manager** gets and renews a **Let's Encrypt** certificate for `todo.jawsight.online` (HTTP-01 challenge). nginx serves HTTPS and redirects HTTP to HTTPS.
- **PostgreSQL on Amazon RDS** in private subnets. The backend logs in with a short-lived **IAM token** (no stored password) over TLS, using **EKS Pod Identity**.
- **Prometheus + Grafana** (kube-prometheus-stack, with persistent EBS volumes) for metrics. Helm values for **Fluent Bit** (logs) and **Jaeger** (traces) are in [`k8s/observability`](k8s/observability).

## How a request reaches the app

```
Browser ──HTTPS──► todo.jawsight.online (Namecheap CNAME)
          ──────► AWS NLB (TCP 443, passes the encrypted traffic through)
          ──────► ingress-nginx pods (Let's Encrypt certificate from cert-manager)
                    ├─ "/"     → frontend-service :8080 → frontend pods (React served by nginx)
                    └─ "/api"  → backend-service  :8081 → backend pods (Express)
                                                            └─TLS + IAM token──► RDS PostgreSQL
```

**Domain:** a CNAME record at Namecheap points `todo` to the NLB.

![Namecheap CNAME record for todo.jawsight.online](screenshots/CNAME%20record.jpg)

## GitOps with Argo CD

Jenkins builds the images, pushes them to **ECR** tagged with the full commit SHA, and commits the new tag into the manifests in `k8s/app`. **Argo CD** sees the commit and syncs the cluster (auto-sync with prune and self-heal).

The database migration runs as a Kubernetes **Job** in an earlier **sync wave**, so Argo CD only updates the backend after the migration has finished. The migration only runs again when its own image changes.

**Application network view:** NLB → Ingress → Services → pods, plus the completed migration Job.

![Argo CD network view of eks-todo-app](screenshots/argo_cd.jpg)

**Application tree:** every resource Argo CD manages, including the cert-manager **Certificate** `todo-tls` created from the Ingress.

![Argo CD resource tree with the todo-tls certificate](screenshots/argo_cd_2.jpg)

## Pipelines

| Jenkinsfile | Trigger | Purpose |
|---|---|---|
| [`Jenkinsfile.pr`](jenkins/Jenkinsfile.pr) | Pull requests (multibranch) | SonarCloud scan, then build the backend, frontend and migration images (not pushed) |
| [`Jenkinsfile.deploy`](jenkins/Jenkinsfile.deploy) | Push to `main` (GitHub webhook) | Build and push only the images whose folder changed, then commit the new image tag to `k8s/app` for Argo CD |

**How the gate is enforced:** Jenkins runs `sonar-scanner` (config in [`sonar-project.properties`](sonar-project.properties)) → SonarCloud posts a Quality Gate check on the PR → that check is **Required** in `main`'s branch protection, so a failed gate disables merging.

## No long-lived keys

| Who | How it gets AWS access |
|---|---|
| Backend pod | **EKS Pod Identity** role that can only call `rds-db:connect` for one database user |
| AWS Load Balancer Controller, EBS CSI driver, Karpenter | their own **Pod Identity** roles |
| Jenkins (on EC2) | an **EC2 instance role** limited to pushing to the three ECR repositories. No access keys are stored in Jenkins. |
| RDS admin password | created and kept by AWS in **Secrets Manager**, used only by a one-time setup script |

Jenkins uses a **fine-grained GitHub token** with only the permissions the pipelines need (read and write contents, commit statuses; read pull requests):

![Fine-grained GitHub token with minimal permissions](screenshots/created%20pat%20with%20minimal%20permisssion%20to%20increaaet%20the%20ratelimit%20from%2060%20to%205000%20an%20hour.jpg)

## Demo: the Quality Gate blocks a bad PR

PR #3 adds `backend/src/sonar-test-vulnerabilities.js`, a test fixture with deliberate issues (hard-coded password, command injection, `eval`, MD5 hashing). It is not used by the app and must never reach `main`.

**Jenkins folder and PR pipeline**

![Jenkins folder home page](screenshots/folder%20home%20page.jpg)
![Jenkins PR pipeline overview](screenshots/pipeline%20overview%20screenshot.jpg)

**Quality Gate fails, and GitHub blocks the merge**

![SonarQube Quality Gate failed in Jenkins](screenshots/qulity%20gate%20faild%20jenkins.jpg)
![PR blocked because static analysis failed](screenshots/PR%20-%20blocked%20when%20static%20analysis%20faild.jpg)

## Repository layout

| Folder | Description |
|---|---|
| [`frontend/`](frontend) | React (Vite) UI served by nginx |
| [`backend/`](backend) | Express REST API (PostgreSQL, OpenTelemetry tracing, Prometheus metrics) |
| [`migration/`](migration) | Database migrations, run as a Kubernetes Job |
| [`jenkins/`](jenkins) | Jenkinsfiles and the Jenkins controller and agent images |
| [`k8s/`](k8s) | Kubernetes manifests: the app (synced by Argo CD), Argo CD, cert-manager, Karpenter, observability |
| [`tf/`](tf) | Terraform: `statebucket` (S3 state bucket) and `infra` (VPC, EKS, add-ons, RDS, ECR) |
| [`scripts/`](scripts) | One-time script that creates the IAM-login database user |
| [`cloud-lesson-notes/`](cloud-lesson-notes) | Notes on how the pieces work: Pod Identity, RDS IAM login, VPC CNI, pod networking, Argo CD sync waves |

## Run locally

```bash
npm install
# copy each *.env.example to *.env and adjust
docker compose up
```
