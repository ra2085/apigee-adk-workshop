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

# --- Helper Functions ---

gen_key_pairs() {
  if [ -z "$PR_KEY" ]; then
    echo "INFO: PR_KEY not set. Generating new RSA key pair (4096-bit)."
    PR_KEY=$(openssl genrsa 4096)
    if [ $? -ne 0 ] || [ -z "$PR_KEY" ]; then
        echo "ERROR: Failed to generate private key."
        exit 1
    fi
    echo "INFO: Private key generated."
    
    PU_KEY=$(printf '%s\n' "$PR_KEY" | openssl rsa -outform PEM -pubout)
    if [ $? -ne 0 ] || [ -z "$PU_KEY" ]; then
        echo "ERROR: Failed to generate public key from private key."
        exit 1
    fi
    echo "INFO: Public key generated."

    # Remove newlines for storage/use in properties
    PR_KEY=$(printf '%s\n' "$PR_KEY" | tr -d '\n')
    PU_KEY=$(printf '%s\n' "$PU_KEY" | tr -d '\n')
    echo "INFO: Keys processed for single-line use."
  else
    echo "INFO: Using provided PR_KEY. Assuming PU_KEY is also correctly set or will be derived if needed by other parts (not derived here if PR_KEY is pre-set)."
  fi
}

deploy_stub_service() {
  local service_dir_name="$1"
  local service_var_prefix="$2"
  local output_url_env_var_name="$3"
  local friendly_service_name="$4"

  echo "--------------------------------------------------"
  echo "Deploying ${friendly_service_name} Stub Service..."
  echo "--------------------------------------------------"

  local stub_dir_path="./stubs/${service_dir_name}"
  if [ ! -d "$stub_dir_path" ]; then
    echo "ERROR: Directory ${stub_dir_path} not found. Ensure you are running this script from the 'mcp_go' root directory."
    exit 1
  fi
  
  pushd "$stub_dir_path" > /dev/null
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to navigate to directory $stub_dir_path."
    exit 1
  fi

  local default_image_url="gcr.io/apigee-hw/${service_dir_name}-service:latest"
  local default_service_name="${service_dir_name}-service"

  local target_image_url=""
  local target_service_name=""

  if [ -z "$REGION" ]; then
    echo "ERROR: REGION variable not set. Required for Cloud Run deployment of ${friendly_service_name}."
    popd > /dev/null
    exit 1
  fi

  local custom_image_name_var_ref="${service_var_prefix}_IMAGE_NAME"
  local custom_image_name="${!custom_image_name_var_ref}"

  if [ -n "$REPO_PROJECT_ID" ] && [ -n "$custom_image_name" ]; then
    echo "INFO: REPO_PROJECT_ID ('$REPO_PROJECT_ID') and ${custom_image_name_var_ref} ('${custom_image_name}') are set. Building and pushing custom image for ${friendly_service_name}."
    target_image_url="gcr.io/${REPO_PROJECT_ID}/${custom_image_name}:latest"
    target_service_name="${custom_image_name}"

    echo "Building docker image: $target_image_url (from $(pwd))"
    docker build -t "$target_image_url" .
    if [ $? -ne 0 ]; then
      echo "ERROR: Docker build failed for $target_image_url."
      popd > /dev/null
      exit 1
    fi

    echo "Pushing docker image: $target_image_url"
    docker push "$target_image_url"
    if [ $? -ne 0 ]; then
      echo "ERROR: Docker push failed for $target_image_url."
      popd > /dev/null
      exit 1
    fi
  else
    echo "INFO: REPO_PROJECT_ID or ${custom_image_name_var_ref} (or both) not provided for ${friendly_service_name}. Using default image settings."
    target_image_url="$default_image_url"

    if [ -n "$custom_image_name" ]; then
      echo "INFO: Using provided ${custom_image_name_var_ref} ('${custom_image_name}') for the service name with the default image for ${friendly_service_name}."
      target_service_name="${custom_image_name}"
    else
      echo "INFO: Using default service name '${default_service_name}' with the default image for ${friendly_service_name}."
      target_service_name="${default_service_name}"
    fi
  fi

  echo "Deploying service '${target_service_name}' for ${friendly_service_name} using image '${target_image_url}' to region '${REGION}'..."
  gcloud run deploy "${target_service_name}" \
      --image="${target_image_url}" \
      --platform="managed" \
      --region="${REGION}" \
      --no-allow-unauthenticated \
      --port=5001 \
      --quiet
  
  if [ $? -ne 0 ]; then
    echo "ERROR: gcloud run deploy failed for service '${target_service_name}' (${friendly_service_name})."
    popd > /dev/null
    exit 1
  fi

  echo "Service '${target_service_name}' (${friendly_service_name}) deployed."

  echo "Fetching service URL for ${friendly_service_name}..."
  local service_url
  service_url=$(gcloud run services describe "${target_service_name}" \
      --platform="managed" \
      --region="${REGION}" \
      --format="value(status.url)")

  if [ -z "$service_url" ]; then
    echo "ERROR: Failed to fetch service URL for '${target_service_name}' (${friendly_service_name})."
    popd > /dev/null
    exit 1
  fi

  export "${output_url_env_var_name}=${service_url}"

  echo "${friendly_service_name} Service URL: ${service_url}"
  echo "The service URL has also been exported as ${output_url_env_var_name}."

  popd > /dev/null
  echo "--------------------------------------------------"
  echo "${friendly_service_name} Stub Service deployment complete."
  echo "--------------------------------------------------"
}

