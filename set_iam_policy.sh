#!/usr/bin/env bash

if [ -z "$PROJECT_ID" ]; then
  echo "No PROJECT_ID variable set"
  exit
fi

if [ -z "$API_KEY" ]; then
  echo "No API_KEY variable set"
  exit
fi

if [ -z "$API_SECRET" ]; then
  echo "No API_SECRET variable set"
  exit
fi

gcloud alpha agent-identity connectors create apigee \
    --location="us-central1" \
    --description="apigee" \
    --two-legged-oauth-client-id=$API_KEEY \
    --two-legged-oauth-client-secret=$API_SECRET \
    --two-legged-oauth-token-endpoint="https://34.107.220.83.nip.io/oauth2/token" \
    --project $PROJECT_ID

sleep 5

PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
ORG_ID=$(gcloud projects get-ancestors $PROJECT_ID --format="value(id, type)" | while read -r id type; do
  if [[ "$type" == "organization" ]]; then
    echo "$id"
    break
  fi
done)

sleep 2

gcloud alpha agent-identity connectors add-iam-policy-binding apigee \
          --project=$PROJECT_ID \
          --location=us-central1 \
          --member="principalSet://agents.global.org-$ORG_ID.system.id.goog/attribute.platformContainer/aiplatform/projects/$PROJECT_NUMBER" \
          --role="roles/iamconnectors.user"