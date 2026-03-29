#!/bin/bash

# Colors for flair
CYAN='\033[0;96m'
GREEN='\033[0;92m'
RED='\033[0;91m'
RESET='\033[0m'

echo "${CYAN}🚀 Starting Speedrun...${RESET}"

# 1. Setup Environment
export PROJECT_ID=$(gcloud config get-value project)
export LOCATION="us"

# Fix: Ensure we are actually authenticated for the curl call
gcloud auth application-default login --quiet
gcloud services enable documentai.googleapis.com --quiet

# 2. Create Processor and CAPTURE ID
echo "${GREEN}Creating Processor...${RESET}"
# We use -s to silence curl progress and handle potential empty responses
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "lab-form-parser",
    "type": "FORM_PARSER_PROCESSOR"
  }' \
  "https://us-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/us/processors")

export PROCESSOR_ID=$(echo $RESPONSE | jq -r '.name' | sed 's|.*/||')

if [ "$PROCESSOR_ID" == "null" ] || [ -z "$PROCESSOR_ID" ]; then
    echo "${RED}❌ Error: Processor ID is null. Response was: $RESPONSE${RESET}"
    exit 1
fi

echo "${CYAN}Captured Processor ID: $PROCESSOR_ID${RESET}"

# 3. Find Zone
export ZONE=$(gcloud compute instances list --filter="name:document-ai-dev" --format='value(zone)' | head -n 1)

if [ -z "$ZONE" ]; then
    echo "${RED}❌ Error: Could not find zone for document-ai-dev${RESET}"
    exit 1
fi

# 4. Prepare Remote Commands
# Using single quotes for the heredoc to prevent premature local evaluation
REMOTE_COMMANDS=$(cat <<EOF
export PROJECT_ID=$PROJECT_ID
export PROCESSOR_ID=$PROCESSOR_ID
export LOCATION=$LOCATION

# Install dependencies
sudo apt-get update && sudo apt-get install jq -y
python3 -m pip install --upgrade google-cloud-documentai google-cloud-storage prettytable --quiet

# Download Lab Files
gsutil cp gs://spls/gsp924/health-intake-form.pdf .
gsutil cp gs://spls/gsp924/synchronous_doc_ai.py .

# Create Request JSON (Corrected Base64)
echo "{\"rawDocument\": {\"mimeType\": \"application/pdf\",\"content\": \"\$(base64 -w 0 health-intake-form.pdf)\"}}" > request.json

# Run Python Script
python3 synchronous_doc_ai.py \
  --project_id=\$PROJECT_ID \
  --processor_id=\$PROCESSOR_ID \
  --location=\$LOCATION \
  --file_name=health-intake-form.pdf | tee results.txt

# Direct API Call for Verification
curl -s -X POST \
  -H "Authorization: Bearer \$(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d @request.json \
  "https://\$LOCATION-documentai.googleapis.com/v1/projects/\$PROJECT_ID/locations/\$LOCATION/processors/\$PROCESSOR_ID:process" > output.json
EOF
)

# 5. Execute on VM
echo "${GREEN}Executing commands on VM: document-ai-dev in $ZONE...${RESET}"
gcloud compute ssh document-ai-dev --project=$PROJECT_ID --zone=$ZONE --quiet --command="$REMOTE_COMMANDS"

echo "${CYAN}✅ Lab completed. Check your progress in the console now!${RESET}"
