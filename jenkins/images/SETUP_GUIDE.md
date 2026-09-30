# Jenkins Setup Guide

Runs Jenkins on a Linux host as two containers: a **controller** (UI + scheduling) and an **agent** (runs the pipelines). Run everything from the repo root.

## Architecture

```mermaid
flowchart LR
    subgraph internet["Public internet"]
        you["You (browser)"]
        gh["GitHub webhook"]
    end

    you ==>|"public internet<br/>port 8080"| ctrl
    gh ==>|"public internet<br/>port 8080"| ctrl

    subgraph host["Host (EC2)"]
        subgraph net["jenkins-net: private Docker network (not reachable from the internet)"]
            ctrl["jenkins<br/>controller"]
            agent["agent1<br/>runs the pipelines"]
        end
        sock{{"/var/run/docker.sock"}}
        engine[("Docker engine")]
        vol[("jenkins_home<br/>volume")]
    end

    agent -->|"private: http://jenkins:8080"| ctrl
    ctrl --- vol
    agent -->|"docker build / push"| sock
    sock --> engine

    style internet fill:#fff4e5,stroke:#e67e22,stroke-width:2px
    style net fill:#e8f4fd,stroke:#2980b9,stroke-width:2px,stroke-dasharray: 5 3
```

| Name | What |
|---|---|
| `jenkins-controller:latest` / `jenkins-agent:latest` | The two images |
| `jenkins` / `agent1` | The two containers (`agent1` is also the node name in Jenkins) |
| `jenkins-net` | Docker network they share |
| `jenkins_home` | Volume holding all Jenkins data |

## The Docker socket, simply

`docker build` is just a **CLI** that sends requests to the Docker **engine** through the file `/var/run/docker.sock`. Our images install only the CLI. Mounting the host's socket (`-v /var/run/docker.sock:/var/run/docker.sock`) plugs the **host's** engine into the container, so builds run on the host and no second engine is needed.

```mermaid
sequenceDiagram
    participant P as Pipeline step
    participant C as docker CLI (in agent1)
    participant S as docker.sock (mounted)
    participant E as Docker engine (host)
    P->>C: docker build ...
    C->>S: send request
    S->>E: forward request
    E-->>E: builds the image on the HOST
    E-->>C: result
```

Linux checks socket permission by group **ID**, so `DOCKER_GID` must equal the host's `docker` group ID.

```mermaid
flowchart LR
    a["Host: docker group has ID 993"] --> b["Build image with<br/>--build-arg DOCKER_GID=993"]
    b --> c["Inside the image:<br/>docker group = 993,<br/>jenkins user added to it"]
    c --> d["jenkins user may<br/>use docker.sock"]
```

> ⚠️ Socket access is effectively root on the host. Only mount it into containers you trust.

## Setup

```mermaid
flowchart LR
    s1["1. Get<br/>DOCKER_GID"] --> s2["2. Create<br/>network"] --> s3["3. Build + run<br/>controller"] --> s4["4. Unlock<br/>Jenkins"] --> s5["5. Create node<br/>+ copy secret"] --> s6["6. Build + run<br/>agent"] --> s7["7. Check<br/>agent is online"]
```

**1. Get the host's docker group ID** (used as `DOCKER_GID` below, examples use `993`)
```bash
getent group docker | cut -d: -f3
```

**2. Create the network**
```bash
docker network create jenkins-net
```

**3. Build and run the controller**
```bash
docker build -f jenkins/images/Dockerfile.controller --build-arg DOCKER_GID=993 -t jenkins-controller:latest jenkins/images
```
```bash
docker run -d \
  --name jenkins \
  --restart unless-stopped \
  --network jenkins-net \
  -p 8080:8080 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins-controller:latest
```

**4. Unlock Jenkins** at `http://<host-ip>:8080` with:
```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

**5. Create the agent node** (Manage Jenkins → Nodes → New Node): name `agent1`, Permanent Agent, remote root `/home/jenkins/agent1`, label `docker`, launch method "connect to the controller". Copy the **secret** it shows.

**6. Build and run the agent**
```bash
docker build -f jenkins/images/Dockerfile.agent --build-arg DOCKER_GID=993 -t jenkins-agent:latest jenkins/images
```
```bash
docker run -d \
  --name agent1 \
  --restart unless-stopped \
  --network jenkins-net \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e JENKINS_URL=http://jenkins:8080 \
  -e JENKINS_SECRET=<secret-from-step-5> \
  -e JENKINS_AGENT_NAME=agent1 \
  -e JENKINS_AGENT_WORKDIR=/home/jenkins/agent1 \
  jenkins-agent:latest
```
No space after each `\`.

**7. Check** — `agent1` should show **online** in Jenkins:
```bash
docker exec agent1 docker version
docker exec agent1 aws --version
```

## What the deploy pipeline does

```mermaid
flowchart LR
    push["Push to main"] --> jenkins["Jenkins<br/>Jenkinsfile.deploy"]
    jenkins -->|"build changed services,<br/>tag = commit SHA"| ecr[("Amazon ECR")]
    jenkins -->|"commit new image tag<br/>to k8s/app/*.yaml"| repo["GitHub repo (main)"]
    repo -->|"Argo CD sees the change"| argo["Argo CD"]
    argo -->|"deploys"| eks["EKS cluster"]
    ecr -.->|"image pulled"| eks
```

## Jenkins credentials

Manage Jenkins → Credentials. IDs must match exactly.

```mermaid
flowchart LR
    k1["aws-access-key-id<br/>aws-secret-access-key"] -->|"login + push images"| ecr[("ECR")]
    k2["github-push"] -->|"push tag change to main"| repo["GitHub repo"]
    k3["SonarCloud server"] -->|"PR analysis"| sonar["SonarCloud"]
```

| ID | Type | Value |
|---|---|---|
| `aws-access-key-id` | Secret text | Access key ID of IAM user `eks-todo-jenkins` |
| `aws-secret-access-key` | Secret text | Its secret key |
| `github-push` | Username with password | GitHub username + token (Contents: write) |

For `Jenkinsfile.pr`, add a SonarQube server named `SonarCloud` (Manage Jenkins → System).

## Jobs

| Job | Type | Script path |
|---|---|---|
| Deploy | Pipeline | `jenkins/Jenkinsfile.deploy` (GitHub push webhook, `main`) |
| PR checks | Multibranch | `jenkins/Jenkinsfile.pr` |

Webhook URL: `http://<host-ip>:8080/github-webhook/`

## Everyday

```bash
docker logs -f agent1        # logs
docker restart jenkins agent1
```

To update an image: rebuild it (step 3 or 6), `docker rm -f <container>`, run it again. Keep `-v jenkins_home:...` on the controller. **Never** `docker volume rm jenkins_home`, since it holds all jobs and credentials.

## Troubleshooting

| Problem | Fix |
|---|---|
| `permission denied ... docker.sock` | `DOCKER_GID` doesn't match the host. Redo step 1 and rebuild. |
| Agent offline | `docker logs agent1`. Check the secret, the node name, and that both containers are on `jenkins-net`. |
| `docker run requires at least 1 argument` | A line break without `\` split the command. |
| Agent secret leaked | Delete the node and create one with a new name. |

**Security:** allow port `8080` only from your IP plus [GitHub's webhook ranges](https://api.github.com/meta) (`hooks`). Never open `50000`.
