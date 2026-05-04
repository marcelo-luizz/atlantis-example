#!/bin/bash
# Script para configurar autenticação GCP para Atlantis
# Estratégia: Service Account no projeto de management com impersonation para cada ambiente

set -euo pipefail

MGMT_PROJECT="jeitto-mgmt"
ATLANTIS_SA="atlantis-sa"
ENVIRONMENTS=("dev" "homolog" "prod")
GKE_NAMESPACE="atlantis"
K8S_SA="atlantis"

echo "=== 1. Criar Service Account principal no projeto de management ==="
gcloud iam service-accounts create ${ATLANTIS_SA} \
  --project=${MGMT_PROJECT} \
  --display-name="Atlantis Terraform SA"

echo "=== 2. Configurar Workload Identity (GKE -> GCP SA) ==="
gcloud iam service-accounts add-iam-policy-binding \
  ${ATLANTIS_SA}@${MGMT_PROJECT}.iam.gserviceaccount.com \
  --project=${MGMT_PROJECT} \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${MGMT_PROJECT}.svc.id.goog[${GKE_NAMESPACE}/${K8S_SA}]"

echo "=== 3. Para cada ambiente, criar SA local e permitir impersonation ==="
for ENV in "${ENVIRONMENTS[@]}"; do
  PROJECT="jeitto-${ENV}"
  
  # Criar SA no projeto do ambiente
  gcloud iam service-accounts create ${ATLANTIS_SA} \
    --project=${PROJECT} \
    --display-name="Atlantis SA for ${ENV}"

  # Dar permissões necessárias no projeto
  gcloud projects add-iam-policy-binding ${PROJECT} \
    --member="serviceAccount:${ATLANTIS_SA}@${PROJECT}.iam.gserviceaccount.com" \
    --role="roles/editor"

  # Permitir que a SA do management impersone a SA do ambiente
  gcloud iam service-accounts add-iam-policy-binding \
    ${ATLANTIS_SA}@${PROJECT}.iam.gserviceaccount.com \
    --project=${PROJECT} \
    --role="roles/iam.serviceAccountTokenCreator" \
    --member="serviceAccount:${ATLANTIS_SA}@${MGMT_PROJECT}.iam.gserviceaccount.com"

  echo "  ✓ ${ENV} configurado"
done

echo "=== 4. Criar buckets de state ==="
for ENV in "${ENVIRONMENTS[@]}"; do
  PROJECT="jeitto-${ENV}"
  BUCKET="jeitto-tfstate-${ENV}"
  
  gsutil mb -p ${PROJECT} -l southamerica-east1 -b on gs://${BUCKET}/ 2>/dev/null || true
  gsutil versioning set on gs://${BUCKET}/
  
  echo "  ✓ gs://${BUCKET} criado com versionamento"
done

echo ""
echo "=== Setup completo! ==="
echo "Atlantis SA: ${ATLANTIS_SA}@${MGMT_PROJECT}.iam.gserviceaccount.com"
echo "Impersona SAs por ambiente via GOOGLE_IMPERSONATE_SERVICE_ACCOUNT"
