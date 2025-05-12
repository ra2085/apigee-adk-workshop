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

gen_key_pairs() {
  if [ -z "$PR_KEY" ]; then
    PR_KEY=$(openssl genrsa 4086)
    echo "$PR_KEY"
    PU_KEY=$(printf '%s\n' "$PR_KEY" | openssl rsa -outform PEM -pubout)
    echo "$PU_KEY"
    PR_KEY=$(printf '%s\n' "$PR_KEY" | tr -d '\n')
    PU_KEY=$(printf '%s\n' "$PU_KEY" | tr -d '\n')
  else
  fi
}

# --- Variable Checks ---
if [ -z "$PROJECT" ]; then
  echo "ERROR: No PROJECT variable set. Please set it to your GCP project ID."
  exit 1
fi
if [ -z "$REGION" ]; then
  echo "ERROR: No REGION variable set. Please set it to your API Hub region."
  exit 1
fi
if [ -z "$APIGEE_ENV" ]; then
  echo "ERROR: No APIGEE_ENV variable set. Please set it to your Apigee environment name."
  exit 1
fi
if [ -z "$CUSTOMERS_API_CR_URL" ]; then
  echo "ERROR: No CUSTOMERS_API_CR_URL variable set. Please set it to your Cloud Run Target."
  exit 1
fi
if [ -z "$ORDERS_API_CR_URL" ]; then
  echo "ERROR: No ORDERS_API_CR_URL variable set. Please set it to your Cloud Run Target."
  exit 1
fi
if [ -z "$PRODUCTS_API_CR_URL" ]; then
  echo "ERROR: No PRODUCTS_API_CR_URL variable set. Please set it to your Cloud Run Target."
  exit 1
fi
if [ -z "$SHIPPING_API_CR_URL" ]; then
  echo "ERROR: No SHIPPING_API_CR_URL variable set. Please set it to your Cloud Run Target."
  exit 1
fi
if [ -z "$WAREHOUSE_API_CR_URL" ]; then
  echo "ERROR: No WAREHOUSE_API_CR_URL variable set. Please set it to your Cloud Run Target."
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

echo "Installing apigeecli"
curl -s https://raw.githubusercontent.com/apigee/apigeecli/main/downloadLatest.sh | bash
export PATH=$PATH:$HOME/.apigeecli/bin

gen_key_pairs

echo "Crating HUB resources ..."

sed -i "s/@APIGEE_HOST@/$APIGEE_HOST/g" ./specs/customers-api/spec.yaml
sed -i "s/@APIGEE_HOST@/$APIGEE_HOST/g" ./specs/orders-creation-api/spec.yaml
sed -i "s/@APIGEE_HOST@/$APIGEE_HOST/g" ./specs/product-catalog-and-availability-api/spec.yaml
sed -i "s/@APIGEE_HOST@/$APIGEE_HOST/g" ./specs/shipping-carrier-api/spec.yaml
sed -i "s/@APIGEE_HOST@/$APIGEE_HOST/g" ./specs/warehouse-management-system-api/spec.yaml

apigeecli apihub apis create -i customers-api -f ./specs/customers-api/api.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions create --api-id customers-api -i 1_0_0 -f ./specs/customers-api/version.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions specs create --api-id customers-api -d customers-api.yaml -i customers-api -v 1_0_0 -f ./specs/customers-api/spec.yaml --org "$PROJECT" -r "$REGION" --token "$TOKEN"

apigeecli apihub apis create -i orders-api -f ./specs/orders-creation-api/api.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions create --api-id orders-api -i 1_0_0 -f ./specs/orders-creation-api/version.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions specs create --api-id orders-api -d orders-api.yaml -i orders-api -v 1_0_0 -f ./specs/customers-api/spec.yaml --org "$PROJECT" -r "$REGION" --token "$TOKEN"

apigeecli apihub apis create -i product-catalog-and-availability-api -f ./specs/product-catalog-and-availability-api/api.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions create --api-id product-catalog-and-availability-api -i 1_0_0 -f ./specs/product-catalog-and-availability-api/version.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions specs create --api-id product-catalog-and-availability-api -d product-catalog-and-availability-api.yaml -i product-catalog-and-availability-api -v 1_0_0 -f ./specs/product-catalog-and-availability-api/spec.yaml --org "$PROJECT" -r "$REGION" --token "$TOKEN"

apigeecli apihub apis create -i shipping-carrier-api -f ./specs/shipping-carrier-api/api.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions create --api-id shipping-carrier-api -i 1_0_0 -f ./specs/shipping-carrier-api/version.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions specs create --api-id shipping-carrier-api -d shipping-carrier-api.yaml -i shipping-carrier-api --api -v 1_0_0 -f ./specs/shipping-carrier-api/spec.yaml --org "$PROJECT" -r "$REGION" --token "$TOKEN"

