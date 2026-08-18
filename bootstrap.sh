#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# URL Shortener EKS bootstrap
# From an existing Terraform-created EKS cluster
# through AWS controllers, app, HPA, Prometheus and Grafana.
#
# Assumptions:
#   - Terraform already created the VPC and EKS cluster.
#   - This script is run from the repository root.
#   - kubernetes/base/ contains the application manifests.
#   - app/ contains Dockerfile, app.py and requirements.txt.
#
# Optional overrides:
#   AWS_REGION=us-east-1
#   CLUSTER_NAME=url-shortener-cluster
#   EXPECTED_ACCOUNT_ID=499140333057
#   ECR_REPO=url-shortener
#   APP_IMAGE_TAG=v1
#   LBC_CHART_VERSION=1.14.0
# ============================================================

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-url-shortener-cluster}"
EXPECTED_ACCOUNT_ID="${EXPECTED_ACCOUNT_ID:-381491944316}"
ECR_REPO="${ECR_REPO:-url-shortener}"
APP_IMAGE_TAG="${APP_IMAGE_TAG:-v4}"
LBC_CHART_VERSION="${LBC_CHART_VERSION:-1.14.0}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

LBC_ROLE="AmazonEKSLoadBalancerControllerRole"
LBC_POLICY="AWSLoadBalancerControllerIAMPolicy"
EBS_ROLE="AmazonEKS_EBS_CSI_DriverRole"
EBS_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriiverPolicy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { echo -e "\n\033[1;34m==> $*\033[0m"; }
ok()   { echo -e "\033[1;32mOK:\033[0m $*"; }
warn() { echo -e "\033[1;33mWARN:\033[0m $*"; }
die()  { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }

trap 'die "Failed at line $LINENO: $BASH_COMMAND"' ERR

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not installed."
}

wait_for() {
  local description="$1"
  shift
  log "$description"
  for _ in {1..60}; do
    if "$@" >/dev/null 2>&1; then
      ok "$description"
      return 0
    fi
    sleep 5
  done
  die "Timed out: $description"
}

# ------------------------------------------------------------
# 0. Preflight
# ------------------------------------------------------------
log "Preflight checks"

for cmd in aws eksctl kubectl helm docker curl; do
  require_cmd "$cmd"
done

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[[ "$ACCOUNT_ID" == "$EXPECTED_ACCOUNT_ID" ]] || \
  die "AWS account mismatch. Expected $EXPECTED_ACCOUNT_ID, got $ACCOUNT_ID."

aws sts get-caller-identity >/dev/null

CLUSTER_STATUS="$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.status' \
  --output text)"

[[ "$CLUSTER_STATUS" == "ACTIVE" ]] || \
  die "EKS cluster $CLUSTER_NAME is not ACTIVE. Current status: $CLUSTER_STATUS."

aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" >/dev/null

kubectl cluster-info >/dev/null
kubectl get nodes

VPC_ID="$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)"

K8S_VERSION="$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.version' \
  --output text)"

OIDC_ISSUER="$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.identity.oidc.issuer' \
  --output text)"

[[ "$VPC_ID" != "None" && "$VPC_ID" != "null" ]] || die "Could not determine VPC ID."
[[ "$OIDC_ISSUER" != "None" && "$OIDC_ISSUER" != "null" ]] || die "Cluster has no OIDC issuer."

ok "Account=$ACCOUNT_ID Cluster=$CLUSTER_NAME Kubernetes=$K8S_VERSION VPC=$VPC_ID"

# ------------------------------------------------------------
# 1. OIDC provider
# ------------------------------------------------------------
log "Ensure IAM OIDC provider exists"

OIDC_ID="${OIDC_ISSUER##*/}"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}"

if aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  ok "OIDC provider already exists"
else
  eksctl utils associate-iam-oidc-provider \
    --cluster "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --approve
  ok "OIDC provider created"
fi


# ------------------------------------------------------------
# 2. AWS Load Balancer Controller IAM
# ------------------------------------------------------------
log "Prepare AWS Load Balancer Controller IAM policy"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

LBC_POLICY_FILE="$SCRIPT_DIR/kubernetes/base/iam_policy.json"

if [[ -f "$LBC_POLICY_FILE" ]]; then
    ok "Using existing AWS Load Balancer Controller IAM policy"
else
    die "AWS Load Balancer Controller IAM policy not found: $LBC_POLICY_FILE"
