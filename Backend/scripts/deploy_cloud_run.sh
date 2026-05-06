#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  PROJECT_ID=... \
  SERVICE_NAME=... \
  IMAGE_NAME=... \
  IMAGE_TAG=... \
  TRAI_ENVIRONMENT=staging|production \
  TRAI_DATABASE_DRIVER=firestore \
  ./scripts/deploy_cloud_run.sh

Required environment variables:
  PROJECT_ID
  SERVICE_NAME
  IMAGE_NAME
  IMAGE_TAG
  TRAI_ENVIRONMENT

Optional environment variables:
  REGION                         default: us-central1
  REPOSITORY                     default: trai-backend
  TRAI_DATABASE_DRIVER           default: firestore
  MIN_INSTANCES                  default: 0
  MAX_INSTANCES                  optional Cloud Run cap, e.g. 3
  TRAI_AI_PROVIDER               default: openai
  GEMINI_MODEL                   default: gemini-3-flash-preview
  OPENAI_MODEL                   default: gpt-5.4-mini
  APPLE_EXPECTED_AUDIENCES       default: Nadav.Trai
  APP_STORE_EXPECTED_BUNDLE_IDS  default: Nadav.Trai
  GEMINI_SECRET_NAME             default: GEMINI_API_KEY
  OPENAI_SECRET_NAME             default: OPENAI_API_KEY
  ADMIN_SECRET_NAME              default: TRAI_ADMIN_API_KEY
EOF
}

required_vars=(
  PROJECT_ID
  SERVICE_NAME
  IMAGE_NAME
  IMAGE_TAG
  TRAI_ENVIRONMENT
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required env var: ${var_name}" >&2
    usage
    exit 1
  fi
done

REGION="${REGION:-us-central1}"
REPOSITORY="${REPOSITORY:-trai-backend}"
TRAI_DATABASE_DRIVER="${TRAI_DATABASE_DRIVER:-firestore}"
TRAI_AI_PROVIDER="${TRAI_AI_PROVIDER:-openai}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3-flash-preview}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-5.4-mini}"
APPLE_EXPECTED_AUDIENCES="${APPLE_EXPECTED_AUDIENCES:-Nadav.Trai}"
APP_STORE_EXPECTED_BUNDLE_IDS="${APP_STORE_EXPECTED_BUNDLE_IDS:-Nadav.Trai}"
GEMINI_SECRET_NAME="${GEMINI_SECRET_NAME:-GEMINI_API_KEY}"
OPENAI_SECRET_NAME="${OPENAI_SECRET_NAME:-OPENAI_API_KEY}"
ADMIN_SECRET_NAME="${ADMIN_SECRET_NAME:-TRAI_ADMIN_API_KEY}"
MIN_INSTANCES="${MIN_INSTANCES:-0}"

if [[ "${TRAI_ENVIRONMENT}" != "staging" && "${TRAI_ENVIRONMENT}" != "production" ]]; then
  echo "TRAI_ENVIRONMENT must be staging or production" >&2
  exit 1
fi

if [[ "${TRAI_DATABASE_DRIVER}" != "firestore" ]]; then
  echo "TRAI_DATABASE_DRIVER must be firestore for Cloud Run deploys" >&2
  exit 1
fi

if [[ "${TRAI_AI_PROVIDER}" != "gemini" && "${TRAI_AI_PROVIDER}" != "openai" ]]; then
  echo "TRAI_AI_PROVIDER must be gemini or openai" >&2
  exit 1
fi

IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building ${IMAGE_URI}"
gcloud builds submit --tag "${IMAGE_URI}" .

secret_mappings="TRAI_ADMIN_API_KEY=${ADMIN_SECRET_NAME}:latest"
if [[ "${TRAI_AI_PROVIDER}" == "gemini" ]]; then
  secret_mappings="${secret_mappings},GEMINI_API_KEY=${GEMINI_SECRET_NAME}:latest"
else
  secret_mappings="${secret_mappings},OPENAI_API_KEY=${OPENAI_SECRET_NAME}:latest"
fi
env_mappings="HOST=0.0.0.0,TRAI_ENVIRONMENT=${TRAI_ENVIRONMENT},TRAI_AI_PROVIDER=${TRAI_AI_PROVIDER},TRAI_DATABASE_DRIVER=${TRAI_DATABASE_DRIVER},GEMINI_MODEL=${GEMINI_MODEL},OPENAI_MODEL=${OPENAI_MODEL},ALLOW_DEV_APPLE_BYPASS=false,APPLE_EXPECTED_AUDIENCES=${APPLE_EXPECTED_AUDIENCES},APP_STORE_EXPECTED_BUNDLE_IDS=${APP_STORE_EXPECTED_BUNDLE_IDS}"

echo "Deploying ${SERVICE_NAME}"
deploy_args=(
  run deploy "${SERVICE_NAME}"
  --image "${IMAGE_URI}" \
  --region "${REGION}" \
  --allow-unauthenticated \
  --clear-cloudsql-instances \
  --min-instances "${MIN_INSTANCES}" \
  --remove-env-vars "TRAI_DATABASE_URL,DATABASE_URL,TRAI_DATABASE_SSL_MODE,PGSSLMODE" \
  --remove-secrets "TRAI_DATABASE_URL,DATABASE_URL" \
  --update-env-vars "${env_mappings}" \
  --update-secrets "${secret_mappings}"
)

if [[ -n "${MAX_INSTANCES:-}" ]]; then
  deploy_args+=(--max-instances "${MAX_INSTANCES}")
fi

gcloud "${deploy_args[@]}"

echo
echo "Service URL:"
gcloud run services describe "${SERVICE_NAME}" \
  --region "${REGION}" \
  --format='value(status.url)'
