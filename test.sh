#!/bin/bash

CYAN='\033[0;96m'
GREEN='\033[0;92m'
RED='\033[0;91m'
RESET='\033[0m'

echo "${CYAN}🚀 Fast Document AI Lab Run...${RESET}"

# 1. Setup
PROJECT_ID=$(gcloud config get-value project)
gcloud services enable documentai.googleapis.com --quiet

# Install jq quickly
sudo apt-get update -y >/dev/null 2>&1
sudo apt-get install jq -y >/dev/null 2>&1

# 2. Create processor
echo "${GREEN}Creating processor...${RESET}"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "form-parser",
    "type": "FORM_PARSER_PROCESSOR"
  }' \
  "https://us-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/us/processors")

PROCESSOR_ID=$(echo "$RESPONSE" | jq -r '.name' | awk -F'/' '{print $NF}')

if [ -z "$PROCESSOR_ID" ] || [ "$PROCESSOR_ID" = "null" ]; then
  echo "${RED}❌ Processor creation failed${RESET}"
  echo "$RESPONSE"
  exit 1
fi

echo "${CYAN}Processor ID: $PROCESSOR_ID${RESET}"

# 3. Get VM zone
ZONE=$(gcloud compute instances list \
  --filter="name:document-ai-dev" \
  --format='value(zone)' | head -n 1)

# 4. Run ONLY required task in VM
echo "${GREEN}Processing document inside VM...${RESET}"

gcloud compute ssh document-ai-dev \
  --zone=$ZONE \
  --quiet \
  --command="
PROJECT_ID=$PROJECT_ID
PROCESSOR_ID=$PROCESSOR_ID

# Download sample PDF
gsutil cp gs://spls/gsp924/health-intake-form.pdf .

# Encode safely
base64 -w 0 health-intake-form.pdf > file.b64

# Create request
cat <<EOF > request.json
{
  \"rawDocument\": {
    \"content\": \"\$(cat file.b64)\",
    \"mimeType\": \"application/pdf\"
  }
}
EOF

# Call API
curl -s -X POST \
  -H \"Authorization: Bearer \$(gcloud auth print-access-token)\" \
  -H \"Content-Type: application/json\" \
  -d @request.json \
  \"https://us-documentai.googleapis.com/v1/projects/\${PROJECT_ID}/locations/us/processors/\${PROCESSOR_ID}:process\" \
  > /dev/null

echo '✅ Document processed'
"

echo "${CYAN}✅ Done! Now click 'Check my progress'.${RESET}"
