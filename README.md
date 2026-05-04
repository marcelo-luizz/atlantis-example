# GitOps Platform Engineering: Terraform + Atlantis + Backstage

## Visão Geral da Arquitetura

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐     ┌─────────┐
│  Backstage  │────▶│  GitHub PR       │────▶│  Atlantis       │────▶│  GCP    │
│  (Portal)   │     │  (gitops-*-infra)│     │  (Plan/Apply)   │     │         │
└─────────────┘     └──────────────────┘     └─────────────────┘     └─────────┘
```

**Fluxo:**
1. Dev preenche formulário no Backstage (bucket, pubsub, gke, sql...)
2. Backstage gera arquivo `.tf` e abre PR no repo correto (app-infra ou core-infra)
3. Atlantis detecta o PR, roda `terraform plan` e comenta no PR
4. Após aprovação e merge, Atlantis roda `terraform apply`
5. State é armazenado remotamente no GCS (um bucket por ambiente)

---

## Estrutura dos Repositórios GitOps

```
gitops-app-infra/          (ou gitops-core-infra/)
├── atlantis.yaml          # Config global do Atlantis
├── environments/
│   ├── dev/
│   │   └── southamerica-east1/
│   │       └── teams/
│   │           ├── team-a/
│   │           │   ├── bucket/
│   │           │   │   └── my-bucket/
│   │           │   │       ├── main.tf
│   │           │   │       ├── backend.tf
│   │           │   │       └── terraform.tfvars
│   │           │   ├── pubsub/
│   │           │   └── sql/
│   │           └── team-b/
│   ├── homolog/
│   │   └── ...
│   └── prod/
│       └── ...
└── modules/               # (opcional, ou referencia módulos externos)
```

---

## State Management (Arquivos de Estado)

**Estratégia: 1 state file por recurso**

Cada pasta de recurso tem seu próprio `backend.tf` apontando para um bucket GCS dedicado ao ambiente. Isso garante:
- Isolamento total entre recursos
- Lock granular (sem contenção)
- Blast radius mínimo

### Buckets de State:
| Ambiente | Bucket de State |
|----------|----------------|
| dev | `gs://jeitto-tfstate-dev` |
| homolog | `gs://jeitto-tfstate-homolog` |
| prod | `gs://jeitto-tfstate-prod` |

---

## Autenticação Multi-Ambiente

### Opção Recomendada: Workload Identity Federation (WIF)

Atlantis roda em GKE e usa **diferentes Service Accounts** por ambiente via WIF:

| Ambiente | GCP Project | Service Account |
|----------|------------|-----------------|
| dev | jeitto-dev | atlantis-sa@jeitto-dev.iam.gserviceaccount.com |
| homolog | jeitto-homolog | atlantis-sa@jeitto-homolog.iam.gserviceaccount.com |
| prod | jeitto-prod | atlantis-sa@jeitto-prod.iam.gserviceaccount.com |

O Atlantis seleciona a SA correta baseado no path do workspace (extraído do `atlantis.yaml`).

---

## Instalação do Atlantis

Ver arquivos neste diretório:
- `atlantis/helm-values.yaml` - Instalação via Helm no GKE
- `atlantis/atlantis.yaml` - Configuração do repo
- `atlantis/server-side-repo-config.yaml` - Workflows customizados

---

## Manutenção

- **Upgrade:** Helm upgrade do chart
- **Logs:** `kubectl logs -f deploy/atlantis -n atlantis`
- **Lock de state:** Gerenciado automaticamente pelo GCS backend
- **Drift detection:** Cron job que roda `terraform plan` e alerta no Slack