fi

if aws iam get-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${LBC_POLICY}" >/dev/null 2>&1; then
  ok "LBC IAM policy already exists"
else
  aws iam create-policy \
    --policy-name "$LBC_POLICY" \
    --policy-document "file://${LBC_POLICY_FILE}" >/dev/null
  ok "LBC IAM policy created"
fi

log "Prepare AWS Load Balancer Controller service account"

if aws iam get-role --role-name "$LBC_ROLE" >/dev/null 2>&1; then
  ok "LBC IAM role already exists"
else
  eksctl create iamserviceaccount \
    --cluster="$CLUSTER_NAME" \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn="arn:aws:iam::${ACCOUNT_ID}:policy/${LBC_POLICY}" \
    --region="$AWS_REGION" \
    --override-existing-serviceaccounts \
    --approve

  ok "LBC IAM role and service account created"
fi

# If the role already existed, make sure its policy is attached.
aws iam attach-role-policy \
  --role-name "$LBC_ROLE" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${LBC_POLICY}" >/dev/null 2>&1 || true

# ------------------------------------------------------------
# 3. AWS Load Balancer Controller
# ------------------------------------------------------------
log "Install/upgrade AWS Load Balancer Controller"

helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null

helm upgrade --install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version "$LBC_CHART_VERSION" \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --wait \
  --timeout 5m

kubectl rollout status deployment/aws-load-balancer-controller \
  -n kube-system \
  --timeout=5m

LBC_READY="$(kubectl get deployment aws-load-balancer-controller \
  -n kube-system \
  -o jsonpath='{.status.readyReplicas}')"

[[ "${LBC_READY:-0}" -ge 1 ]] || die "AWS Load Balancer Controller is not ready."
ok "AWS Load Balancer Controller is healthy"

# ------------------------------------------------------------
# 4. EBS CSI IAM role
# ------------------------------------------------------------
log "Prepare EBS CSI IAM role"

EBS_ROLE="AmazonEKS_EBS_CSI_DriverRole"
EBS_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
EBS_SA_NAME="ebs-csi-controller-sa"
EBS_NAMESPACE="kube-system"

# Verify the correct AWS-managed EBS CSI policy exists.
# IMPORTANT: Do NOT use AmazonEBSCSIDriverPolicyV2.
log "Verify EBS CSI managed policy exists"

if ! aws iam get-policy \
  --policy-arn "$EBS_POLICY_ARN" \
  --query 'Policy.Arn' \
  --output text >/dev/null 2>&1; then
  die "Required EBS CSI managed policy is unavailable: $EBS_POLICY_ARN"
fi

# Get the EKS OIDC issuer.
OIDC_ISSUER="$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.identity.oidc.issuer' \
  --output text)"

[[ -n "$OIDC_ISSUER" && "$OIDC_ISSUER" != "None" ]] || \
  die "EKS cluster does not have an OIDC issuer."

OIDC_PROVIDER="${OIDC_ISSUER#https://}"
OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"

# Verify the IAM OIDC provider exists.
log "Verify IAM OIDC provider exists"

if ! aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null 2>&1; then
  die "IAM OIDC provider is missing: $OIDC_PROVIDER_ARN"
fi

# Create the trust policy for:
# system:serviceaccount:kube-system:ebs-csi-controller-sa
EBS_TRUST_FILE="$(mktemp)"

cat > "$EBS_TRUST_FILE" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${EBS_NAMESPACE}:${EBS_SA_NAME}"
        }
      }
    }
  ]
}
EOF

cleanup_ebs_trust() {
  rm -f "$EBS_TRUST_FILE"
}

trap cleanup_ebs_trust EXIT

# Create or repair the IAM role.
if aws iam get-role \
  --role-name "$EBS_ROLE" \
  --query 'Role.Arn' \
  --output text >/dev/null 2>&1; then

  ok "EBS CSI IAM role already exists"

  # Make sure the trust relationship is correct.
  aws iam update-assume-role-policy \
    --role-name "$EBS_ROLE" \
    --policy-document "file://$EBS_TRUST_FILE"

else

  log "Creating EBS CSI IAM role"

  aws iam create-role \
    --role-name "$EBS_ROLE" \
    --assume-role-policy-document "file://$EBS_TRUST_FILE" \
    --description "IAM role for Amazon EKS EBS CSI driver"

  ok "EBS CSI IAM role created"
