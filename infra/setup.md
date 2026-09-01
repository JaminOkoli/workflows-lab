# GCP one-time setup

Run these once, in order, from your terminal. Everything here is a plain
`gcloud` command (no Terraform) so the focus stays on GitHub Actions, not
infrastructure-as-code.

We set a few shell variables first so every command below can just refer to
`$PROJECT_ID` etc., instead of you hunting for placeholders to replace.

## 0. Install and log into the gcloud CLI

```bash
brew install --cask google-cloud-sdk
gcloud init
```

`gcloud init` opens a browser to log you in and lets you create or pick a
GCP project interactively. If you'd rather do it by hand, `gcloud auth login`
logs you in without touching project config.

## 1. Set your working variables

Pick a **globally unique** project ID (GCP project IDs are unique across all
of GCP, not just your account) and a region/zone near you.

```bash
export PROJECT_ID="workflows-lab-$RANDOM"   # e.g. workflows-lab-14821 - change if you like
export REGION="us-central1"
export ZONE="us-central1-a"
export REPO_NAME="workflows-lab"                     # GitHub org/user + repo
export GITHUB_REPO="JaminOkoli/workflows-lab"          # must match exactly
export AR_REPO="workflows-lab"                          # Artifact Registry repo name
export SA_NAME="github-actions-deployer"
export VM_NAME="workflows-lab-vm"
```

## 2. Create the project and link billing

```bash
gcloud projects create "$PROJECT_ID" --name="workflows-lab"
gcloud config set project "$PROJECT_ID"

# List your billing accounts, then link one (needed before any resource works):
gcloud billing accounts list
gcloud billing projects link "$PROJECT_ID" --billing-account=<BILLING_ACCOUNT_ID>
```

## 3. Enable the APIs we need

```bash
gcloud services enable \
  artifactregistry.googleapis.com \
  compute.googleapis.com \
  iamcredentials.googleapis.com \
  iap.googleapis.com \
  --project="$PROJECT_ID"
```

## 4. Create the Artifact Registry Docker repo

This is where `build-and-push.yml` pushes images to.

```bash
gcloud artifacts repositories create "$AR_REPO" \
  --project="$PROJECT_ID" \
  --repository-format=docker \
  --location="$REGION" \
  --description="Docker images for workflows-lab"
```

## 5. Create the Compute Engine VM

A small, cheap VM with Docker pre-installed via a startup script. No public
SSH port here on purpose — Stage 4's deploy job connects through an IAP
tunnel instead.

```bash
gcloud compute instances create "$VM_NAME" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata=startup-script='#! /bin/bash
apt-get update
apt-get install -y docker.io
systemctl enable docker
systemctl start docker'
```

## 6. Firewall rules

Two separate rules, on purpose: SSH stays private (IAP only), the app port
is public so you can actually curl it.

```bash
# SSH only from Google's IAP relay range - never from the open internet.
gcloud compute firewall-rules create allow-iap-ssh \
  --project="$PROJECT_ID" \
  --direction=INGRESS \
  --action=allow \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20

# The app's port, open so you (and Stage 4's health checks) can reach it.
gcloud compute firewall-rules create allow-app-port \
  --project="$PROJECT_ID" \
  --direction=INGRESS \
  --action=allow \
  --rules=tcp:8000 \
  --source-ranges=0.0.0.0/0
```

## 7. Create the GitHub Actions service account

This is the identity GitHub Actions will act as - never a human account.

```bash
gcloud iam service-accounts create "$SA_NAME" \
  --project="$PROJECT_ID" \
  --display-name="GitHub Actions Deployer"

export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Least-privilege roles: push images, tunnel SSH via IAP, log into the VM,
# and look up the VM's IP.
for ROLE in roles/artifactregistry.writer roles/iap.tunnelResourceAccessor roles/compute.osLogin roles/compute.viewer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$ROLE"
done
```

## 8. Set up Workload Identity Federation

This is the keyless part: it lets GitHub Actions runs from *this specific
repo* impersonate the service account above, without ever creating or
storing a JSON key.

```bash
# A "pool" is a container for external identities (here, GitHub's).
gcloud iam workload-identity-pools create "github-pool" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# A "provider" inside that pool tells GCP how to trust GitHub's OIDC tokens,
# and the --attribute-condition locks this down to ONLY your repo - any
# other repo's tokens are rejected even if they hit this same provider.
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Actions Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='${GITHUB_REPO}'" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Grant that provider (scoped to your repo) permission to impersonate the
# service account - this is the actual "trust link".
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/${GITHUB_REPO}"
```

## 9. Collect the values GitHub Actions needs

```bash
# The full WIF provider resource name (goes into GitHub as a repo Variable)
gcloud iam workload-identity-pools providers describe "github-provider" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --format="value(name)"

echo "Service account email: $SA_EMAIL"
echo "Project ID: $PROJECT_ID"
echo "Artifact Registry region: $REGION"
echo "Artifact Registry repo: $AR_REPO"
echo "VM name: $VM_NAME   VM zone: $ZONE"
```

None of these values are secret (WIF is specifically designed so nothing
sensitive needs to be stored) - so store them in GitHub as **Variables**,
not Secrets: repo → **Settings → Secrets and variables → Actions → Variables
tab → New repository variable**. Suggested names:

| Variable name | Value |
|---|---|
| `GCP_WIF_PROVIDER` | output of the first command above |
| `GCP_SERVICE_ACCOUNT_EMAIL` | `$SA_EMAIL` |
| `GCP_PROJECT_ID` | `$PROJECT_ID` |
| `GCP_AR_REGION` | `$REGION` |
| `GCP_AR_REPO` | `$AR_REPO` |
| `GCP_VM_NAME` | `$VM_NAME` |
| `GCP_VM_ZONE` | `$ZONE` |

Once these are saved as repo Variables, `build-and-push.yml` (Stage 3) can
be run manually from the Actions tab, passing them in as the workflow's
inputs - and later, `release.yml` (Stage 5) will pass them through
automatically via `vars.*`.
