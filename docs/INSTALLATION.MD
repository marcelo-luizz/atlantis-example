# Passo a Passo: Instalação Completa do Atlantis com GitHub App

## Índice
1. [Criar GitHub App](#1-criar-github-app)
2. [Configurar Webhook](#2-configurar-webhook)
3. [Instalar GitHub App nos Repos](#3-instalar-github-app-nos-repos)
4. [Preparar GCP (Auth + State Buckets)](#4-preparar-gcp)
5. [Instalar Atlantis no GKE](#5-instalar-atlantis-no-gke)
6. [Validar Instalação](#6-validar-instalação)
7. [Configurar Repos GitOps](#7-configurar-repos-gitops)
8. [Teste End-to-End](#8-teste-end-to-end)

---

## 1. Criar GitHub App

### 1.1 Acessar GitHub

```
https://github.com/organizations/marcelo-luizz/settings/apps/new
```

> Se for conta pessoal: `https://github.com/settings/apps/new`

### 1.2 Preencher os campos

| Campo | Valor |
|-------|-------|
| **GitHub App name** | `atlantis-jeitto` |
| **Homepage URL** | `https://atlantis.jeitto.internal` |
| **Webhook URL** | `https://atlantis.jeitto.internal/events` |
| **Webhook secret** | Gere um: `openssl rand -hex 32` (guarde esse valor!) |

### 1.3 Permissões necessárias (Repository permissions)

| Permissão | Nível |
|-----------|-------|
| **Contents** | Read & Write |
| **Issues** | Read & Write |
| **Pull requests** | Read & Write |
| **Commit statuses** | Read & Write |
| **Checks** | Read & Write |
| **Metadata** | Read-only |
| **Administration** | Read-only (opcional, para criar webhooks automaticamente) |

### 1.4 Subscribe to events (Webhook)

Marque:
- [x] **Pull request**
- [x] **Pull request review**
- [x] **Pull request review comment**
- [x] **Issue comment** (para comandos `atlantis plan`, `atlantis apply`)
- [x] **Push**

### 1.5 Onde instalar

Selecione: **Only on this account**

### 1.6 Clicar em "Create GitHub App"

### 1.7 Anotar os valores

Após criar, você verá a página do App. Anote:

```
App ID:           123456          ← aparece no topo da página
```

### 1.8 Gerar Private Key

Na mesma página do App, role até o final e clique em **"Generate a private key"**.

Um arquivo `.pem` será baixado. **Guarde com segurança!**

```bash
# Renomear para facilitar
mv ~/Downloads/atlantis-jeitto.*.private-key.pem ~/atlantis-github-app-key.pem
```

---

## 2. Configurar Webhook

O webhook URL é: `https://atlantis.jeitto.internal/events`

> **Nota:** Se o Atlantis ainda não está instalado, o webhook vai falhar inicialmente. Isso é normal — o GitHub vai reenviar automaticamente quando o Atlantis subir.

Se você estiver testando localmente antes de ter DNS:
```bash
# Usar ngrok para teste local
ngrok http 4141
# Use a URL do ngrok como Webhook URL temporariamente
```

---

## 3. Instalar GitHub App nos Repos

### 3.1 Ir para Installation

```
https://github.com/organizations/marcelo-luizz/settings/installations
```

### 3.2 Clicar no App "atlantis-jeitto" → Configure

### 3.3 Selecionar repositórios

Selecione **"Only select repositories"** e adicione:
- `gitops-app-infra`
- `gitops-core-infra`

### 3.4 Anotar o Installation ID

Após instalar, a URL será algo como:
```
https://github.com/organizations/marcelo-luizz/settings/installations/12345678
                                                                       ^^^^^^^^
                                                                       Este é o Installation ID
```

---

## 4. Preparar GCP

### 4.1 Executar script de setup

```bash
cd /path/to/sugestao-atlantis-flow/atlantis/
chmod +x setup-gcp-auth.sh

# Revise os nomes de projetos no script antes de executar!
# Edite MGMT_PROJECT, e o padrão "jeitto-${ENV}" conforme seu ambiente real
vim setup-gcp-auth.sh

# Executar
./setup-gcp-auth.sh
```

Esse script irá:
- Criar Service Account `atlantis-sa` no projeto de management
- Configurar Workload Identity para o GKE
- Criar SAs em cada projeto de ambiente (dev, homolog, prod)
- Configurar impersonation
- Criar buckets de state com versionamento

### 4.2 Verificar buckets criados

```bash
gsutil ls gs://jeitto-tfstate-dev/
gsutil ls gs://jeitto-tfstate-homolog/
gsutil ls gs://jeitto-tfstate-prod/
```

### 4.3 Verificar SAs

```bash
for env in dev homolog prod; do
  echo "=== jeitto-${env} ==="
  gcloud iam service-accounts list --project=jeitto-${env} --filter="email:atlantis"
done
```

---

## 5. Instalar Atlantis no GKE

### 5.1 Pré-requisitos no cluster

```bash
# Garantir que está conectado ao cluster de management
gcloud container clusters get-credentials <cluster-name> \
  --region southamerica-east1 \
  --project jeitto-mgmt

# Criar namespace
kubectl create namespace atlantis
```

### 5.2 Criar Secret com a Private Key do GitHub App

```bash
# Usar os valores anotados nos passos anteriores
WEBHOOK_SECRET="<valor-gerado-no-passo-1.2>"
PEM_FILE="$HOME/atlantis-github-app-key.pem"

kubectl create secret generic atlantis-github-app \
  --from-file=key.pem=${PEM_FILE} \
  --from-literal=webhook-secret=${WEBHOOK_SECRET} \
  -n atlantis
```

### 5.3 Editar helm-values.yaml com seus valores reais

```bash
cd /path/to/sugestao-atlantis-flow/atlantis/

# Substituir os placeholders pelos valores reais:
# - 000000 pelo App ID (2 lugares)
# - 00000000 pelo Installation ID
# - atlantis-jeitto pelo slug do seu app
vim helm-values.yaml
```

### 5.4 Instalar com Helm

```bash
# Adicionar repo
helm repo add runatlantis https://runatlantis.github.io/helm-charts
helm repo update

# Instalar
helm install atlantis runatlantis/atlantis \
  -n atlantis \
  -f helm-values.yaml

# Verificar
kubectl get pods -n atlantis -w
```

### 5.5 Verificar logs

```bash
# Aguardar o pod ficar Running
kubectl logs -f deploy/atlantis -n atlantis

# Deve aparecer algo como:
# "Successfully fetched GitHub App token"
# "Listening on port 4141"
```

### 5.6 Configurar DNS / Ingress

Se usar nginx-ingress:
```bash
# Verificar que o ingress foi criado
kubectl get ingress -n atlantis

# Pegar o IP do LoadBalancer
kubectl get svc -n ingress-nginx

# Criar registro DNS: atlantis.jeitto.internal → IP do LB
```

---

## 6. Validar Instalação

### 6.1 Testar acesso à UI

```bash
curl -s https://atlantis.jeitto.internal/healthz
# Deve retornar: {"status":"ok"}
```

### 6.2 Verificar webhook

Vá em **GitHub App → Advanced → Recent Deliveries**

Deve mostrar `200 OK` para o ping event.

### 6.3 Verificar autenticação GCP

```bash
kubectl exec -it deploy/atlantis -n atlantis -- sh

# Dentro do pod:
# Testar se o Workload Identity funciona
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
# Deve mostrar: atlantis-sa@jeitto-mgmt.iam.gserviceaccount.com
```

---

## 7. Configurar Repos GitOps

### 7.1 Copiar atlantis.yaml para os repos

```bash
# Para cada repo (gitops-app-infra e gitops-core-infra):
cp atlantis/atlantis.yaml /path/to/gitops-app-infra/atlantis.yaml
cp atlantis/atlantis.yaml /path/to/gitops-core-infra/atlantis.yaml

# Commitar e pushar
cd /path/to/gitops-app-infra
git add atlantis.yaml
git commit -m "chore: add atlantis config"
git push
```

### 7.2 Estrutura final do repo GitOps

```
gitops-app-infra/
├── atlantis.yaml           ← Config do Atlantis
├── environments/
│   ├── dev/
│   │   └── southamerica-east1/
│   │       └── teams/
│   ├── homolog/
│   └── prod/
└── README.md
```

---

## 8. Teste End-to-End

### 8.1 Criar um bucket de teste via Backstage (ou manualmente)

Se o Backstage ainda não está configurado, teste manualmente:

```bash
cd /path/to/gitops-app-infra
git checkout -b feat/bucket-test-atlantis-dev

# Criar diretório
mkdir -p environments/dev/southamerica-east1/teams/team-platform/bucket/test-atlantis/

# Criar main.tf (sem templates do Backstage, valores reais)
cat > environments/dev/southamerica-east1/teams/team-platform/bucket/test-atlantis/main.tf << 'EOF'
module "bucket" {
  source = "git::https://github.com/marcelo-luizz/terraform-modules.git//gcp/gcs-bucket?ref=v1.0.0"

  bucket_name   = "test-atlantis"
  project_id    = "jeitto-dev"
  region        = "southamerica-east1"
  environment   = "dev"
  team          = "team-platform"
  storage_class = "STANDARD"
  versioning    = false

  labels = {
    team        = "team-platform"
    environment = "dev"
    managed_by  = "atlantis"
    created_by  = "manual-test"
  }
}
EOF

cat > environments/dev/southamerica-east1/teams/team-platform/bucket/test-atlantis/backend.tf << 'EOF'
terraform {
  backend "gcs" {
    bucket = "jeitto-tfstate-dev"
    prefix = "environments/dev/southamerica-east1/teams/team-platform/bucket/test-atlantis"
  }

  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "jeitto-dev"
  region  = "southamerica-east1"
}
EOF

git add .
git commit -m "feat(gcs): add test bucket for atlantis validation"
git push origin feat/bucket-test-atlantis-dev
```

### 8.2 Abrir PR no GitHub

Abra o PR de `feat/bucket-test-atlantis-dev` → `main`

### 8.3 Observar o Atlantis

Dentro de ~30 segundos:
1. Atlantis comenta no PR com o **terraform plan**
2. Revise o plan
3. Comente no PR: `atlantis apply`
4. Atlantis executa o apply e comenta com o resultado

### 8.4 Verificar o recurso criado

```bash
gsutil ls gs://test-atlantis/ 2>/dev/null || echo "Bucket não existe (verifique o nome com projeto)"
gcloud storage buckets describe gs://test-atlantis --project=jeitto-dev
```

### 8.5 Cleanup

```bash
# Comentar no PR: atlantis plan -d environments/dev/.../test-atlantis -- -destroy
# Ou deletar a pasta e abrir outro PR
```

---

## Troubleshooting

| Problema | Solução |
|----------|---------|
| Webhook retorna 404 | Verificar URL: deve ser `/events` não `/webhook` |
| "Could not authenticate" | Verificar App ID, Installation ID e que o .pem está correto |
| "Permission denied" no GCP | Verificar Workload Identity e impersonation SAs |
| Plan não roda automaticamente | Verificar que `atlantis.yaml` está na raiz do repo e os paths batem |
| Lock stuck | Acessar UI `https://atlantis.jeitto.internal/locks` e fazer unlock |
| Pod CrashLooping | `kubectl logs deploy/atlantis -n atlantis --previous` |

---

## Próximos Passos

- [ ] Configurar Backstage templates apontando para os repos corretos
- [ ] Adicionar mais módulos Terraform (pubsub, sql, gke...)
- [ ] Configurar CODEOWNERS nos repos GitOps
- [ ] Adicionar OPA/Conftest para policy enforcement
- [ ] Configurar alertas (Slack/Teams) para plans e applies
- [ ] Criar runbook de operação do Atlantis
