#!/bin/bash

CYAN='\033[0;96m'
GREEN='\033[0;92m'
RED='\033[0;91m'
RESET='\033[0m'

echo "${CYAN}🚀 Starting FULL Document AI Lab Script...${RESET}"

# -------------------------------
# Task 1: Setup
# -------------------------------
PROJECT_ID=$(gcloud config get-value project)
gcloud services enable documentai.googleapis.com --quiet

sudo apt-get update -y >/dev/null 2>&1
sudo apt-get install jq -y >/dev/null 2>&1

# -------------------------------
# Task 2: Create Processor
# -------------------------------
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

# -------------------------------
# Task 3: Connect to VM
# -------------------------------
ZONE=$(gcloud compute instances list \
  --filter="name:document-ai-dev" \
  --format='value(zone)' | head -n 1)

echo "${GREEN}Running all lab tasks inside VM...${RESET}"

gcloud compute ssh document-ai-dev \
  --zone=$ZONE \
  --quiet \
  --command="
# -------------------------------
# Inside VM
# -------------------------------
PROJECT_ID=$PROJECT_ID
PROCESSOR_ID=$PROCESSOR_ID
LOCATION=us

echo '🔐 Creating Service Account...'
SA_NAME='document-ai-service-account'

gcloud iam service-accounts create \$SA_NAME --display-name=\$SA_NAME --quiet || true

gcloud projects add-iam-policy-binding \$PROJECT_ID \
  --member=\"serviceAccount:\$SA_NAME@\${PROJECT_ID}.iam.gserviceaccount.com\" \
  --role=\"roles/documentai.apiUser\" --quiet

gcloud iam service-accounts keys create key.json \
  --iam-account \$SA_NAME@\${PROJECT_ID}.iam.gserviceaccount.com --quiet

export GOOGLE_APPLICATION_CREDENTIALS=\"\$PWD/key.json\"

echo '📥 Downloading sample form...'
gsutil cp gs://spls/gsp924/health-intake-form.pdf .

# -------------------------------
# Task 3: Create request.json
# -------------------------------
echo '📝 Creating request.json...'
echo '{\"inlineDocument\": {\"mimeType\": \"application/pdf\",\"content\": \"' > temp.json
base64 health-intake-form.pdf | tr -d '\n' >> temp.json
echo '\"}}' >> temp.json
cat temp.json | tr -d '\n' > request.json

# -------------------------------
# Task 4: CURL API CALL
# -------------------------------
echo '🚀 Calling Document AI API...'
curl -s -X POST \
  -H \"Authorization: Bearer \$(gcloud auth application-default print-access-token)\" \
  -H \"Content-Type: application/json; charset=utf-8\" \
  -d @request.json \
  \"https://\${LOCATION}-documentai.googleapis.com/v1beta3/projects/\${PROJECT_ID}/locations/\${LOCATION}/processors/\${PROCESSOR_ID}:process\" \
  > output.json

echo '✅ API response saved to output.json'

# -------------------------------
# Task 4: Extract data using jq
# -------------------------------
sudo apt-get update -y >/dev/null 2>&1
sudo apt-get install jq -y >/dev/null 2>&1

echo '📄 Extracted text:'
cat output.json | jq -r '.document.text' | head -n 20

echo '📊 Form fields:'
cat output.json | jq -r '.document.pages[].formFields' | head -n 20

# -------------------------------
# Task 5: Python setup
# -------------------------------
echo '🐍 Installing Python dependencies...'
sudo apt-get install python3-pip -y >/dev/null 2>&1
python3 -m ensurepip --upgrade || true
python3 -m pip install --upgrade pip --quiet
python3 -m pip install google-cloud-documentai google-cloud-storage prettytable --quiet

# -------------------------------
# Task 5: Download Python script
# -------------------------------
gsutil cp gs://spls/gsp924/synchronous_doc_ai.py .

# -------------------------------
# Task 6: Run Python script
# -------------------------------
echo '🚀 Running Python Document AI script...'

python3 synchronous_doc_ai.py \
  --project_id=\$PROJECT_ID \
  --processor_id=\$PROCESSOR_ID \
  --location=\$LOCATION \
  --file_name=health-intake-form.pdf | tee results.txt

echo '🎉 All VM tasks completed!'
"

echo "${CYAN}✅ FULL LAB COMPLETED — Click all 'Check my progress' buttons.${RESET}"