fi

# Attach the correct AWS-managed policy.
log "Attach/verify EBS CSI managed policy"

aws iam attach-role-policy \
  --role-name "$EBS_ROLE" \
  --policy-arn "$EBS_POLICY_ARN" \
  --region "$AWS_REGION" >/dev/null 2>&1 || true

EBS_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${EBS_ROLE}"

# IAM is eventually consistent.
# Do not create the EKS addon until the role and policy are visible.
EBS_ROLE_READY=false

for attempt in {1..24}; do

  ROLE_ARN_CHECK="$(aws iam get-role \
    --role-name "$EBS_ROLE" \
    --query 'Role.Arn' \
    --output text 2>/dev/null || true)"

  POLICY_CHECK="$(aws iam list-attached-role-policies \
    --role-name "$EBS_ROLE" \
    --query "AttachedPolicies[?PolicyArn=='${EBS_POLICY_ARN}'].PolicyArn" \
    --output text 2>/dev/null || true)"

  if [[ "$ROLE_ARN_CHECK" == "$EBS_ROLE_ARN" &&
        "$POLICY_CHECK" == "$EBS_POLICY_ARN" ]]; then
    EBS_ROLE_READY=true
    break
  fi

  log "Waiting for EBS IAM role/policy propagation... attempt $attempt/24"
  sleep 5
done

[[ "$EBS_ROLE_READY" == "true" ]] || \
  die "EBS CSI IAM role or policy was not verifiably ready after waiting."

ok "EBS CSI IAM role verified: $EBS_ROLE_ARN"


# ------------------------------------------------------------
# 5. EBS CSI addon
# ------------------------------------------------------------
log "Install/repair AWS EBS CSI addon"

EBS_ADDON="aws-ebs-csi-driver"

ADDON_EXISTS=false
ADDON_STATUS=""

# Check whether the addon already exists.
if aws eks describe-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name "$EBS_ADDON" \
  --region "$AWS_REGION" >/dev/null 2>&1; then

  ADDON_EXISTS=true

  ADDON_STATUS="$(aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$EBS_ADDON" \
    --region "$AWS_REGION" \
    --query 'addon.status' \
    --output text)"
fi


# ------------------------------------------------------------
# Repair an existing broken addon
# ------------------------------------------------------------

if [[ "$ADDON_EXISTS" == "true" ]]; then

  EXISTING_ROLE_ARN="$(aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$EBS_ADDON" \
    --region "$AWS_REGION" \
    --query 'addon.serviceAccountRoleArn' \
    --output text 2>/dev/null || true)"

  log "Existing EBS CSI addon status: $ADDON_STATUS"

  # Detect the exact failure we experienced:
  #
  # EKS addon references:
  #   AmazonEKS_EBS_CSI_DriverRole
  #
  # But IAM role was deleted.
  #
  # In this situation the addon gets stuck in CREATING and the
  # EBS controller enters CrashLoopBackOff.
  if [[ -n "$EXISTING_ROLE_ARN" &&
        "$EXISTING_ROLE_ARN" != "None" ]]; then

    if ! aws iam get-role \
      --role-name "${EXISTING_ROLE_ARN##*/}" \
      --query 'Role.Arn' \
      --output text >/dev/null 2>&1; then

      warn "EBS CSI addon references missing IAM role: $EXISTING_ROLE_ARN"
      warn "Deleting the broken addon before recreating it with the verified role."

      aws eks delete-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name "$EBS_ADDON" \
        --region "$AWS_REGION" >/dev/null

      # Wait until AWS completely removes the addon.
      for attempt in {1..36}; do

        if ! aws eks describe-addon \
          --cluster-name "$CLUSTER_NAME" \
          --addon-name "$EBS_ADDON" \
          --region "$AWS_REGION" >/dev/null 2>&1; then
          break
        fi

        log "Waiting for broken EBS CSI addon deletion... attempt $attempt/36"
        sleep 5
      done

      if aws eks describe-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name "$EBS_ADDON" \
        --region "$AWS_REGION" >/dev/null 2>&1; then

        die "Broken EBS CSI addon could not be deleted."
      fi

      ADDON_EXISTS=false
      ADDON_STATUS=""
    fi
  fi
fi


# ------------------------------------------------------------
# Handle existing addon status
# ------------------------------------------------------------