# --- Variable Checks ---
echo "Performing environment variable checks..."
REQUIRED_VARS=(
    "PROJECT"
    "REGION"
    "APIGEE_ENV"
    "APIGEE_HOST"
    "SA_EMAIL"
)
ALL_VARS_SET=true
for var_name in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var_name}" ]; then
    echo "ERROR: No ${var_name} variable set. Please set it."
    ALL_VARS_SET=false
  fi
done

if [ "$ALL_VARS_SET" = false ]; then
  echo "ERROR: One or more required environment variables are missing. Exiting."
  exit 1
fi
echo "All required global variables are set."

if [ -z "$TOKEN" ]; then
  echo "INFO: No TOKEN variable set. Attempting to fetch from gcloud."
  TOKEN=$(gcloud auth print-access-token)
  if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get gcloud access token. Please login or set the TOKEN variable."
    exit 1
  fi
  echo "INFO: Successfully fetched gcloud access token."
fi

# --- Main Script ---

echo "Installing apigeecli..."
curl -s https://raw.githubusercontent.com/apigee/apigeecli/main/downloadLatest.sh | bash
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to download/install apigeecli."
    exit 1
fi
export PATH=$PATH:$HOME/.apigeecli/bin
echo "apigeecli installed and PATH updated."

# Determine sed in-place arguments for portability (macOS vs Linux)
sedi_args=("-i")
if [[ "$(uname)" == "Darwin" ]]; then
  sedi_args=("-i" "") # For macOS, sed -i requires an extension argument. "" means no backup.
fi

gen_key_pairs
if [ -z "$PR_KEY" ] || [ -z "$PU_KEY" ]; then
    echo "ERROR: Private or Public key not available after gen_key_pairs. Exiting."
    exit 1
fi
echo "Key pairs are ready."


gcloud config set project $PROJECT
# Deploy Stub Services
deploy_stub_service "customers" "CUSTOMERS" "CUSTOMERS_API_CR_URL" "Customers"
deploy_stub_service "orders" "ORDERS" "ORDERS_API_CR_URL" "Orders"
deploy_stub_service "product" "PRODUCTS" "PRODUCTS_API_CR_URL" "Product Catalog"
deploy_stub_service "shipping-carrier" "SHIPPING" "SHIPPING_API_CR_URL" "Shipping Carrier"
deploy_stub_service "warehouse-orders" "WAREHOUSE" "WAREHOUSE_API_CR_URL" "Warehouse Orders"

echo "Verifying all stub service URLs are set..."
REQUIRED_STUB_URLS=(
  "CUSTOMERS_API_CR_URL"
  "ORDERS_API_CR_URL"
  "PRODUCTS_API_CR_URL"
  "SHIPPING_API_CR_URL"
  "WAREHOUSE_API_CR_URL"
)
ALL_STUB_URLS_SET=true
for var_name in "${REQUIRED_STUB_URLS[@]}"; do
  if [ -z "${!var_name}" ]; then
    echo "ERROR: ${var_name} is not set. Deployment of stub service might have failed."
    ALL_STUB_URLS_SET=false
  else
    echo "INFO: ${var_name}=${!var_name}"
  fi
