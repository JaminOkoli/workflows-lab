# Not run directly - "source" this in any new terminal to reload the
# shell variables used throughout infra/setup.md, instead of retyping them.
#
#   source infra/env.sh
#
export PROJECT_ID="lumi-project-89263"
export REGION="us-central1"
export ZONE="us-central1-a"
export GITHUB_REPO="JaminOkoli/workflows-lab"
export AR_REPO="workflows-lab"
export SA_NAME="github-actions-deployer"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export VM_NAME="workflows-lab-vm"

gcloud config set project "$PROJECT_ID" >/dev/null

echo "Loaded: PROJECT_ID=$PROJECT_ID  REGION=$REGION  ZONE=$ZONE  VM_NAME=$VM_NAME"
