# Jenkins Setup Guide

How to run Jenkins for this project on a Linux host (e.g. an EC2 instance) using Docker: one **controller** and one **agent**, both as containers.

All commands are run from the **repo root** on the host.

## What's in this folder

| File | What it is |
|---|---|
| `Dockerfile.controller` | Jenkins controller: web UI, job scheduling, credentials. Doesn't run builds. |
| `Dockerfile.agent` | Build agent: runs the pipelines. Has Docker CLI, SonarScanner and AWS CLI. |
| `Jenkinsfile.deploy` | Push pipeline: build → push to ECR → update k8s manifests (Argo CD deploys) |
| `Jenkinsfile.pr` | Pull request pipeline: SonarCloud scan + test builds |

| Name | Used for |
|---|---|
| `jenkins-controller:latest` | Controller image |
| `jenkins-agent:latest` | Agent image |
| `jenkins` | Controller container |
| `agent1` | Agent container (and the node name in Jenkins) |
| `jenkins-net` | Docker network both containers join |
| `jenkins_home` | Docker volume holding all Jenkins data (jobs, credentials, plugins) |

## How the pieces talk to each other

```
                         host (EC2)
 ┌───────────────────────────────────────────────────────┐
 │  jenkins-net (Docker network)                         │
 │  ┌─────────────┐   http://jenkins:8080  ┌──────────┐  │
 │  │  jenkins    │◀───────────────────────│  agent1  │  │
 │  │ (controller)│                        │          │  │
 │  └─────────────┘                        └────┬─────┘  │
 │                                              │        │
 │                     /var/run/docker.sock ◀───┘        │
 │                     (host's Docker engine)            │
 └───────────────────────────────────────────────────────┘
        ▲ :8080 (browser, your IP only)
```

- The **agent connects to the controller** using the container name `jenkins`. That works because both containers are on `jenkins-net`, where Docker gives every container a hostname equal to its name.
- Only port `8080` is published, so you can open the UI in a browser. Agent traffic never leaves the host.

## The Docker socket, simply explained

The pipelines run `docker build` and `docker push`, but the agent is itself a container. So how does it run Docker?

Docker has two parts:
- **Docker CLI**: the `docker` command. It only *sends requests*.
- **Docker engine**: the background service that actually builds images and runs containers.

The CLI sends its requests to the engine through a special file: `/var/run/docker.sock` (the "socket"). Think of it as the engine's phone line.

Our images install **only the CLI**. With

```
-v /var/run/docker.sock:/var/run/docker.sock
```

we plug the **host's** phone line into the container. So when the agent runs `docker build`, the request goes to the **host's** Docker engine, which does the work. No second Docker engine runs inside the container. Images built this way appear on the host (`docker images` on the host shows them).

**Why `DOCKER_GID`?** The socket file belongs to the host's `docker` group. Linux checks permissions by group **ID number**, not name. The images set their internal `docker` group to the host's ID, and add the `jenkins` user to it, so `jenkins` is allowed to use the socket. If the numbers don't match you get `permission denied ... docker.sock`.

> ⚠️ Anything with access to the socket effectively has root on the host. Only mount it into containers you trust.

## First-time setup

### 1. Find the host's docker group ID

```bash
getent group docker | cut -d: -f3
```

Use this number as `DOCKER_GID` below (examples use `993`).

### 2. Create the network

```bash
docker network create jenkins-net
```

### 3. Build and run the controller

```bash
docker build \
  -f jenkins/Dockerfile.controller \
  --build-arg DOCKER_GID=993 \
  -t jenkins-controller:latest \
  jenkins
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

`-v jenkins_home:/var/jenkins_home` stores all Jenkins data in a volume, so it survives restarts and image rebuilds.

### 4. Unlock Jenkins

Get the first-time admin password:

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Open `http://<host-ip>:8080`, paste it, install the suggested plugins, and create your admin user.

### 5. Create the agent node in Jenkins

