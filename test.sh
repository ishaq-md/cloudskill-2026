#!/bin/bash

# Colors for clarity
CYAN='\033[0;96m'
GREEN='\033[0;92m'
RESET='\033[0m'

echo "${CYAN}🚀 Starting Document AI Lab Speedrun...${RESET}"

# 1. Setup Environment & Enable API
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
echo "${CYAN}Processor ID Captured: $PROCESSOR_ID${RESET}"

# 3. Find VM Zone (Task 3)
export ZONE=$(gcloud compute instances list --filter="name:document-ai-dev" --format='value(zone)' | head -n 1)

# 4. Define commands to run INSIDE the VM
# This block covers Task 3 (Auth), Task 4 (Curl), and Task 5 (Python)
REMOTE_COMMANDS=$(cat <<EOF
export PROJECT_ID=$PROJECT_ID
export PROCESSOR_ID=$PROCESSOR_ID
export LOCATION="us"

curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d "{
    \"rawDocument\": {
      \"content\": \"$(base64 -w 0 form.pdf)\",
      \"mimeType\": \"application/pdf\"
    }
  }" \
  "https://us-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/us/processors/${PROCESSOR_ID}:process"

# Task 3: Authenticate API requests
export SA_NAME="document-ai-service-account"
gcloud iam service-accounts create \$SA_NAME --display-name \$SA_NAME --quiet || true

gcloud projects add-iam-policy-binding \${PROJECT_ID} \
  --member="serviceAccount:\$SA_NAME@\${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/documentai.apiUser" --quiet

gcloud iam service-accounts keys create key.json \
  --iam-account \$SA_NAME@\${PROJECT_ID}.iam.gserviceaccount.com --quiet

export GOOGLE_APPLICATION_CREDENTIALS="\$PWD/key.json"

# Task 3 & 4: Download form and prepare JSON
gsutil cp gs://spls/gsp924/health-intake-form.pdf .
echo '{"inlineDocument": {"mimeType": "application/pdf","content": "' > temp.json
base64 health-intake-form.pdf | tr -d '\n' >> temp.json
echo '"}}' >> temp.json
cat temp.json | tr -d '\n' > request.json

# Task 4: Make Synchronous Request using Curl
sudo apt-get update && sudo apt-get install jq -y
curl -s -X POST \
  -H "Authorization: Bearer \$(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d @request.json \
  "https://\${LOCATION}-documentai.googleapis.com/v1beta3/projects/\${PROJECT_ID}/locations/\${LOCATION}/processors/\${PROCESSOR_ID}:process" > output.json

# Task 5: Python Client Setup and Execution
gsutil cp gs://spls/gsp924/synchronous_doc_ai.py .
sudo apt-get install python3-pip -y
python3 -m pip install --upgrade google-cloud-documentai google-cloud-storage prettytable --quiet

echo "${GREEN}Running Python script...${RESET}"
python3 synchronous_doc_ai.py \
  --project_id=\$PROJECT_ID \
  --processor_id=\$PROCESSOR_ID \
  --location=\$LOCATION \
  --file_name=health-intake-form.pdf
EOF
)

# 5. Execute everything on the VM via SSH
echo "${GREEN}Connecting to VM and executing lab tasks...${RESET}"
gcloud compute ssh document-ai-dev --project=$PROJECT_ID --zone=$ZONE --quiet --command="$REMOTE_COMMANDS"

echo "${CYAN}✅ Lab Tasks Complete! Click all 'Check my progress' buttons now.${RESET}"
