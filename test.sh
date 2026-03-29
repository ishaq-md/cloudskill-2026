#!/bin/bash

# ===============================
# Colors for clarity
# ===============================
CYAN='\033[0;96m'
GREEN='\033[0;92m'
RED='\033[0;91m'
RESET='\033[0m'

echo -e "${CYAN}🚀 Starting FULL Document AI Lab Script...${RESET}"

# -------------------------------
# 1. Set Project ID & Enable API
# -------------------------------
export PROJECT_ID=$(gcloud config get-value project)
gcloud services enable documentai.googleapis.com --quiet
echo -e "${GREEN}✅ Document AI API enabled${RESET}"

# -------------------------------
# 2. Create 'form-parser' Processor
# -------------------------------
echo -e "${GREEN}Creating processor...${RESET}"
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "form-parser",
    "type": "FORM_PARSER_PROCESSOR"
  }' \
  "https://us-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/us/processors")

# Extract processor ID
PROCESSOR_ID=$(echo $RESPONSE | jq -r '.name' | sed 's|.*/||')

# Handle duplicate processor
if [ "$PROCESSOR_ID" == "null" ] || [ -z "$PROCESSOR_ID" ]; then
    echo -e "${RED}Processor creation failed or already exists. Fetching existing processor ID...${RESET}"
    PROCESSOR_ID=$(gcloud documentai processors list \
        --project=$PROJECT_ID --location=us \
        --filter="display_name:form-parser" \
        --format="value(name)" | sed 's|.*/||')
fi

echo -e "${CYAN}Processor ID: $PROCESSOR_ID${RESET}"

# -------------------------------
# 3. Set VM Zone
# -------------------------------
ZONE=$(gcloud compute instances list --filter="name:document-ai-dev" --format='value(zone)' | head -n1)

# -------------------------------
# 4. Prepare commands for VM
# -------------------------------
REMOTE_COMMANDS=$(cat <<EOF
export PROJECT_ID=$PROJECT_ID
export PROCESSOR_ID=$PROCESSOR_ID
export LOCATION="us"

# -------------------------------
# 4a. Create Service Account
# -------------------------------
echo -e "${GREEN}🔐 Creating Service Account...${RESET}"
export SA_NAME="document-ai-service-account"
gcloud iam service-accounts create \$SA_NAME --display-name \$SA_NAME --quiet || true

gcloud projects add-iam-policy-binding \$PROJECT_ID \
  --member="serviceAccount:\$SA_NAME@\${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/documentai.apiUser" --quiet

gcloud iam service-accounts keys create key.json \
  --iam-account \$SA_NAME@\${PROJECT_ID}.iam.gserviceaccount.com --quiet

export GOOGLE_APPLICATION_CREDENTIALS="\$PWD/key.json"
echo -e "${GREEN}✅ Service Account created and credentials set${RESET}"

# -------------------------------
# 4b. Download sample form
# -------------------------------
echo -e "${GREEN}📥 Downloading sample form...${RESET}"
gsutil cp gs://spls/gsp924/health-intake-form.pdf .

# Create JSON request for curl
echo -e "${GREEN}📝 Creating request.json...${RESET}"
echo '{"inlineDocument": {"mimeType": "application/pdf","content": "' > temp.json
base64 health-intake-form.pdf | tr -d '\n' >> temp.json
echo '"}}' >> temp.json
cat temp.json | tr -d '\n' > request.json

# -------------------------------
# 4c. Synchronous curl request
# -------------------------------
echo -e "${GREEN}🚀 Calling Document AI API...${RESET}"
curl -s -X POST \
  -H "Authorization: Bearer \$(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d @request.json \
  "https://\${LOCATION}-documentai.googleapis.com/v1beta3/projects/\${PROJECT_ID}/locations/\${LOCATION}/processors/\${PROCESSOR_ID}:process" > output.json

echo -e "${GREEN}✅ API response saved to output.json${RESET}"

# Extract text and form fields using jq
sudo apt-get update -qq
sudo apt-get install -y jq

echo -e "${GREEN}📄 Extracted text:${RESET}"
cat output.json | jq -r ".document.text"

echo -e "${GREEN}📊 Form fields:${RESET}"
cat output.json | jq -r ".document.pages[].formFields"

# -------------------------------
# 5. Python Client Processing
# -------------------------------
echo -e "${GREEN}🐍 Installing Python dependencies...${RESET}"
sudo apt install -y python3-pip
python3 -m pip install --upgrade google-cloud-documentai google-cloud-storage prettytable --quiet

echo -e "${GREEN}📂 Downloading Python sample code...${RESET}"
gsutil cp gs://spls/gsp924/synchronous_doc_ai.py .

echo -e "${GREEN}🚀 Running Python script...${RESET}"
python3 synchronous_doc_ai.py \
  --project_id=\$PROJECT_ID \
  --processor_id=\$PROCESSOR_ID \
  --location=\$LOCATION \
  --file_name=health-intake-form.pdf
EOF
)

# -------------------------------
# 6. Execute everything inside VM
# -------------------------------
echo -e "${GREEN}🚀 Running all lab tasks inside VM...\n${RESET}"
gcloud compute ssh document-ai-dev --project=$PROJECT_ID --zone=$ZONE --quiet --command="$REMOTE_COMMANDS"

echo -e "${CYAN}✅ Lab Script Completed! Check your output.json and Python results.${RESET}"