if [[ "$ADDON_EXISTS" == "true" ]]; then

  case "$ADDON_STATUS" in

    ACTIVE)

      # ACTIVE addon must use our verified role.
      if [[ "${EXISTING_ROLE_ARN:-}" != "$EBS_ROLE_ARN" ]]; then

        warn "EBS CSI addon uses role ${EXISTING_ROLE_ARN:-<none>}"
        warn "Updating addon to verified role $EBS_ROLE_ARN"

        aws eks update-addon \
          --cluster-name "$CLUSTER_NAME" \
          --addon-name "$EBS_ADDON" \
          --region "$AWS_REGION" \
          --service-account-role-arn "$EBS_ROLE_ARN" \
          --resolve-conflicts OVERWRITE >/dev/null

      else

        ok "EBS CSI addon is already ACTIVE with the verified IAM role"

      fi
      ;;


    CREATING|UPDATING)

      # IAM role has already been verified.
      # Therefore, wait instead of starting another addon operation.
      log "EBS CSI addon is $ADDON_STATUS. Waiting for it to finish."
      ;;


    CREATE_FAILED|DEGRADED|UPDATE_FAILED|DELETE_FAILED)

      warn "Existing EBS CSI addon is in $ADDON_STATUS. Removing it before repair."

      aws eks delete-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name "$EBS_ADDON" \
        --region "$AWS_REGION" >/dev/null

      for attempt in {1..36}; do

        if ! aws eks describe-addon \
          --cluster-name "$CLUSTER_NAME" \
          --addon-name "$EBS_ADDON" \
          --region "$AWS_REGION" >/dev/null 2>&1; then
          break
        fi

        log "Waiting for failed EBS CSI addon deletion... attempt $attempt/36"
        sleep 5
      done

      if aws eks describe-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name "$EBS_ADDON" \
        --region "$AWS_REGION" >/dev/null 2>&1; then

        die "Failed EBS CSI addon could not be removed."
      fi

      ADDON_EXISTS=false
      ;;


    DELETING)

      die "EBS CSI addon is already DELETING. Wait for deletion before rerunning."
      ;;


    *)

      die "Unexpected EBS CSI addon status: $ADDON_STATUS"
      ;;

  esac
fi


# ------------------------------------------------------------
# Create addon if it does not exist
# ------------------------------------------------------------

if [[ "$ADDON_EXISTS" == "false" ]]; then

  log "Creating EBS CSI addon with verified IAM role"

  aws eks create-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$EBS_ADDON" \
    --region "$AWS_REGION" \
    --service-account-role-arn "$EBS_ROLE_ARN" \
    --resolve-conflicts OVERWRITE >/dev/null

fi


# ------------------------------------------------------------
# Wait for ACTIVE
# ------------------------------------------------------------

log "Waiting for EBS CSI addon to become ACTIVE"

EBS_STATUS=""
EBS_ACTIVE=false

for attempt in {1..60}; do

  EBS_STATUS="$(aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$EBS_ADDON" \
    --region "$AWS_REGION" \
    --query 'addon.status' \
    --output text 2>/dev/null || true)"

  case "$EBS_STATUS" in

    ACTIVE)

      EBS_ACTIVE=true
      break
      ;;


    CREATE_FAILED|DEGRADED|UPDATE_FAILED)

      break
      ;;


    *)

      log "EBS CSI addon status: ${EBS_STATUS:-NOT_FOUND}. Waiting... attempt $attempt/60"
      sleep 5
      ;;

  esac

done


# ------------------------------------------------------------
# Diagnostics if addon fails
# ------------------------------------------------------------

if [[ "$EBS_ACTIVE" != "true" ]]; then

  echo
  echo "========== EBS CSI DIAGNOSTICS =========="

  echo "Addon:"

  aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$EBS_ADDON" \
    --region "$AWS_REGION" \
    --query 'addon.{status:status,version:addonVersion,role:serviceAccountRoleArn,health:health}' \
    --output json || true


  echo
  echo "IAM role:"

  aws iam get-role \
    --role-name "$EBS_ROLE" \
    --query 'Role.{Arn:Arn,RoleName:RoleName}' \
    --output json || true


  echo
  echo "Attached IAM policies:"

  aws iam list-attached-role-policies \
    --role-name "$EBS_ROLE" \
    --output table || true


  echo
  echo "ServiceAccount:"

  kubectl get serviceaccount "$EBS_SA_NAME" \
    -n "$EBS_NAMESPACE" \
    -o yaml || true


  echo
  echo "EBS CSI controller pods:"

  kubectl get pods \
    -n "$EBS_NAMESPACE" \
    -l app.kubernetes.io/name=aws-ebs-csi-driver \
    -o wide || true


  echo
  echo "EBS CSI controller logs:"

  kubectl logs \
    -n "$EBS_NAMESPACE" \
    -l app.kubernetes.io/name=aws-ebs-csi-driver \
    --all-containers=true \
    --tail=80 2>/dev/null || true


  echo
  echo "Recent EBS CSI events:"

  kubectl get events \
    -n "$EBS_NAMESPACE" \
    --sort-by='.lastTimestamp' 2>/dev/null \
    | grep -i ebs \
    | tail -30 || true


  echo "=========================================="

  die "EBS CSI addon did not become ACTIVE. Diagnostics printed above."