done

if [ "$ALL_STUB_URLS_SET" = false ]; then
  echo "ERROR: Not all stub service URLs were set. Aborting Apigee deployment."
  exit 1
fi
echo "All stub service URLs verified. Proceeding with Apigee deployment."

echo "Creating HUB resources ..."

sed "${sedi_args[@]}" "s/@APIGEE_HOST@/$APIGEE_HOST/g" ./apigee_bundles/specs/customers-api/spec.yaml
sed "${sedi_args[@]}" "s/@APIGEE_HOST@/$APIGEE_HOST/g" ./apigee_bundles/specs/orders-creation-api/spec.yaml
sed "${sedi_args[@]}" "s/@APIGEE_HOST@/$APIGEE_HOST/g" ./apigee_bundles/specs/product-catalog-and-availability-api/spec.yaml
sed "${sedi_args[@]}" "s/@APIGEE_HOST@/$APIGEE_HOST/g" ./apigee_bundles/specs/shipping-carrier-api/spec.yaml
sed "${sedi_args[@]}" "s/@APIGEE_HOST@/$APIGEE_HOST/g" ./apigee_bundles/specs/warehouse-management-system-api/spec.yaml

apigeecli apihub apis create -i customers-api -f ./apigee_bundles/specs/customers-api/api.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions create --api-id customers-api -i 1_0_0 -f ./apigee_bundles/specs/customers-api/version.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions specs create --api-id customers-api -d customers-api.yaml -i customers-api -v 1_0_0 -f ./apigee_bundles/specs/customers-api/spec.yaml --org "$PROJECT" -r "$REGION" --token "$TOKEN"

apigeecli apihub apis create -i orders-api -f ./apigee_bundles/specs/orders-creation-api/api.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions create --api-id orders-api -i 1_0_0 -f ./apigee_bundles/specs/orders-creation-api/version.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions specs create --api-id orders-api -d orders-api.yaml -i orders-api -v 1_0_0 -f ./apigee_bundles/specs/orders-creation-api/spec.yaml --org "$PROJECT" -r "$REGION" --token "$TOKEN"

apigeecli apihub apis create -i product-catalog-and-availability-api -f ./apigee_bundles/specs/product-catalog-and-availability-api/api.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions create --api-id product-catalog-and-availability-api -i 1_0_0 -f ./apigee_bundles/specs/product-catalog-and-availability-api/version.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions specs create --api-id product-catalog-and-availability-api -d product-catalog-and-availability-api.yaml -i product-catalog-and-availability-api -v 1_0_0 -f ./apigee_bundles/specs/product-catalog-and-availability-api/spec.yaml --org "$PROJECT" -r "$REGION" --token "$TOKEN"

apigeecli apihub apis create -i shipping-carrier-api -f ./apigee_bundles/specs/shipping-carrier-api/api.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions create --api-id shipping-carrier-api -i 1_0_0 -f ./apigee_bundles/specs/shipping-carrier-api/version.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions specs create --api-id shipping-carrier-api -d shipping-carrier-api.yaml -i shipping-carrier-api -v 1_0_0 -f ./apigee_bundles/specs/shipping-carrier-api/spec.yaml --org "$PROJECT" -r "$REGION" --token "$TOKEN"

apigeecli apihub apis create -i warehouse-management-system-api -f ./apigee_bundles/specs/warehouse-management-system-api/api.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions create --api-id warehouse-management-system-api -i 1_0_0 -f ./apigee_bundles/specs/warehouse-management-system-api/version.json --org "$PROJECT" -r "$REGION" --token "$TOKEN"
apigeecli apihub apis versions specs create --api-id warehouse-management-system-api -d warehouse-management-system-api.yaml -i warehouse-management-system-api -v 1_0_0 -f ./apigee_bundles/specs/warehouse-management-system-api/spec.yaml --org "$PROJECT" -r "$REGION" --token "$TOKEN"

