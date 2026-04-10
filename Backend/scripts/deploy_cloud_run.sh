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
  CLOUD_SQL_INSTANCE=project:region:instance \
  TRAI_DATABASE_URL=postgresql://... \
  ./scripts/deploy_cloud_run.sh

  or

  PROJECT_ID=... \
  SERVICE_NAME=... \
  IMAGE_NAME=... \
  IMAGE_TAG=... \
  TRAI_ENVIRONMENT=staging|production \
  CLOUD_SQL_INSTANCE=project:region:instance \
  DATABASE_URL_SECRET_NAME=TRAI_DATABASE_URL_PRODUCTION \
  ./scripts/deploy_cloud_run.sh

Required environment variables:
  PROJECT_ID
  SERVICE_NAME
  IMAGE_NAME
  IMAGE_TAG
  TRAI_ENVIRONMENT
  CLOUD_SQL_INSTANCE

Optional environment variables:
  REGION                         default: us-central1
  REPOSITORY                     default: trai-backend
  TRAI_AI_PROVIDER               default: openai
  GEMINI_MODEL                   default: gemini-3-flash-preview
  OPENAI_MODEL                   default: gpt-5.4-mini
  APPLE_EXPECTED_AUDIENCES       default: Nadav.Trai
  APP_STORE_EXPECTED_BUNDLE_IDS  default: Nadav.Trai
  GEMINI_SECRET_NAME             default: GEMINI_API_KEY
  OPENAI_SECRET_NAME             default: OPENAI_API_KEY
  ADMIN_SECRET_NAME              default: TRAI_ADMIN_API_KEY
  DATABASE_URL_SECRET_NAME       optional Secret Manager secret name for TRAI_DATABASE_URL
  DATABASE_SSL_MODE              default: disable
EOF
}

required_vars=(
  PROJECT_ID
  SERVICE_NAME
  IMAGE_NAME
  IMAGE_TAG
  TRAI_ENVIRONMENT
  CLOUD_SQL_INSTANCE
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required env var: ${var_name}" >&2
    usage
    exit 1
  fi
done

if [[ -z "${TRAI_DATABASE_URL:-}" && -z "${DATABASE_URL_SECRET_NAME:-}" ]]; then
  echo "You must set either TRAI_DATABASE_URL or DATABASE_URL_SECRET_NAME" >&2
  usage
  exit 1
fi

REGION="${REGION:-us-central1}"
REPOSITORY="${REPOSITORY:-trai-backend}"
TRAI_AI_PROVIDER="${TRAI_AI_PROVIDER:-openai}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3-flash-preview}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-5.4-mini}"
APPLE_EXPECTED_AUDIENCES="${APPLE_EXPECTED_AUDIENCES:-Nadav.Trai}"
APP_STORE_EXPECTED_BUNDLE_IDS="${APP_STORE_EXPECTED_BUNDLE_IDS:-Nadav.Trai}"
GEMINI_SECRET_NAME="${GEMINI_SECRET_NAME:-GEMINI_API_KEY}"
OPENAI_SECRET_NAME="${OPENAI_SECRET_NAME:-OPENAI_API_KEY}"
ADMIN_SECRET_NAME="${ADMIN_SECRET_NAME:-TRAI_ADMIN_API_KEY}"
DATABASE_SSL_MODE="${DATABASE_SSL_MODE:-disable}"

if [[ "${TRAI_ENVIRONMENT}" != "staging" && "${TRAI_ENVIRONMENT}" != "production" ]]; then
  echo "TRAI_ENVIRONMENT must be staging or production" >&2
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
if [[ -n "${DATABASE_URL_SECRET_NAME:-}" ]]; then
  secret_mappings="${secret_mappings},TRAI_DATABASE_URL=${DATABASE_URL_SECRET_NAME}:latest"
fi

env_mappings="HOST=0.0.0.0,TRAI_ENVIRONMENT=${TRAI_ENVIRONMENT},TRAI_AI_PROVIDER=${TRAI_AI_PROVIDER},TRAI_DATABASE_DRIVER=postgres,TRAI_DATABASE_SSL_MODE=${DATABASE_SSL_MODE},GEMINI_MODEL=${GEMINI_MODEL},OPENAI_MODEL=${OPENAI_MODEL},ALLOW_DEV_APPLE_BYPASS=false,APPLE_EXPECTED_AUDIENCES=${APPLE_EXPECTED_AUDIENCES},APP_STORE_EXPECTED_BUNDLE_IDS=${APP_STORE_EXPECTED_BUNDLE_IDS}"
if [[ -n "${TRAI_DATABASE_URL:-}" ]]; then
  env_mappings="${env_mappings},TRAI_DATABASE_URL=${TRAI_DATABASE_URL}"
fi

echo "Deploying ${SERVICE_NAME}"
gcloud run deploy "${SERVICE_NAME}" \
  --image "${IMAGE_URI}" \
  --region "${REGION}" \
  --allow-unauthenticated \
  --add-cloudsql-instances "${CLOUD_SQL_INSTANCE}" \
  --set-env-vars "${env_mappings}" \
  --set-secrets "${secret_mappings}"

echo
echo "Service URL:"
gcloud run services describe "${SERVICE_NAME}" \
  --region "${REGION}" \
  --format='value(status.url)'