fi


# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

FINAL_EBS_ROLE_ARN="$(aws eks describe-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name "$EBS_ADDON" \
  --region "$AWS_REGION" \
  --query 'addon.serviceAccountRoleArn' \
  --output text)"

[[ "$FINAL_EBS_ROLE_ARN" == "$EBS_ROLE_ARN" ]] || \
  die "EBS CSI addon is ACTIVE but references unexpected IAM role: $FINAL_EBS_ROLE_ARN"


# Verify Kubernetes CSI driver exists.
kubectl get csidriver ebs.csi.aws.com >/dev/null 2>&1 || \
  die "EBS CSI addon is ACTIVE but ebs.csi.aws.com CSIDriver is missing."


# Verify EBS CSI controller has an available replica.
EBS_CONTROLLER_AVAILABLE="$(kubectl get deployment \
  ebs-csi-controller \
  -n kube-system \
  -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"

[[ "${EBS_CONTROLLER_AVAILABLE:-0}" -ge 1 ]] || \
  die "EBS CSI addon is ACTIVE but the controller deployment has no available replicas."


ok "EBS CSI addon is ACTIVE, role is verified, and controller is available"

kubectl get pods -n kube-system | grep ebs-csi || true

# ------------------------------------------------------------
# Check gp2 StorageClass
# ------------------------------------------------------------
log "Check gp2 StorageClass"

GP2_PROVISIONER=""
GP2_EXISTS=false

if kubectl get storageclass gp2 >/dev/null 2>&1; then
    GP2_EXISTS=true

    GP2_PROVISIONER="$(kubectl get storageclass gp2 \
        -o jsonpath='{.provisioner}')"

    ok "gp2 StorageClass already exists"
else
    log "gp2 StorageClass does not exist"
fi


if [[ "$GP2_EXISTS" == "true" &&
      "$GP2_PROVISIONER" == "ebs.csi.aws.com" ]]; then

    ok "gp2 uses AWS EBS CSI provisioner"

elif [[ "$GP2_EXISTS" == "true" &&
        "$GP2_PROVISIONER" == "kubernetes.io/aws-ebs" ]]; then

    warn "gp2 uses legacy in-tree AWS EBS provisioner"

    GP2_PVC_COUNT="$(kubectl get pvc -A \
        -o jsonpath='{range .items[?(@.spec.storageClassName=="gp2")]}x{end}' \
        | wc -c)"

    if [[ "$GP2_PVC_COUNT" -gt 0 ]]; then
        die "gp2 is used by existing PVCs. Refusing to delete StorageClass automatically."
    fi

    log "No PVCs use gp2. Recreating it with EBS CSI provisioner."

    kubectl delete storageclass gp2

    # Wait until deletion completes.
    for attempt in {1..30}; do
        if ! kubectl get storageclass gp2 >/dev/null 2>&1; then
            break
        fi

        sleep 2
    done

    if kubectl get storageclass gp2 >/dev/null 2>&1; then
        die "Failed to delete legacy gp2 StorageClass."
    fi

    cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
provisioner: ebs.csi.aws.com
parameters:
  type: gp2
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

    ok "gp2 recreated using EBS CSI"

else

    log "Creating gp2 StorageClass using EBS CSI"

    cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
provisioner: ebs.csi.aws.com
parameters:
  type: gp2
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

    ok "gp2 StorageClass created"
fi


# Final verification
FINAL_GP2_PROVISIONER="$(kubectl get storageclass gp2 \
    -o jsonpath='{.provisioner}')"