echo "Configuring Apigee proxy target URLs..."
export CUSTOMERS_API_CR_URL="${CUSTOMERS_API_CR_URL#https://}"
export ORDERS_API_CR_URL="${ORDERS_API_CR_URL#https://}"
export PRODUCTS_API_CR_URL="${PRODUCTS_API_CR_URL#https://}"
export SHIPPING_API_CR_URL="${SHIPPING_API_CR_URL#https://}"
export WAREHOUSE_API_CR_URL="${WAREHOUSE_API_CR_URL#https://}"

sed "${sedi_args[@]}" "s/TARGETURL/$CUSTOMERS_API_CR_URL/g" ./apigee_bundles/apigee-mcp-products/customers-api/apiproxy/targets/default.xml
sed "${sedi_args[@]}" "s/TARGETURL/$ORDERS_API_CR_URL/g" ./apigee_bundles/apigee-mcp-products/order-creation-api/apiproxy/targets/default.xml
sed "${sedi_args[@]}" "s/TARGETURL/$PRODUCTS_API_CR_URL/g" ./apigee_bundles/apigee-mcp-products/product-catalog-and-availability-api/apiproxy/targets/default.xml
sed "${sedi_args[@]}" "s/TARGETURL/$SHIPPING_API_CR_URL/g" ./apigee_bundles/apigee-mcp-products/shipping-carrier-api/apiproxy/targets/default.xml
sed "${sedi_args[@]}" "s/TARGETURL/$WAREHOUSE_API_CR_URL/g" ./apigee_bundles/apigee-mcp-products/warehouse-management-system-api/apiproxy/targets/default.xml

echo "Deploying keypair configuration..."
echo -e "public_key=$PU_KEY\nprivate_key=$PR_KEY" >oauth_configuration.properties
apigeecli res create --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --name oauth_configuration --type properties --respath oauth_configuration.properties

