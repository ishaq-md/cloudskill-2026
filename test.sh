#!/bin/bash

# Colors for flair
CYAN='\033[0;96m'
GREEN='\033[0;92m'
RESET='\033[0m'

echo "${CYAN}🚀 Starting Speedrun...${RESET}"

# 1. Setup Environment
export PROJECT_ID=$(gcloud config get-value project)
export LOCATION="us"
gcloud services enable documentai.googleapis.com --quiet

# 2. Create Processor and CAPTURE ID (The most important fix)
echo "${GREEN}Creating Processor...${RESET}"
export PROCESSOR_ID=$(curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "lab-form-parser",
    "type": "FORM_PARSER_PROCESSOR"
  }' \
  "https://us-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/us/processors" | jq -r '.name' | sed 's|.*/||')

echo "${CYAN}Captured Processor ID: $PROCESSOR_ID${RESET}"

# 3. Prepare the Workhorse Commands
# We wrap everything that needs to happen ON THE VM into one block
REMOTE_COMMANDS=$(cat <<EOF
export PROJECT_ID=$PROJECT_ID
export PROCESSOR_ID=$PROCESSOR_ID
export LOCATION=$LOCATION

# Install dependencies fast
sudo apt-get update && sudo apt-get install jq -y
python3 -m pip install --upgrade google-cloud-documentai google-cloud-storage prettytable --quiet

# Download Lab Files
gsutil cp gs://spls/gsp924/health-intake-form.pdf .
gsutil cp gs://spls/gsp924/synchronous_doc_ai.py .

# Create Request JSON (Corrected Base64)
echo "{\"rawDocument\": {\"mimeType\": \"application/pdf\",\"content\": \"\$(base64 -w 0 health-intake-form.pdf)\"}}" > request.json

# Run Python Script (The Lab Checkpoint)
python3 synchronous_doc_ai.py \
  --project_id=\$PROJECT_ID \
  --processor_id=\$PROCESSOR_ID \
  --location=\$LOCATION \
  --file_name=health-intake-form.pdf | tee results.txt

# Direct API Call for Verification
curl -X POST \
  -H "Authorization: Bearer \$(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d @request.json \
  "https://\$LOCATION-documentai.googleapis.com/v1/projects/\$PROJECT_ID/locations/\$LOCATION/processors/\$PROCESSOR_ID:process" > output.json

echo "DONE"
EOF
)

# 4. Find Zone and Execute on VM
export ZONE=$(gcloud compute instances list --filter="name:document-ai-dev" --format='value(zone)')

echo "${GREEN}Executing commands on VM: document-ai-dev...${RESET}"
gcloud compute ssh document-ai-dev --project=$PROJECT_ID --zone=$ZONE --quiet --command="$REMOTE_COMMANDS"

echo "${CYAN}Lab completed. Check your progress now!${RESET}"