Manage Jenkins → Nodes → **New Node**:

| Field | Value |
|---|---|
| Node name | `agent1` |
| Type | Permanent Agent |
| Remote root directory | `/home/jenkins/agent1` |
| Labels | `docker` (the Jenkinsfiles use `agent { label 'docker' }`) |
| Launch method | Launch agent by connecting it to the controller |

Save, then open the node. The page shows a **secret**. Copy it for the next step.

Also set the controller's own executors to `0` (Manage Jenkins → Nodes → Built-In Node → Configure), so builds only run on the agent.

### 6. Build and run the agent

```bash
docker build \
  -f jenkins/Dockerfile.agent \
  --build-arg DOCKER_GID=993 \
  -t jenkins-agent:latest \
  jenkins
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

Every line except the last ends with `\`, with **no space after it**.

### 7. Check everything works

```bash
docker ps
docker exec agent1 docker version
docker exec agent1 aws --version
docker exec agent1 sonar-scanner --version
```

In Jenkins, `agent1` should show as **online**.

## Credentials to add in Jenkins

Manage Jenkins → Credentials → (global) → Add. The **IDs must match exactly**, because the Jenkinsfiles refer to them.

| ID | Type | Value | Used by |
|---|---|---|---|
| `aws-access-key-id` | Secret text | Access key ID of IAM user `eks-todo-jenkins` | `Jenkinsfile.deploy` |
| `aws-secret-access-key` | Secret text | Its secret access key | `Jenkinsfile.deploy` |
| `github-push` | Username with password | GitHub username + Personal Access Token (Contents: write) | `Jenkinsfile.deploy` |

SonarCloud: Manage Jenkins → System → SonarQube servers → add a server named **`SonarCloud`** with your SonarCloud token (used by `Jenkinsfile.pr`).

## Jobs to create

| Job | Type | Script path | Trigger |
|---|---|---|---|
| Deploy | Pipeline (SCM) | `jenkins/Jenkinsfile.deploy` | GitHub push webhook, branch `main` |
| PR checks | Multibranch Pipeline | `jenkins/Jenkinsfile.pr` | Pull requests |

GitHub webhook: repo → Settings → Webhooks → `http://<host-ip>:8080/github-webhook/`.

## Everyday commands

```bash
# Logs
docker logs -f jenkins
docker logs -f agent1

# Restart
docker restart jenkins agent1

# Stop / start
docker stop agent1 jenkins
docker start jenkins agent1
```

### Updating an image (e.g. after editing a Dockerfile)

Rebuild, remove the old container, run again with the same `docker run` command as in the setup steps:

```bash
docker build -f jenkins/Dockerfile.agent --build-arg DOCKER_GID=993 -t jenkins-agent:latest jenkins
docker rm -f agent1
# then run the step 6 'docker run' command again
```

Recreating the **controller** container is safe as long as you reuse `-v jenkins_home:/var/jenkins_home`. **Never** run `docker volume rm jenkins_home`, because that deletes all jobs, credentials and plugins.

## Troubleshooting

| Problem | Fix |
|---|---|
| `permission denied ... /var/run/docker.sock` | `DOCKER_GID` doesn't match the host. Re-check step 1 and rebuild the image. |
| Agent stays offline | `docker logs agent1`. Check the secret, the node name matches `JENKINS_AGENT_NAME`, and both containers are on `jenkins-net` (`docker network inspect jenkins-net`). |
| `docker run requires at least 1 argument` | A line break without `\` split the command. The image name must be part of the command. |
| Agent secret leaked | Delete the node and create one with a new name (the secret is derived from the node name). |

## Security checklist

- EC2 security group: allow `8080` **only from your IP**, plus GitHub's webhook IP ranges (the `hooks` list at https://api.github.com/meta) so push webhooks still arrive. Don't open `50000`; the agent connects over `jenkins-net`.
- Never commit secrets. They live only in Jenkins credentials.
