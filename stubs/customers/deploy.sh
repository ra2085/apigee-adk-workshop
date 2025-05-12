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

DEFAULT_IMAGE_URL="gcr.io/apigee-hw/customers-service:latest"
DEFAULT_SERVICE_NAME="customers-service" # Default service name if IMAGE_NAME is not provided

# Target image and service name for deployment
TARGET_IMAGE_URL=""
TARGET_SERVICE_NAME=""

# Check for REGION early, as it's always required for deployment
if [ -z "$REGION" ]; then
  echo "ERROR: No REGION variable set. Please set it to your Cloud Run region."
  exit 1
fi

# Determine image and service name based on REPO_PROJECT_ID and IMAGE_NAME
if [ -n "$REPO_PROJECT_ID" ] && [ -n "$IMAGE_NAME" ]; then
  # Both REPO_PROJECT_ID and IMAGE_NAME are provided, build and push custom image
  echo "INFO: REPO_PROJECT_ID and IMAGE_NAME are set. Building and pushing custom image."
  TARGET_IMAGE_URL="gcr.io/${REPO_PROJECT_ID}/${IMAGE_NAME}:latest"
  TARGET_SERVICE_NAME="${IMAGE_NAME}"

  echo "Building docker image: $TARGET_IMAGE_URL"
  # Build the image locally
  docker build -t "$TARGET_IMAGE_URL" .
  if [ $? -ne 0 ]; then
    echo "ERROR: Docker build failed for $TARGET_IMAGE_URL."
    exit 1
  fi

  echo "Pushing docker image: $TARGET_IMAGE_URL"
  # Push the image to Artifact Registry
  docker push "$TARGET_IMAGE_URL"
  if [ $? -ne 0 ]; then
    echo "ERROR: Docker push failed for $TARGET_IMAGE_URL."
    exit 1
  fi
else
  # Either REPO_PROJECT_ID or IMAGE_NAME (or both) are not set. Use default image.
  echo "INFO: REPO_PROJECT_ID or IMAGE_NAME (or both) not provided. Using default image: $DEFAULT_IMAGE_URL."
  TARGET_IMAGE_URL="$DEFAULT_IMAGE_URL"

  if [ -n "$IMAGE_NAME" ]; then
    # IMAGE_NAME was provided, but REPO_PROJECT_ID was not. Use IMAGE_NAME for the service.
    echo "INFO: Using provided IMAGE_NAME '${IMAGE_NAME}' for the service name with the default image."
    TARGET_SERVICE_NAME="${IMAGE_NAME}"
  else
    # IMAGE_NAME was not provided. Use default service name.
    echo "INFO: Using default service name '${DEFAULT_SERVICE_NAME}' with the default image."
    TARGET_SERVICE_NAME="${DEFAULT_SERVICE_NAME}"
  fi
fi

echo "Deploying service '${TARGET_SERVICE_NAME}' using image '${TARGET_IMAGE_URL}' to region '${REGION}'..."
gcloud run deploy "${TARGET_SERVICE_NAME}" \
    --image="${TARGET_IMAGE_URL}" \
    --platform="managed" \
    --region="${REGION}" \
    --no-allow-unauthenticated \
    --port=5001

if [ $? -ne 0 ]; then
  echo "ERROR: gcloud run deploy failed for service '${TARGET_SERVICE_NAME}'."
  exit 1
fi

echo "Service '${TARGET_SERVICE_NAME}' deployed."

echo "Fetching service URL..."
CUSTOMERS_API_CR_URL=$(gcloud run services describe "${TARGET_SERVICE_NAME}" \
    --platform="managed" \
    --region="${REGION}" \
    --format="value(status.url)")

export CUSTOMERS_API_CR_URL

echo "Service URL: ${CUSTOMERS_API_CR_URL}"
echo "The service URL has also been exported as CUSTOMERS_API_CR_URL."
