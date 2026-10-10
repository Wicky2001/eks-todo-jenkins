#!/usr/bin/env bash
#
# Tears down the whole tf/infra stack without leaving paid resources behind.
#
# Why not just `terraform destroy`? Some AWS resources are created by controllers
# inside the cluster, so Terraform does not know about them:
#   - the NLB (made by the AWS Load Balancer Controller for the ingress-nginx Service)
#   - EC2 nodes (made by Karpenter)
#   - EBS volumes (made by the EBS CSI driver for the monitoring PVCs)
# If the cluster is deleted first, nobody is left to delete them. The NLB and the
# Karpenter nodes also sit in the VPC subnets, so the VPC delete would fail.
#
# So this script asks the controllers to clean up while they are still running,
# then runs `terraform destroy`, then removes anything that was still left over.
#
# The S3 state bucket (tf/statebucket) is kept: it costs almost nothing and the
# next `terraform apply` needs it.
#
# Usage:  bash scripts/destroy.sh

set -euo pipefail

export AWS_PROFILE="terraform-user"
REGION="us-east-1"
CLUSTER="todo-cluster"
JENKINS_USER="eks-todo-jenkins"

# kubectl and terraform run `aws eks get-token` themselves, so they must find aws.
# A PATH entry with a stray quote (for example C:\Python27\Scripts\") makes Windows
# programs like kubectl misread the rest of PATH, so drop such entries for this script.
PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '"' | paste -sd ':' -)"
export PATH
if ! command -v aws.exe >/dev/null 2>&1 && ! command -v aws >/dev/null 2>&1; then
  export PATH="$PATH:/c/Program Files/Amazon/AWSCLIV2"
fi

cd "$(dirname "$0")/../tf/infra"

step() { echo; echo "==> $*"; }

###############################################################################
# 1. Clean up inside the cluster (only if the cluster still exists)
###############################################################################
if aws eks describe-cluster --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

  step "Stop Argo CD from recreating the app"
  kubectl delete applications.argoproj.io --all -n argocd --ignore-not-found --wait=true || true

  step "Delete every LoadBalancer Service, so the controller deletes its NLB"
  kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' |
    while read -r ns name; do
      [ -n "$name" ] && kubectl delete svc "$name" -n "$ns" --wait=true --timeout=5m || true
    done

  step "Delete the monitoring stack's workloads and disks (PVCs), so the EBS volumes are deleted"
  kubectl delete prometheus,alertmanager --all -n monitoring --ignore-not-found --wait=true || true
  # ECK deletes the Elasticsearch pod and its disk when the Elasticsearch object is deleted.
  kubectl delete kibana,elasticsearch --all -A --ignore-not-found --wait=true 2>/dev/null || true
  kubectl delete deployment,statefulset --all -n monitoring --ignore-not-found --wait=true || true
  kubectl delete pvc --all -A --wait=true --timeout=5m || true
  kubectl wait --for=delete pv --all --timeout=5m 2>/dev/null || true

  step "Delete the Karpenter NodePool, so Karpenter terminates its EC2 nodes"
  kubectl delete deployment inflate -n default --ignore-not-found || true
  kubectl delete nodepools.karpenter.sh --all --ignore-not-found --wait=false || true
  kubectl wait --for=delete nodeclaims.karpenter.sh --all --timeout=10m 2>/dev/null || true
else
  step "Cluster $CLUSTER not found, skipping the in-cluster cleanup"
fi

###############################################################################
# 2. Remove access keys a human added by hand (AWS refuses to delete a user that has keys)
###############################################################################
step "Delete hand-made access keys of the IAM user $JENKINS_USER (if any)"
for key in $(aws iam list-access-keys --user-name "$JENKINS_USER" --query "AccessKeyMetadata[].AccessKeyId" --output text 2>/dev/null || true); do
  if [ "$key" != "None" ]; then
    aws iam delete-access-key --user-name "$JENKINS_USER" --access-key-id "$key"
    echo "deleted $key"
  fi
done

###############################################################################
# 3. Terraform destroy
###############################################################################
step "terraform destroy"
terraform destroy -auto-approve

###############################################################################
# 4. Remove anything still left over
###############################################################################
step "Leftover load balancers of $CLUSTER"
for arn in $(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[].LoadBalancerArn" --output text); do
  if aws elbv2 describe-tags --region "$REGION" --resource-arns "$arn" \
       --query "TagDescriptions[].Tags[?Key=='elbv2.k8s.aws/cluster' && Value=='$CLUSTER'][]" --output text | grep -q .; then
    aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$arn" && echo "deleted $arn"
  fi
done

step "Leftover EBS volumes made for $CLUSTER (unattached only)"
for vol in $(aws ec2 describe-volumes --region "$REGION" \
    --filters "Name=status,Values=available" "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" \
    --query "Volumes[].VolumeId" --output text); do
  aws ec2 delete-volume --region "$REGION" --volume-id "$vol" && echo "deleted $vol"
done

step "Leftover EC2 instances started by Karpenter"
for id in $(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag-key,Values=karpenter.sh/nodepool" "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" --output text); do
  aws ec2 terminate-instances --region "$REGION" --instance-ids "$id" >/dev/null && echo "terminated $id"
done

step "Leftover EKS log group (EKS can recreate it after Terraform deletes it)"
aws logs delete-log-group --region "$REGION" --log-group-name "/aws/eks/$CLUSTER/cluster" 2>/dev/null && echo "deleted" || echo "none"

echo
echo "Done. Everything in tf/infra is destroyed. The S3 state bucket is kept for the next apply."
