# EKS Todo — Jenkins CI/CD with SonarCloud Quality Gates

A full-stack Todo app (React + Express + Mongoose/DocumentDB) used to demo **Jenkins pipelines**, **SonarCloud static analysis**, and a **GitOps deployment to Amazon EKS**. Every pull request is built by Jenkins and scanned by SonarCloud, and GitHub branch protection **blocks the merge** if the Quality Gate fails.

## Architecture

![EKS Todo architecture](screenshots/eks-todo-jenkins-architecture.png)

- **Terraform** provisions the VPC (3 AZs), an **EKS 1.33** cluster and its add-ons, with state in **S3**
- **Karpenter** scales nodes on demand instead of a fixed-size node group
- **Argo CD** watches the `k8s/` manifests in this repo and syncs them into the cluster (GitOps — Jenkins never deploys directly)
- An internet-facing **AWS Network Load Balancer** + **ingress-nginx** route traffic to the frontend, backend and migration workloads
- **Prometheus**, **Fluent Bit** and **Jaeger** cover metrics, logs and traces for the backend
- **Sealed Secrets** and the **AWS LB Controller** run as cluster add-ons managed by Karpenter

## Pipelines

| Job | Jenkinsfile | Trigger | Purpose |
|---|---|---|---|
| `eks-todo-jenkins` (multibranch) | [`Jenkinsfile.ci`](jenkins/Jenkinsfile.ci) | Pull requests | SonarCloud scan + build all 3 images (not pushed) |
| `todo-backend` | [`Jenkinsfile.backend`](jenkins/Jenkinsfile.backend) | Push webhook | Build & push backend image when `backend/**` changes |
| `todo-frontend` | [`Jenkinsfile.frontend`](jenkins/Jenkinsfile.frontend) | Push webhook | Build & push frontend image |
| `todo-migrations` | [`Jenkinsfile.migration`](jenkins/Jenkinsfile.migration) | Push webhook | Build & push migration image when `mongoose/**` changes |

All jobs run on a dedicated `docker` agent (`agent1`). Images are pushed to Docker Hub tagged `<short-sha>-<build-number>` and `latest`, using credentials from the Jenkins credential store.

**How the gate is enforced:** Jenkins runs `sonar-scanner` (config in [`sonar-project.properties`](sonar-project.properties)) → SonarCloud posts a Quality Gate check on the PR → that check is **Required** in `main`'s branch protection, so a failed gate disables merging.

## Demo

PR #3 adds [`backend/src/sonar-test-vulnerabilities.js`](backend/src/sonar-test-vulnerabilities.js), a test fixture with deliberate issues (hard-coded password, command injection, `eval`, MD5 hashing). It is not used by the app and must never reach `main`.

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
| [`backend/`](backend) | Express REST API |
| [`mongoose/`](mongoose) | Database migrations |
| [`jenkins/`](jenkins) | Jenkinsfiles |
| [`k8s/`](k8s) | Kubernetes manifests |
| [`tf/`](tf) | Terraform for AWS / EKS |

## Run locally

```bash
npm install
# copy each *.env.example to *.env and adjust
docker compose up
```
