# Cloud lesson notes

Notes written while learning how this project works on AWS. Read them in this order:

| # | Note | What you will learn |
|---|---|---|
| 1 | [EKS Pod Identity vs IRSA](eks-pod-identity-vs-irsa.md) | How a pod gets AWS permissions without stored keys, what EKS injects into the pod, and why we use Pod Identity and not the older IRSA. |
| 2 | [RDS login with IAM and Pod Identity](rds-iam-login-with-pod-identity.md) | How the backend logs in to the PostgreSQL database with no password: the badge, the keys, the login note, TLS, and the one-time script that creates the database user. |
| 3 | [VPC CNI and prefix delegation](vpc-cni-prefix-delegation.md) | How pods get IP addresses, why a small server runs out of them, and how blocks of 16 solve it. Three step-by-step diagrams. |
| 4 | [VPC CNI and pod networking](vpc-cni-pod-networking.md) | The whole path of a request: listeners, target groups, why the NLB skips the Service, NodePort vs IP mode, what a CNI is, and how overlay CNIs like Flannel differ from the VPC CNI. |
| 5 | [Argo CD sync waves](argocd-sync-waves.md) | How the migration Job runs before the backend, why a sync wave and not a PreSync hook, and why the ServiceAccount and ConfigMap need an earlier wave. |
| 6 | [Prometheus stack monitoring](prometheus-stack-monitoring.md) | How prom-client, Prometheus, Alertmanager and Grafana fit together, who pulls from whom, and why each one has its own database. |
| 7 | [Tracing](tracing.md) | Traces and spans, the OpenTelemetry and Jaeger components for the frontend and backend, how to read a trace timeline, and how self time shows what is slow. |
| 8 | [Grafana for metrics, logs and traces](grafana-metrics-logs-traces.md) | Grafana as the one UI: which backend each signal comes from, why traces go through Jaeger, the two Elasticsearch databases, users, and sharing the CA with trust-manager. |
| 9 | [Pod-to-pod traffic: Services, kube-proxy and ztunnel](pod-to-pod-traffic-service-and-ztunnel.md) | How a Service and kube-proxy pick a pod, and how Istio ambient mode does the same with ztunnel: the redirect rule, the sockets inside every pod, and the encrypted tunnel. |
| 10 | [What is inside the mesh, and why](what-is-inside-the-mesh.md) | Which namespaces join the mesh and which stay out, which connections already have their own TLS, and the interview answer. |
| 11 | [Secrets with AWS Secrets Manager and ESO](secrets-with-aws-secrets-manager-and-eso.md) | How ESO copies passwords from AWS Secrets Manager into Kubernetes Secrets: who reads what, every ExternalSecret field, Pod Identity, and all the secrets in this project. |

Other how-to notes live next to the code they describe:

- `migration/README.md`: running the database migrations
- `developmentTools/db/README.md`: the local PostgreSQL for development
- `jenkins/images/SETUP_GUIDE.md`: setting up Jenkins
