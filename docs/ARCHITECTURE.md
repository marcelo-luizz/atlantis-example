# Arquitetura Detalhada

## Como Funciona o State

```
gs://jeitto-tfstate-dev/
├── environments/dev/southamerica-east1/teams/team-a/bucket/my-bucket/default.tfstate
├── environments/dev/southamerica-east1/teams/team-a/pubsub/my-topic/default.tfstate
└── environments/dev/southamerica-east1/teams/team-b/sql/my-db/default.tfstate

gs://jeitto-tfstate-homolog/
└── environments/homolog/.../default.tfstate

gs://jeitto-tfstate-prod/
└── environments/prod/.../default.tfstate
```

**Por que 1 state por recurso?**
- Atlantis faz lock por diretório, sem contenção entre times
- `terraform plan` é rápido (apenas 1 recurso)
- Destruir recurso = deletar pasta + state (simples)
- Sem risco de corromper state de outros recursos

---

## Fluxo Completo (Passo a Passo)

```
1. Dev acessa Backstage → Escolhe "Create GCS Bucket"
2. Preenche: name=logs-app, env=dev, team=team-a, repo=gitops-app-infra
3. Backstage renderiza skeleton/ com os valores
4. Backstage abre PR no gitops-app-infra:
   - Branch: feat/bucket-logs-app-dev
   - Path: environments/dev/southamerica-east1/teams/team-a/bucket/logs-app/
   - Arquivos: main.tf, backend.tf
5. Atlantis recebe webhook do PR
6. Atlantis detecta .tf em environments/dev/** → usa workflow "dev"
7. Atlantis impersona atlantis-sa@jeitto-dev.iam.gserviceaccount.com
8. Atlantis roda: terraform init + terraform plan
9. Atlantis comenta no PR com o plan output
10. Tech Lead aprova PR
11. Dev comenta: "atlantis apply"
12. Atlantis roda terraform apply
13. PR é auto-merged (opcional)
```

---

## Autenticação - Diagrama

```
┌─────────────────────────────────────────────────────────┐
│ GKE Cluster (jeitto-mgmt)                               │
│                                                         │
│  ┌─────────────────┐    Workload Identity               │
│  │ Atlantis Pod    │◄──────────────────────┐            │
│  │ (K8s SA)        │                       │            │
│  └────────┬────────┘                       │            │
│           │                                │            │
└───────────┼────────────────────────────────┼────────────┘
            │ impersonate                    │
            ▼                                ▼
┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
│ jeitto-dev        │  │ jeitto-homolog    │  │ jeitto-prod       │
│                   │  │                   │  │                   │
│ atlantis-sa@      │  │ atlantis-sa@      │  │ atlantis-sa@      │
│ jeitto-dev.iam    │  │ jeitto-homolog.iam│  │ jeitto-prod.iam   │
│                   │  │                   │  │                   │
│ Role: Editor      │  │ Role: Editor      │  │ Role: Editor      │
└───────────────────┘  └───────────────────┘  └───────────────────┘
```

---

## Adicionando Novos Ambientes (ex: staging, sandbox)

1. Criar projeto GCP: `jeitto-staging`
2. Rodar script `setup-gcp-auth.sh` adicionando o novo env
3. Criar bucket de state: `gs://jeitto-tfstate-staging`
4. Adicionar workflow no `atlantis.yaml`:
   ```yaml
   staging:
     plan:
       steps:
         - env:
             name: GOOGLE_IMPERSONATE_SERVICE_ACCOUNT
             value: atlantis-sa@jeitto-staging.iam.gserviceaccount.com
         - init
         - plan
   ```
5. Adicionar enum nos templates do Backstage
6. Done!

---

## Manutenção do Atlantis

### Upgrade
```bash
helm upgrade atlantis runatlantis/atlantis -n atlantis -f helm-values.yaml
```

### Troubleshooting
```bash
# Ver logs
kubectl logs -f deploy/atlantis -n atlantis

# Ver locks ativos
# Acesse a UI: https://atlantis.jeitto.internal/locks

# Forçar unlock (emergência)
atlantis unlock --id=<lock-id>
```

### Monitoramento
- Expor métricas Prometheus: `/metrics`
- Alertas: plan com erro, apply falhando, locks > 1h

---

## Segurança

- **Prod requer 2 approvals** para apply
- **Branch protection** no main dos repos gitops
- **CODEOWNERS** por team/path
- **OPA/Conftest** (futuro): validar policies no plan
- **Audit trail**: todo apply está associado a um PR + autor
