#!/bin/bash
set -euo pipefail

# ─── Colors ────────────────────────────────────────────────────────────────────
CYAN=$'\033[0;96m'
GREEN=$'\033[0;92m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
RESET=$'\033[0m'
BOLD=$'\033[1m'
UNDERLINE=$'\033[4m'

step() { echo; echo "${CYAN}${BOLD}Step $1:${RESET} ${GREEN}$2${RESET}"; }

clear

# ─── Enable API & Create Processor ────────────────────────────────────────────
echo
echo "${CYAN}${BOLD}Enabling Document AI API...${RESET}"
gcloud services enable documentai.googleapis.com

export PROJECT_ID=$(gcloud config get-value project)

echo
echo "${CYAN}${BOLD}Creating Form Parser Processor...${RESET}"
export PROCESSOR_ID=$(curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "form-parser",
    "type": "FORM_PARSER_PROCESSOR"
  }' \
  "https://us-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/us/processors" \
  | jq -r '.name | split("/") | last')

echo "${GREEN}${BOLD}Processor ID: ${PROCESSOR_ID}${RESET}"

# ─── Step 1: System update ─────────────────────────────────────────────────────
step 1 "Updating system and installing dependencies."
sudo apt-get update -q
sudo apt-get install -y -q --no-install-recommends python3-pip

# ─── Step 2: Service account setup ────────────────────────────────────────────
step 2 "Creating service account and configuring IAM permissions."
export SA_NAME="document-ai-service-account"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
  gcloud iam service-accounts create "$SA_NAME" --display-name="$SA_NAME"
fi

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/documentai.apiUser" \
  --quiet

gcloud iam service-accounts keys create key.json \
  --iam-account="$SA_EMAIL"

export GOOGLE_APPLICATION_CREDENTIALS="$PWD/key.json"

# ─── Step 3: Download sample PDF ──────────────────────────────────────────────
step 3 "Downloading sample PDF."
gsutil -q cp gs://cloud-training/gsp924/health-intake-form.pdf .

# ─── Step 4: Build JSON request ───────────────────────────────────────────────
step 4 "Encoding PDF and building API request payload."
sleep 20
{
  echo '{"inlineDocument": {"mimeType": "application/pdf","content": "'
  base64 health-intake-form.pdf | tr -d '\n'
  echo '"}}'
} | tr -d '\n' > request.json

# ─── Step 5: Call Document AI API ─────────────────────────────────────────────
step 5 "Sending request to Document AI API."
export LOCATION="us"

curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d @request.json \
  "https://${LOCATION}-documentai.googleapis.com/v1beta3/projects/${PROJECT_ID}/locations/${LOCATION}/processors/${PROCESSOR_ID}:process" \
  -o output.json

# ─── Step 6: Display extracted text ───────────────────────────────────────────
step 6 "Displaying extracted document text."
sleep 18
jq -r '.document.text' output.json

# ─── Step 7: Download Python script ───────────────────────────────────────────
step 7 "Downloading Python synchronous processing script."
gsutil -q cp gs://cloud-training/gsp924/synchronous_doc_ai.py .

# ─── Step 8: Install Python dependencies ──────────────────────────────────────
step 8 "Installing Python dependencies."
python3 -m pip install -q --upgrade \
  google-cloud-documentai \
  google-cloud-storage \
  prettytable

# ─── Step 9: Run Python script ────────────────────────────────────────────────
step 9 "Running synchronous Document AI Python script."

python3 synchronous_doc_ai.py \
  --project_id="$PROJECT_ID" \
  --processor_id="$PROCESSOR_ID" \
  --location=us \
  --file_name=health-intake-form.pdf | tee results.txt

# ─── Step 10: Verification API call ───────────────────────────────────────────
step 10 "Sending verification request to Document AI API."

curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d @request.json \
  "https://${LOCATION}-documentai.googleapis.com/v1beta3/projects/${PROJECT_ID}/locations/${LOCATION}/processors/${PROCESSOR_ID}:process" \
  -o output.json

# ─── SSH into VM and run script ───────────────────────────────────────────────
echo
echo "${CYAN}${BOLD}SSHing into VM and executing test.sh...${RESET}"

export ZONE=$(gcloud compute instances list document-ai-dev \
  --format='csv[no-heading](zone)')

gcloud compute ssh document-ai-dev \
  --project="$DEVSHELL_PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  --command="curl -LO https://raw.githubusercontent.com/ishaq-md/cloudskill-2026/refs/heads/main/test.sh && sudo chmod +x test.sh && ./test.sh"

echo
echo "${BLUE}${BOLD}Subscribe to Dr Abhishek Cloud Tutorial:${RESET} ${MAGENTA}${UNDERLINE}https://www.youtube.com/@drabhishek.5460/videos${RESET}"
echo