echo "Importing and Deploying mcp-spec-tools ..."
REV=$(apigeecli apis create bundle -f ./apigee_bundles/apigee-mcp-products/mcp-spec-tools/apiproxy -n mcp-spec-tools --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name mcp-spec-tools --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying customers-api ..."
REV=$(apigeecli apis create bundle -f ./apigee_bundles/apigee-mcp-products/customers-api/apiproxy -n customers-api --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name customers-api --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying order-creation-api ..."
REV=$(apigeecli apis create bundle -f ./apigee_bundles/apigee-mcp-products/order-creation-api/apiproxy -n order-creation-api --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name order-creation-api --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying product-catalog-and-availability-api ..."
REV=$(apigeecli apis create bundle -f ./apigee_bundles/apigee-mcp-products/product-catalog-and-availability-api/apiproxy -n product-catalog-and-availability-api --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name product-catalog-and-availability-api --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying shipping-carrier-api ..."
REV=$(apigeecli apis create bundle -f ./apigee_bundles/apigee-mcp-products/shipping-carrier-api/apiproxy -n shipping-carrier-api --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name shipping-carrier-api --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying warehouse-management-system-api ..."
REV=$(apigeecli apis create bundle -f ./apigee_bundles/apigee-mcp-products/warehouse-management-system-api/apiproxy -n warehouse-management-system-api --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name warehouse-management-system-api --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Creating MCP Product"
apigeecli products create --name mcp-product --display-name "MCP Product" --envs "$APIGEE_ENV" --approval auto --quota 50 --interval 1 --unit minute --opgrp ./apigee_bundles/mcp-product-opgroup.json --org "$PROJECT" --token "$TOKEN"

echo "Creating CRM Product"
apigeecli products create --name crm-product --display-name "CRM Product" --envs "$APIGEE_ENV" --approval auto --quota 50 --interval 1 --unit minute --opgrp ./apigee_bundles/crm-product-opgroup.json --attrs "hub_location=projects/$PROJECT/locations/$REGION" --org "$PROJECT" --token "$TOKEN"

echo "Creating OMS Product"
apigeecli products create --name oms-product --display-name "OMS Product" --envs "$APIGEE_ENV" --approval auto --quota 50 --interval 1 --unit minute --opgrp ./apigee_bundles/oms-product-opgroup.json --attrs "hub_location=projects/$PROJECT/locations/$REGION" --org "$PROJECT" --token "$TOKEN"

echo "Creating WMS Product"
apigeecli products create --name wms-product --display-name "WMS Product" --envs "$APIGEE_ENV" --approval auto --quota 50 --interval 1 --unit minute --opgrp ./apigee_bundles/wms-product-opgroup.json --attrs "hub_location=projects/$PROJECT/locations/$REGION" --org "$PROJECT" --token "$TOKEN"

echo "Creating Developer"
apigeecli developers create --user consumer --email mcpconsumer@cymbal.com --first Consumer --last Doe --org "$PROJECT" --token "$TOKEN"

echo "Creating CRM Developer App"
apigeecli apps create --name crm-consumer-app --email mcpconsumer@cymbal.com --prods mcp-product,crm-product --callback https://developers.google.com/oauthplayground/ --org "$PROJECT" --token "$TOKEN" --disable-check

echo "Creating OMS Developer App"
apigeecli apps create --name oms-consumer-app --email mcpconsumer@cymbal.com --prods mcp-product,oms-product --callback https://developers.google.com/oauthplayground/ --org "$PROJECT" --token "$TOKEN" --disable-check

echo "Creating WMS Developer App"
apigeecli apps create --name wms-consumer-app --email mcpconsumer@cymbal.com --prods mcp-product,wms-product --callback https://developers.google.com/oauthplayground/ --org "$PROJECT" --token "$TOKEN" --disable-check


CRM_API_KEY=$(apigeecli apps get --name crm-consumer-app --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."[0].credentials[0].consumerKey" -r)
CRM_SECRET=$(apigeecli apps get --name crm-consumer-app --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."[0].credentials[0].consumerSecret" -r)

OMS_API_KEY=$(apigeecli apps get --name oms-consumer-app --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."[0].credentials[0].consumerKey" -r)
OMS_SECRET=$(apigeecli apps get --name oms-consumer-app --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."[0].credentials[0].consumerSecret" -r)

WMS_API_KEY=$(apigeecli apps get --name wms-consumer-app --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."[0].credentials[0].consumerKey" -r)
WMS_SECRET=$(apigeecli apps get --name wms-consumer-app --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."[0].credentials[0].consumerSecret" -r)

export PROJECT_ID="$PROJECT"
export REGION="$REGION"
export SERVICE_NAME="crm-mcp-service"
export MCP_BASE_URL_VALUE="https://$APIGEE_HOST/mcp"

export BASE_PATH="crm-mcp-proxy"
export MCP_CLIENT_ID_VALUE="$CRM_API_KEY"
export MCP_CLIENT_SECRET_VALUE="$CRM_SECRET"

gcloud run deploy ${SERVICE_NAME} \
  --image gcr.io/apigee-hw/apigee-mcp-service:latest \
  --platform managed \
  --region ${REGION} \
  --no-allow-unauthenticated \
  --set-env-vars "NODE_ENV=production" \
  --set-env-vars "MCP_MODE=SSE" \
  --set-env-vars "MCP_CLIENT_ID=${MCP_CLIENT_ID_VALUE}" \
  --set-env-vars "MCP_CLIENT_SECRET=${MCP_CLIENT_SECRET_VALUE}" \
  --set-env-vars "MCP_BASE_URL=${MCP_BASE_URL_VALUE}" \
  --set-env-vars "BASE_PATH=${BASE_PATH}"

export CRM_PROXY_CR_URL=$(gcloud run services describe "${SERVICE_NAME}" \
      --platform="managed" \
      --region="${REGION}" \
      --format="value(status.url)")

export SERVICE_NAME="oms-mcp-service"
export MCP_CLIENT_ID_VALUE="$OMS_API_KEY"
export MCP_CLIENT_SECRET_VALUE="$OMS_SECRET"

gcloud run deploy ${SERVICE_NAME} \
  --image gcr.io/apigee-hw/apigee-mcp-service:latest \
  --platform managed \
  --region ${REGION} \
  --no-allow-unauthenticated \
  --set-env-vars "NODE_ENV=production" \
  --set-env-vars "MCP_MODE=SSE" \
  --set-env-vars "MCP_CLIENT_ID=${MCP_CLIENT_ID_VALUE}" \
  --set-env-vars "MCP_CLIENT_SECRET=${MCP_CLIENT_SECRET_VALUE}" \
  --set-env-vars "MCP_BASE_URL=${MCP_BASE_URL_VALUE}" \
  --set-env-vars "BASE_PATH=${BASE_PATH}"

export OMS_PROXY_CR_URL=$(gcloud run services describe "${SERVICE_NAME}" \
      --platform="managed" \
      --region="${REGION}" \
      --format="value(status.url)")

export SERVICE_NAME="wms-mcp-service"
export MCP_CLIENT_ID_VALUE="$WMS_API_KEY"
export MCP_CLIENT_SECRET_VALUE="$WMS_SECRET"

gcloud run deploy ${SERVICE_NAME} \
  --image gcr.io/apigee-hw/apigee-mcp-service:latest \
  --platform managed \
  --region ${REGION} \
  --no-allow-unauthenticated \
  --set-env-vars "NODE_ENV=production" \
  --set-env-vars "MCP_MODE=SSE" \
  --set-env-vars "MCP_CLIENT_ID=${MCP_CLIENT_ID_VALUE}" \
  --set-env-vars "MCP_CLIENT_SECRET=${MCP_CLIENT_SECRET_VALUE}" \
  --set-env-vars "MCP_BASE_URL=${MCP_BASE_URL_VALUE}" \
  --set-env-vars "BASE_PATH=${BASE_PATH}"

export WMS_PROXY_CR_URL=$(gcloud run services describe "${SERVICE_NAME}" \
      --platform="managed" \
      --region="${REGION}" \
      --format="value(status.url)")

echo "Configuring Apigee MCP proxies target URLs..."
export CRM_PROXY_CR_URL="${CRM_PROXY_CR_URL#https://}"
export OMS_PROXY_CR_URL="${OMS_PROXY_CR_URL#https://}"
export WMS_PROXY_CR_URL="${WMS_PROXY_CR_URL#https://}"

sed "${sedi_args[@]}" "s/TARGETURL/$CRM_PROXY_CR_URL/g" ./apigee_bundles/apigee-mcp-products/crm-mcp-proxy/apiproxy/targets/default.xml
sed "${sedi_args[@]}" "s/TARGETURL/$OMS_PROXY_CR_URL/g" ./apigee_bundles/apigee-mcp-products/oms-mcp-proxy/apiproxy/targets/default.xml
sed "${sedi_args[@]}" "s/TARGETURL/$WMS_PROXY_CR_URL/g" ./apigee_bundles/apigee-mcp-products/wms-mcp-proxy/apiproxy/targets/default.xml

echo "Importing and Deploying crm-mcp-proxy ..."
REV=$(apigeecli apis create bundle -f ./apigee_bundles/apigee-mcp-products/crm-mcp-proxy/apiproxy -n crm-mcp-proxy --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name crm-mcp-proxy --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying oms-mcp-proxy ..."
REV=$(apigeecli apis create bundle -f ./apigee_bundles/apigee-mcp-products/oms-mcp-proxy/apiproxy -n oms-mcp-proxy --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name oms-mcp-proxy --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "Importing and Deploying wms-mcp-proxy ..."
REV=$(apigeecli apis create bundle -f ./apigee_bundles/apigee-mcp-products/wms-mcp-proxy/apiproxy -n wms-mcp-proxy --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
apigeecli apis deploy --wait --name wms-mcp-proxy --ovr --rev "$REV" --org "$PROJECT" --env "$APIGEE_ENV" --token "$TOKEN" --sa "$SA_EMAIL"

echo "--------------------------------------------------"
echo "CRM Consumer Client ID: $CRM_API_KEY"
echo "CRM Consumer Client Secret: $CRM_SECRET"
echo "OMS Consumer Client ID: $OMS_API_KEY"
echo "OMS Consumer Client Secret: $OMS_SECRET"
echo "WMS Consumer Client ID: $WMS_API_KEY"
echo "WMS Consumer Client Secret: $WMS_SECRET"
echo "--------------------------------------------------"
echo "All deployments and configurations complete."