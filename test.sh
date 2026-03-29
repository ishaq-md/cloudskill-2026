#!/bin/bash

# Colors for flair
CYAN='\033[0;96m'
GREEN='\033[0;92m'
RESET='\033[0m'

echo "${CYAN}🚀 Starting Document AI Lab Speedrun...${RESET}"

# 1. Setup Environment & Enable API (Task 1)
export PROJECT_ID=$(gcloud config get-value project)
gcloud services enable documentai.googleapis.com --quiet

# 2. Create the 'form-parser' Processor (Task 2)
echo "${GREEN}Creating form-parser processor...${RESET}"
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "form-parser",
    "type": "FORM_PARSER_PROCESSOR"
  }' \
  "https://us-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/us/processors")

export PROCESSOR_ID=$(echo $RESPONSE | jq -r '.name' | sed 's|.*/||')

if [ "$PROCESSOR_ID" == "null" ]; then
    echo "❌ Error: Processor creation failed. Check API permissions."
    exit 1
fi

echo "${CYAN}Processor ID Captured: $PROCESSOR_ID${RESET}"

# 3. Find VM Zone (Task 3)
export ZONE=$(gcloud compute instances list --filter="name:document-ai-dev" --format='value(zone)' | head -n 1)

# 4. Define commands to run INSIDE the VM
REMOTE_COMMANDS=$(cat <<EOF
export PROJECT_ID=$PROJECT_ID
export PROCESSOR_ID=$PROCESSOR_ID
export LOCATION="us"

# --- TASK 3: Authenticate API requests ---
export SA_NAME="document-ai-service-account"
gcloud iam service-accounts create \$SA_NAME --display-name \$SA_NAME --quiet || true

gcloud projects add-iam-policy-binding \${PROJECT_ID} \
  --member="serviceAccount:\$SA_NAME@\${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/documentai.apiUser" --quiet

gcloud iam service-accounts keys create key.json \
  --iam-account \$SA_NAME@\${PROJECT_ID}.iam.gserviceaccount.com --quiet

export GOOGLE_APPLICATION_CREDENTIALS="\$PWD/key.json"

# --- TASK 3 & 4: Download form and prepare JSON ---
gsutil cp gs://spls/gsp924/health-intake-form.pdf .
# Standardize the filename to form.pdf as per Task 2 instructions
cp health
