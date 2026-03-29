#!/bin/bash
set -euo pipefail

# ─── Colors ────────────────────────────────────────────────────────────────────
BLACK=`tput setaf 0`; RED=`tput setaf 1`; GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`; BLUE=`tput setaf 4`; MAGENTA=`tput setaf 5`; CYAN=`tput setaf 6`
BG_RED=`tput setab 1`; BG_GREEN=`tput setab 2`; BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`; BG_MAGENTA=`tput setab 5`; BG_CYAN=`tput setab 6`
BOLD=`tput bold`; RESET=`tput sgr0`

TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

clear
echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}Starting Execution${RESET}"

# ─── Step 1: Environment Variables ────────────────────────────────────────────
echo "${BOLD}${GREEN}Step 1: Setting environment variables${RESET}"
export PROCESSOR_NAME=form-processor
export PROJECT_ID=$(gcloud config get-value core/project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export GEO_CODE_REQUEST_PUBSUB_TOPIC=geocode_request
export BUCKET_LOCATION=$REGION
export CLOUD_FUNCTION_LOCATION=$REGION

echo "${CYAN}Project: $PROJECT_ID | Region: $REGION${RESET}"

# ─── Step 2: Enable APIs (parallel) ───────────────────────────────────────────
echo "${BOLD}${BLUE}Step 2: Enabling required APIs${RESET}"
gcloud services enable \
  documentai.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  geocoding-backend.googleapis.com &
API_ENABLE_PID=$!

# ─── Step 3: Create GCS Buckets (parallel) ────────────────────────────────────
echo "${BOLD}${YELLOW}Step 3: Creating GCS buckets${RESET}"
for BUCKET in input-invoices output-invoices archived-invoices; do
  gsutil mb -c standard -l ${BUCKET_LOCATION} -b on \
    gs://${PROJECT_ID}-${BUCKET} 2>/dev/null || echo "Bucket ${BUCKET} already exists, skipping."
done

# Wait for APIs to finish enabling
wait $API_ENABLE_PID
echo "${GREEN}APIs enabled.${RESET}"

# ─── Step 4: Create & Restrict API Key ────────────────────────────────────────
echo "${BOLD}${MAGENTA}Step 4: Creating and restricting API key${RESET}"
gcloud alpha services api-keys create --display-name="awesome" --quiet

export KEY_NAME=$(gcloud alpha services api-keys list \
  --format="value(name)" --filter="displayName=awesome" --limit=1)
export API_KEY=$(gcloud alpha services api-keys get-key-string $KEY_NAME \
  --format="value(keyString)")

curl -s -X PATCH \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "restrictions": {
      "apiTargets": [{"service": "geocoding-backend.googleapis.com"}]
    }
  }' \
  "https://apikeys.googleapis.com/v2/$KEY_NAME?updateMask=restrictions" > /dev/null

echo "${GREEN}API key created and restricted.${RESET}"

# ─── Step 5: Copy Demo Assets ─────────────────────────────────────────────────
echo "${BOLD}${CYAN}Step 5: Copying demo assets${RESET}"
mkdir -p ~/documentai-pipeline-demo
gcloud storage cp -r \
  gs://spls/gsp927/documentai-pipeline-demo/* \
  ~/documentai-pipeline-demo/

# ─── Step 6: Create Document AI Processor ─────────────────────────────────────
echo "${BOLD}${YELLOW}Step 6: Creating Document AI Processor${RESET}"
PROCESSOR_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d "{\"display_name\": \"$PROCESSOR_NAME\", \"type\": \"FORM_PARSER_PROCESSOR\"}" \
  "https://documentai.googleapis.com/v1/projects/$PROJECT_ID/locations/us/processors")

export PROCESSOR_ID=$(echo $PROCESSOR_RESPONSE | jq -r '.name | split("/") | last')
echo "${GREEN}Processor ID: $PROCESSOR_ID${RESET}"

# ─── Step 7: BigQuery Setup ────────────────────────────────────────────────────
echo "${BOLD}${BLUE}Step 7: Creating BigQuery dataset and tables${RESET}"
bq --location="US" mk -d --description "Form Parser Results" \
  ${PROJECT_ID}:invoice_parser_results 2>/dev/null || echo "Dataset already exists."

cd ~/documentai-pipeline-demo/scripts/table-schema/
bq mk --table invoice_parser_results.doc_ai_extracted_entities \
  doc_ai_extracted_entities.json 2>/dev/null || true
bq mk --table invoice_parser_results.geocode_details \
  geocode_details.json 2>/dev/null || true

