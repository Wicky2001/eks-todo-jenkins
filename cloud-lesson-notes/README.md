# Cloud lesson notes

Notes written while learning how this project works on AWS. Read them in this order:

| # | Note | What you will learn |
|---|---|---|
| 1 | [EKS Pod Identity vs IRSA](eks-pod-identity-vs-irsa.md) | How a pod gets AWS permissions without stored keys, what EKS injects into the pod, and why we use Pod Identity and not the older IRSA. |
| 2 | [RDS login with IAM and Pod Identity](rds-iam-login-with-pod-identity.md) | How the backend logs in to the PostgreSQL database with no password: the badge, the keys, the login note, TLS, and the one-time script that creates the database user. |
| 3 | [VPC CNI and prefix delegation](vpc-cni-prefix-delegation.md) | How pods get IP addresses, why a small server runs out of them, and how blocks of 16 solve it. Three step-by-step diagrams. |

Other how-to notes live next to the code they describe:

- `migration/README.md`: running the database migrations
- `developmentTools/db/README.md`: the local PostgreSQL for development
- `jenkins/images/SETUP_GUIDE.md`: setting up Jenkins