[[ "$FINAL_GP2_PROVISIONER" == "ebs.csi.aws.com" ]] || \
    die "gp2 exists but uses unexpected provisioner: $FINAL_GP2_PROVISIONER"

ok "gp2 StorageClass verified with EBS CSI provisioner"


# ------------------------------------------------------------
# 7. ECR + application image
# ------------------------------------------------------------
log "Prepare ECR repository"

if aws ecr describe-repositories \
  --repository-names "$ECR_REPO" \
  --region "$AWS_REGION" >/dev/null 2>&1; then

  ok "ECR repository already exists"

else

  log "ECR repository does not exist. Creating it."

  aws ecr create-repository \
    --repository-name "$ECR_REPO" \
    --region "$AWS_REGION" >/dev/null

  ok "ECR repository created"

fi

ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_IMAGE="${ECR_REGISTRY}/${ECR_REPO}:${APP_IMAGE_TAG}"


# ------------------------------------------------------------
# 8. Validate application
# ------------------------------------------------------------
log "Validate application"

[[ -f app/app.py ]] || die "app/app.py not found."
[[ -f app/requirements.txt ]] || die "app/requirements.txt not found."
[[ -f app/Dockerfile ]] || die "app/Dockerfile not found."

grep -q "prometheus_flask_exporter" app/requirements.txt || \
  die "prometheus_flask_exporter is missing from app/requirements.txt."

grep -q "PrometheusMetrics" app/app.py || \
  die "PrometheusMetrics import/initialization is missing from app/app.py."

grep -q "PrometheusMetrics(app)" app/app.py || \
  die "PrometheusMetrics(app) is missing from app/app.py."

ok "Application validation passed"


# ------------------------------------------------------------
# 9. Build application image
# ------------------------------------------------------------
log "Build application image"

docker build \
  -t "${ECR_REPO}:${APP_IMAGE_TAG}" \
  -f app/Dockerfile \
  .

ok "Application image built"


# ------------------------------------------------------------
# 10. Authenticate and push to ECR
# ------------------------------------------------------------
log "Authenticate Docker to ECR"

aws ecr get-login-password \
  --region "$AWS_REGION" |
  docker login \
    --username AWS \
    --password-stdin "$ECR_REGISTRY" >/dev/null

ok "Docker authenticated to ECR"

docker tag \
  "${ECR_REPO}:${APP_IMAGE_TAG}" \
  "$ECR_IMAGE"

log "Push application image to ECR"

docker push "$ECR_IMAGE"

ok "Application image pushed: $ECR_IMAGE"


# ------------------------------------------------------------
# Apply application manifests
# ------------------------------------------------------------
log "Prepare application namespace"

if kubectl get namespace url-shortener >/dev/null 2>&1; then
    ok "Namespace url-shortener already exists"
else
    kubectl create namespace url-shortener
    ok "Namespace url-shortener created"
fi

kubectl get namespace url-shortener >/dev/null 2>&1 || \
    die "Namespace url-shortener was not created"

log "Apply application manifests"

kubectl apply -f kubernetes/base/postgres.yml
kubectl apply -f kubernetes/base/app.yml
kubectl apply -f kubernetes/base/hpa.yml
kubectl apply -f kubernetes/base/ingress.yml
kubectl apply -f kubernetes/base/network-policy.yml


ok "Application manifests applied"

log "Verify application prerequisites"

# PostgreSQL
kubectl wait \
  --for=condition=Available \
  deployment/postgres-deployment \
  -n url-shortener \
  --timeout=5m

# URL shortener deployment
kubectl wait \
  --for=condition=Available \
  deployment/url-shortener-deployment \
  -n url-shortener \
  --timeout=5m

# Service port validation
log "Verify url-shortener service port"

SERVICE_PORT=$(kubectl get service url-shortener-service \
  -n url-shortener \
  -o jsonpath='{.spec.ports[?(@.name=="http")].port}')

SERVICE_TARGET_PORT=$(kubectl get service url-shortener-service \
  -n url-shortener \
  -o jsonpath='{.spec.ports[?(@.name=="http")].targetPort}')

if [[ "$SERVICE_PORT" != "8080" ]]; then
    die "url-shortener-service HTTP port is ${SERVICE_PORT}, expected 8080"
fi

if [[ "$SERVICE_TARGET_PORT" != "8080" ]]; then
    die "url-shortener-service targetPort is ${SERVICE_TARGET_PORT}, expected 8080"