# ─── Step 8: Pub/Sub Topic ─────────────────────────────────────────────────────
echo "${BOLD}${MAGENTA}Step 8: Creating Pub/Sub topic${RESET}"
gcloud pubsub topics create ${GEO_CODE_REQUEST_PUBSUB_TOPIC} 2>/dev/null || \
  echo "Topic already exists."

# ─── Step 9: Service Account & IAM ────────────────────────────────────────────
echo "${BOLD}${CYAN}Step 9: Setting up service account and IAM roles${RESET}"
gcloud iam service-accounts create "service-$PROJECT_NUMBER" \
  --display-name="Cloud Storage Service Account" 2>/dev/null || true

SA_EMAIL="service-$PROJECT_NUMBER@gs-project-accounts.iam.gserviceaccount.com"
for ROLE in roles/pubsub.publisher roles/iam.serviceAccountTokenCreator; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$ROLE" --quiet
done

# ─── Step 10: Update .env.yaml files ──────────────────────────────────────────
echo "${BOLD}${GREEN}Step 10: Updating environment variable files${RESET}"
cd ~/documentai-pipeline-demo/scripts

# Update process-invoices env
cat > cloud-functions/process-invoices/.env.yaml <<EOF
PROCESSOR_ID: ${PROCESSOR_ID}
PARSER_LOCATION: us
GCP_PROJECT: ${PROJECT_ID}
OUTPUT_BUCKET: ${PROJECT_ID}-output-invoices
GEO_CODE_REQUEST_PUBSUB_TOPIC: ${GEO_CODE_REQUEST_PUBSUB_TOPIC}
EOF

# Update geocode-addresses env
cat > cloud-functions/geocode-addresses/.env.yaml <<EOF
API_key: ${API_KEY}
EOF

# ─── Step 11: Deploy Cloud Functions ──────────────────────────────────────────
deploy_with_retry() {
  local NAME=$1; local ENTRY=$2; local SOURCE=$3
  local TIMEOUT=$4; local TRIGGER_TYPE=$5; local TRIGGER_VALUE=$6

  while true; do
    echo "${BOLD}${YELLOW}Deploying ${NAME}...${RESET}"

    if [[ "$TRIGGER_TYPE" == "bucket" ]]; then
      TRIGGER_ARGS="--trigger-resource=${TRIGGER_VALUE} --trigger-event=google.storage.object.finalize"
    else
      TRIGGER_ARGS="--trigger-topic=${TRIGGER_VALUE}"
    fi

    if gcloud functions deploy "$NAME" \
        --no-gen2 \
        --region="${CLOUD_FUNCTION_LOCATION}" \
        --entry-point="$ENTRY" \
        --runtime=python39 \
        --source="$SOURCE" \
        --timeout="$TIMEOUT" \
        --env-vars-file="${SOURCE}/.env.yaml" \
        $TRIGGER_ARGS; then
      echo "${BOLD}${GREEN}✅ ${NAME} deployed successfully!${RESET}"
      break
    else
      echo "${BOLD}${RED}❌ ${NAME} failed. Retrying in 30s...${RESET}"
      sleep 30
    fi
  done
}

echo "${BOLD}${BLUE}Step 11: Deploying Cloud Functions${RESET}"
deploy_with_retry "process-invoices" "process_invoice" \
  "cloud-functions/process-invoices" "400" \
  "bucket" "gs://${PROJECT_ID}-input-invoices"

deploy_with_retry "geocode-addresses" "process_address" \
  "cloud-functions/geocode-addresses" "60" \
  "topic" "${GEO_CODE_REQUEST_PUBSUB_TOPIC}"

# ─── Step 12: Upload Sample Files ─────────────────────────────────────────────
echo "${BOLD}${CYAN}Step 12: Uploading sample invoice files${RESET}"
gsutil -m cp gs://spls/gsp927/documentai-pipeline-demo/sample-files/* \
  gs://${PROJECT_ID}-input-invoices/

echo "${GREEN}${BOLD}All sample files uploaded. Pipeline triggered!${RESET}"

# ─── Congratulations ──────────────────────────────────────────────────────────
MESSAGES=(
  "${GREEN}Congratulations! Lab completed successfully!${RESET}"
  "${CYAN}Well done! Your hard work paid off!${RESET}"
  "${YELLOW}Amazing job! You've completed the lab!${RESET}"
  "${BLUE}Outstanding! Your dedication brought success!${RESET}"
  "${MAGENTA}Great work! One step closer to mastering this!${RESET}"
)
echo -e "\n${BOLD}${MESSAGES[$RANDOM % ${#MESSAGES[@]}]}\n"

# ─── Cleanup ──────────────────────────────────────────────────────────────────
cd ~
for file in *; do
  if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* ]] && [[ -f "$file" ]]; then
    rm "$file" && echo "Removed: $file"
  fi
done
