#!/bin/bash

# Colors
CYAN='\033[0;96m'
GREEN='\033[0;92m'
RED='\033[0;91m'
RESET='\033[0m'

echo "${CYAN}🚀 Starting Document AI Lab Speedrun...${RESET}"

# 1. Setup
export PROJECT_ID=$(gcloud config get-value project)

echo "${GREEN}Enabling Document AI API...${RESET}"
gcloud services enable documentai.googleapis.com --quiet

# Install jq (required)
sudo apt-get update -y >/dev/null 2>&1
sudo apt-get install jq -y >/dev/null 2>&1

# 2. Create Processor
echo "${GREEN}Creating form-parser processor...${RESET}"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "form-parser",
    "type": "FORM_PARSER_PROCESSOR"
  }' \
  "https://us-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/us/processors")

echo "$RESPONSE"

PROCESSOR_ID=$(echo "$RESPONSE" | jq -r '.name // empty' | awk -F'/' '{print $NF}')

if [ -z "$PROCESSOR_ID" ]; then
  echo "${RED}❌ Failed to create processor${RESET}"
  exit 1
fi

echo "${CYAN}Processor ID: $PROCESSOR_ID${RESET}"

# 3. Get VM zone
ZONE=$(gcloud compute instances list \
  --filter="name:document-ai-dev" \
  --format='value(zone)' | head -n 1)

echo "${GREEN}Connecting to VM...${RESET}"

# 4. Run tasks inside VM
gcloud compute ssh document-ai-dev \
  --zone=$ZONE \
  --quiet \
  --command="
# Set variables
PROJECT_ID=$PROJECT_ID
PROCESSOR_ID=$PROCESSOR_ID
LOCATION=us

echo '📥 Downloading sample PDF...'
gsutil cp gs://spls/gsp924/health-intake-form.pdf .

echo '📦 Encoding PDF...'
base64 -w 0 health-intake-form.pdf > file.b64

echo '📝 Creating request.json...'
cat <<EOF > request.json
{
  \"rawDocument\": {
    \"content\": \"\$(cat file.b64)\",
    \"mimeType\": \"application/pdf\"
  }
}
EOF

echo '🚀 Sending request to Document AI...'
curl -s -X POST \
  -H \"Authorization: Bearer \$(gcloud auth print-access-token)\" \
  -H \"Content-Type: application/json\" \
  -d @request.json \
  \"https://us-documentai.googleapis.com/v1/projects/\${PROJECT_ID}/locations/\${LOCATION}/processors/\${PROCESSOR_ID}:process\" \
  > output.json

echo '✅ Output saved to output.json'

# Optional Python task
echo '🐍 Running Python client...'
gsutil cp gs://spls/gsp924/synchronous_doc_ai.py .

sudo apt-get install python3-pip -y >/dev/null 2>&1
python3 -m pip install --upgrade google-cloud-documentai google-cloud-storage prettytable --quiet

python3 synchronous_doc_ai.py \
  --project_id=\$PROJECT_ID \
  --processor_id=\$PROCESSOR_ID \
  --location=\$LOCATION \
  --file_name=health-intake-form.pdf

echo '🎉 VM tasks completed!'
"

echo "${CYAN}✅ Lab Completed! Click all 'Check my progress' buttons.${RESET}"