fi

ok "Service HTTP port 8080 -> targetPort 8080"


# Service metrics port validation
log "Verify metrics endpoint uses service port 8080"

METRICS_SERVICE_PORT=$(kubectl get service url-shortener-service \
  -n url-shortener \
  -o jsonpath='{.spec.ports[?(@.name=="http")].port}')

if [[ "$METRICS_SERVICE_PORT" != "8080" ]]; then
    die "Metrics endpoint service port is ${METRICS_SERVICE_PORT}, expected 8080"
fi

ok "Metrics endpoint uses service port 8080"


# Existing rollout status
kubectl rollout status deployment/url-shortener-deployment \
  -n url-shortener \
  --timeout=5m


# Verify deployed application exposes /metrics
log "Verify deployed application exposes /metrics"

kubectl exec -n url-shortener \
  deployment/url-shortener-deployment \
  -- python -c \
  "from app import app; assert any(str(r) == '/metrics' for r in app.url_map.iter_rules()), 'Missing /metrics route'"

ok "Deployed application contains /metrics endpoint"


# Verify application metrics endpoint
log "Verify application metrics endpoint"

METRICS_OK=false

for attempt in {1..12}; do
    if kubectl run metrics-preflight \
        -n url-shortener \
        --rm -i \
        --restart=Never \
        --image=curlimages/curl \
        -- curl -fsS \
        http://url-shortener-service:8080/metrics \
        >/dev/null 2>&1; then

        METRICS_OK=true
        break
    fi

    log "Metrics endpoint not ready yet, attempt ${attempt}/12"
    sleep 5
done

if [[ "$METRICS_OK" != "true" ]]; then
    die "Application /metrics endpoint is not reachable"
fi



# ------------------------------------------------------------
# 12. Verify ALB / Ingress
# ------------------------------------------------------------
log "Verify application Ingress and ALB"

if kubectl get ingress url-shortener-ingress -n url-shortener >/dev/null 2>&1; then

  # Wait for ALB hostname
  ALB_HOST=""

  for attempt in {1..60}; do
    ALB_HOST="$(kubectl get ingress url-shortener-ingress \
      -n url-shortener \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
      2>/dev/null || true)"

    if [[ -n "$ALB_HOST" ]]; then
      break
    fi

    log "Waiting for ALB hostname, attempt ${attempt}/60"
    sleep 5
  done

  [[ -n "$ALB_HOST" ]] || \
    die "Ingress exists but ALB hostname was not assigned."

  ok "ALB hostname assigned: $ALB_HOST"

  # Wait for ALB /health
  ALB_HEALTH_OK=false

  for attempt in {1..20}; do
    if curl -fsS \
      --max-time 10 \
      "http://${ALB_HOST}/health" \
      >/dev/null 2>&1; then

      ALB_HEALTH_OK=true
      break
    fi

    log "ALB /health not ready yet, attempt ${attempt}/20"
    sleep 10
  done

  if [[ "$ALB_HEALTH_OK" != "true" ]]; then
    die "ALB exists but /health is not returning success."
  fi

  ok "ALB /health is responding successfully"

else
  log "No application Ingress found, skipping ALB verification"
fi


# ------------------------------------------------------------
# 13. Metrics Server for HPA
# ------------------------------------------------------------
log "Install Metrics Server"

kubectl apply -f \
  https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# EKS commonly requires InternalIP preference.
kubectl patch deployment metrics-server \
  -n kube-system \
  --type='json' \
  -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP"}
  ]' 2>/dev/null || true

kubectl rollout status deployment/metrics-server \
  -n kube-system \
  --timeout=5m

for _ in {1..30}; do
  if kubectl top nodes >/dev/null 2>&1; then
    ok "Metrics API is available"
    break
  fi
  sleep 5
done

kubectl top nodes >/dev/null 2>&1 || \
  die "Metrics API is still unavailable."