apigeecli apihub apis create -i warehouse-management-system-api -f ./specs/warehouse-management-system-api/api.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions create --api-id warehouse-management-system-api -i 1_0_0 -f ./specs/warehouse-management-system-api/version.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions specs create --api-id swarehouse-management-system-api -d warehouse-management-system-api.yaml -i warehouse-management-system-api -v 1_0_0 -f ./specs/warehouse-management-system-api/spec.yaml --org "$PROJECT" -r "$REGION" --token "$TOKEN"

sed -i "s/@TARGETURL@/$CUSTOMERS_API_CR_URL/g" ./apigee-mcp-products/customers-api/apiproxy/targets/default.xml
sed -i "s/@TARGETURL@/$ORDERS_API_CR_URL/g" ./apigee-mcp-products/order-creation-api/apiproxy/targets/default.xml
sed -i "s/@TARGETURL@/$PRODUCTS_API_CR_URL/g" ./apigee-mcp-products/product-catalog-and-availability-api/apiproxy/targets/default.xml
sed -i "s/@TARGETURL@/$SHIPPING_API_CR_URL/g" ./apigee-mcp-products/shipping-carrier-api/apiproxy/targets/default.xml
sed -i "s/@TARGETURL@/$WAREHOUSE_API_CR_URL/g" ./apigee-mcp-products/warehouse-management-system-api/apiproxy/targets/default.xml

echo "Deploying keypair configuration..."
echo -e "public_key=$PU_KEY\nprivate_key=$PR_KEY" >oauth_configuration.properties
apigeecli res create --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --name oauth_configuration --type properties --respath oauth_configuration.properties

echo "Importing and Deploying mcp-spec-tools ..."
REV=$(apigeecli apis create bundle -f ./apigee-mcp-products/mcp-spec-tools/apiproxy -n mcp-spec-tools --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name mcp-spec-tools --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying customers-api ..."
REV=$(apigeecli apis create bundle -f ./apigee-mcp-products/customers-api/apiproxy -n customers-api --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name customers-api --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying order-creation-api ..."
REV=$(apigeecli apis create bundle -f ./apigee-mcp-products/order-creation-api/apiproxy -n order-creation-api --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name order-creation-api --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying product-catalog-and-availability-api ..."
REV=$(apigeecli apis create bundle -f ./apigee-mcp-products/product-catalog-and-availability-api/apiproxy -n product-catalog-and-availability-api --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name product-catalog-and-availability-api --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying shipping-carrier-api ..."
REV=$(apigeecli apis create bundle -f ./apigee-mcp-products/shipping-carrier-api/apiproxy -n shipping-carrier-api --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name shipping-carrier-api --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying warehouse-management-system-api ..."
REV=$(apigeecli apis create bundle -f ./apigee-mcp-products/warehouse-management-system-api/apiproxy -n warehouse-management-system-api --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name warehouse-management-system-api --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Creating MCP Product"
apigeecli products create --name mcp-product --display-name "MCP Product" --envs "$APIGEE_ENV" --approval auto --quota 50 --interval 1 --unit minute --opgrp ./mcp-product-opgroup.json --org "$PROJECT" --token "$TOKEN"

echo "Creating CRM Product"
apigeecli products create --name crm-product --display-name "CRM Product" --envs "$APIGEE_ENV" --approval auto --quota 50 --interval 1 --unit minute --opgrp ./crm-product-opgroup.json --attrs hub_location=projects/$PROJECT/locations/$REGION --org "$PROJECT" --token "$TOKEN"

echo "Creating OMS Product"
apigeecli products create --name oms-product --display-name "OMS Product" --envs "$APIGEE_ENV" --approval auto --quota 50 --interval 1 --unit minute --opgrp ./oms-product-opgroup.json --attrs hub_location=projects/$PROJECT/locations/$REGION --org "$PROJECT" --token "$TOKEN"

echo "Creating WMS Product"
apigeecli products create --name wms-product --display-name "WMS Product" --envs "$APIGEE_ENV" --approval auto --quota 50 --interval 1 --unit minute --opgrp ./wms-product-opgroup.json --attrs hub_location=projects/$PROJECT/locations/$REGION --org "$PROJECT" --token "$TOKEN"


echo "Creating Developer"
apigeecli developers create --user consumer --email mcpconsumer@cymbal.com --first Consumer --last Doe --org "$PROJECT" --token "$TOKEN"

echo "Creating Developer App"
apigeecli apps create --name sample-mcp-consumer-app --email mcpconsumer@cymbal.com --prods mcp-product --callback https://developers.google.com/oauthplayground/ --org "$PROJECT" --token "$TOKEN" --disable-check

TOKEN_AUDIENCE=$(apigeecli apps get --name sample-mcp-consumer-app --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."[0].credentials[0].consumerKey" -r)
IDP_APP_CLIENT_ID="$TOKEN_AUDIENCE"
IDP_APP_CLIENT_SECRET=$(apigeecli apps get --name sample-mcp-consumer-app --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."[0].credentials[0].consumerSecret" -r)

echo "--------------------------------------------------"
echo "MCP Consumer Client ID: $IDP_APP_CLIENT_ID"
echo "MCP Consumer Client Secret: $IDP_APP_CLIENT_SECRET"
