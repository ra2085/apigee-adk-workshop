#!/bin/bash

# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# --- Variable Checks ---
if [ -z "$PROJECT" ]; then
  echo "ERROR: No PROJECT variable set. Please set it to your GCP project ID."
  exit 1
fi

if [ -z "$APIGEE_ENV" ]; then
  echo "ERROR: No APIGEE_ENV variable set. Please set it to your Apigee environment name."
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "INFO: No TOKEN variable set. Attempting to fetch from gcloud."
  TOKEN=$(gcloud auth print-access-token)
  if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get gcloud access token. Please login or set the TOKEN variable."
    exit 1
  fi
  echo "INFO: Successfully fetched gcloud access token."
fi

APP_NAME=sample-mcp-consumer-app
DEVELOPER_EMAIL=mcpconsumer@cymbal.com
PRODUCT_NAME=mcp-product
RESOURCE_NAME=oauth_configuration
RESOURCE_FILE=oauth_configuration.properties

echo "Installing apigeecli"
curl -s https://raw.githubusercontent.com/apigee/apigeecli/main/downloadLatest.sh | bash
export PATH=$PATH:$HOME/.apigeecli/bin

echo "Deleting Developer App"
apigeecli apps delete --name $APP_NAME --email $DEVELOPER_EMAIL --org "$PROJECT" --token "$TOKEN"

echo "Deleting Developer"
apigeecli developers delete --email $DEVELOPER_EMAIL --org "$PROJECT" --token "$TOKEN"

echo "Deleting API Products"
apigeecli products delete --name mcp-product --org "$PROJECT" --token "$TOKEN"
apigeecli products delete --name crm-product --org "$PROJECT" --token "$TOKEN"
apigeecli products delete --name oms-product --org "$PROJECT" --token "$TOKEN"
apigeecli products delete --name wms-product --org "$PROJECT" --token "$TOKEN"

echo "Undeploying and Deleting mcp-spec-tools proxy"
REV=$(apigeecli envs deployments get --env "$APIGEE_ENV" --org "$PROJECT" --token "$TOKEN" --disable-check | jq --arg proxy "mcp-spec-tools" '.deployments[] | select(.apiProxy==$proxy).revision' -r)
apigeecli apis undeploy --name mcp-spec-tools --env "$APIGEE_ENV" --rev "$REV" --org "$PROJECT" --token "$TOKEN"
apigeecli apis delete --name mcp-spec-tools --org "$PROJECT" --token "$TOKEN"

echo "Undeploying and Deleting customers-api proxy"
REV=$(apigeecli envs deployments get --env "$APIGEE_ENV" --org "$PROJECT" --token "$TOKEN" --disable-check | jq --arg proxy "customers-api" '.deployments[] | select(.apiProxy==$proxy).revision' -r)
apigeecli apis undeploy --name customers-api --env "$APIGEE_ENV" --rev "$REV" --org "$PROJECT" --token "$TOKEN"
apigeecli apis delete --name customers-api --org "$PROJECT" --token "$TOKEN"

echo "Undeploying and Deleting order-creation-api proxy"
REV=$(apigeecli envs deployments get --env "$APIGEE_ENV" --org "$PROJECT" --token "$TOKEN" --disable-check | jq --arg proxy "order-creation-api" '.deployments[] | select(.apiProxy==$proxy).revision' -r)
apigeecli apis undeploy --name order-creation-api --env "$APIGEE_ENV" --rev "$REV" --org "$PROJECT" --token "$TOKEN"
apigeecli apis delete --name order-creation-api --org "$PROJECT" --token "$TOKEN"

echo "Undeploying and Deleting product-catalog-and-availability-api proxy"
REV=$(apigeecli envs deployments get --env "$APIGEE_ENV" --org "$PROJECT" --token "$TOKEN" --disable-check | jq --arg proxy "product-catalog-and-availability-api" '.deployments[] | select(.apiProxy==$proxy).revision' -r)
apigeecli apis undeploy --name product-catalog-and-availability-api --env "$APIGEE_ENV" --rev "$REV" --org "$PROJECT" --token "$TOKEN"
apigeecli apis delete --name product-catalog-and-availability-api --org "$PROJECT" --token "$TOKEN"

echo "Undeploying and Deleting shipping-carrier-api proxy"
REV=$(apigeecli envs deployments get --env "$APIGEE_ENV" --org "$PROJECT" --token "$TOKEN" --disable-check | jq --arg proxy "shipping-carrier-api" '.deployments[] | select(.apiProxy==$proxy).revision' -r)
apigeecli apis undeploy --name shipping-carrier-api --env "$APIGEE_ENV" --rev "$REV" --org "$PROJECT" --token "$TOKEN"
apigeecli apis delete --name shipping-carrier-api --org "$PROJECT" --token "$TOKEN"

echo "Undeploying and Deleting warehouse-management-system-api proxy"
REV=$(apigeecli envs deployments get --env "$APIGEE_ENV" --org "$PROJECT" --token "$TOKEN" --disable-check | jq --arg proxy "warehouse-management-system-api" '.deployments[] | select(.apiProxy==$proxy).revision' -r)
apigeecli apis undeploy --name warehouse-management-system-api --env "$APIGEE_ENV" --rev "$REV" --org "$PROJECT" --token "$TOKEN"
apigeecli apis delete --name warehouse-management-system-api --org "$PROJECT" --token "$TOKEN"


echo "Deleting $RESOURCE_NAME environment property set..."
apigeecli res delete --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --name $RESOURCE_NAME --type properties

rm -f $RESOURCE_FILE