# HPA manifests, if present.
for f in kubernetes/base/*hpa*.yml kubernetes/base/*hpa*.yaml; do
  [[ -f "$f" ]] && kubectl apply -f "$f"
done

# ------------------------------------------------------------
# 14. Verify HPA
# ------------------------------------------------------------
log "Verify HPA"

if kubectl get hpa url-shortener-hpa -n url-shortener >/dev/null 2>&1; then
  kubectl get hpa -n url-shortener
else
  warn "url-shortener-hpa was not found. Create/apply your HPA manifest before load testing."
fi

# ------------------------------------------------------------
# 15. Install kube-prometheus-stack
# ------------------------------------------------------------
log "Install Prometheus + Grafana"

kubectl get namespace "$MONITORING_NAMESPACE" >/dev/null 2>&1 || \
  kubectl create namespace "$MONITORING_NAMESPACE"

helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true

helm repo update prometheus-community >/dev/null

helm upgrade --install monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace "$MONITORING_NAMESPACE" \
  --set prometheus.prometheusSpec.serviceMonitorSelector.matchLabels.release=monitoring \
  --set-json 'prometheus.prometheusSpec.serviceMonitorNamespaceSelector={}' \
  --wait \
  --timeout 10m

kubectl get pods -n "$MONITORING_NAMESPACE"

# ------------------------------------------------------------
# 16. Apply the application ServiceMonitor after the operator exists
# ------------------------------------------------------------
log "Apply URL shortener ServiceMonitor"

SERVICEMONITOR_FILE="$(find kubernetes/base -maxdepth 1 -type f \
  \( -iname '*servicemonitor*.yml' -o -iname '*servicemonitor*.yaml' \) \
  | head -n1 || true)"

if [[ -n "$SERVICEMONITOR_FILE" ]]; then
  kubectl apply -f "$SERVICEMONITOR_FILE"
else
  cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: url-shortener
  namespace: monitoring
  labels:
    release: monitoring
spec:
  namespaceSelector:
    matchNames:
      - url-shortener
  selector:
    matchLabels:
      app: url-shortener
  endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
EOF
fi

kubectl rollout status deployment/monitoring-grafana \
  -n "$MONITORING_NAMESPACE" \
  --timeout=10m || true

kubectl wait \
  --for=condition=Ready \
  pod -l app.kubernetes.io/name=prometheus \
  -n "$MONITORING_NAMESPACE" \
  --timeout=10m || true

# ------------------------------------------------------------
# 17. Expose Grafana
# ------------------------------------------------------------
log "Expose Grafana as LoadBalancer"

kubectl patch svc monitoring-grafana \
  -n "$MONITORING_NAMESPACE" \
  --type=merge \
  -p '{"spec":{"type":"LoadBalancer"}}' >/dev/null

echo
echo "Waiting for Grafana external address..."
for _ in {1..60}; do
  GRAFANA_ADDRESS="$(kubectl get svc monitoring-grafana \
    -n "$MONITORING_NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

  [[ -n "$GRAFANA_ADDRESS" ]] && break
  sleep 5
done

echo
echo "Grafana address: ${GRAFANA_ADDRESS:-<pending>}"

# ------------------------------------------------------------
# 18. Final verification
# ------------------------------------------------------------
log "Final Prometheus/Grafana verification"

kubectl get pods -n kube-system | grep -E \
  'aws-load-balancer-controller|ebs-csi|metrics-server' || true

kubectl get csidriver ebs.csi.aws.com
kubectl get storageclass
kubectl get pods -n url-shortener
kubectl get svc -n url-shortener
kubectl get pods -n "$MONITORING_NAMESPACE"
kubectl get prometheus -n "$MONITORING_NAMESPACE" 2>/dev/null || true
kubectl get servicemonitor -n "$MONITORING_NAMESPACE" || true

echo
echo "Prometheus target verification:"
echo "  Open Prometheus -> Status -> Targets and confirm url-shortener is UP."
echo "  Or query: up{namespace=\"url-shortener\"}"

echo
echo "============================================================"
echo "BOOTSTRAP COMPLETE"
echo "============================================================"
echo "Cluster:       $CLUSTER_NAME"
echo "AWS Account:   $ACCOUNT_ID"
echo "Region:        $AWS_REGION"
echo "VPC:           $VPC_ID"
echo "ECR image:     $ECR_IMAGE"
echo "Grafana:       ${GRAFANA_ADDRESS:-pending}"
echo
echo "Next manual checks:"
echo "  kubectl top nodes"
echo "  kubectl get hpa -n url-shortener"
echo "  kubectl get servicemonitor -n monitoring"
echo "  kubectl get pods -n monitoring"
echo "  kubectl get prometheus -n monitoring"
echo
echo "Then verify Prometheus target:"
echo "  Prometheus -> Status -> Targets -> url-shortener -> UP"
echo "============================================================"
