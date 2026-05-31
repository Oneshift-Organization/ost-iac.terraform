# ost-iac.terraform

Infra-as-Code da OneShift Cloud Intelligence Platform — OCI via Terraform.

Provisiona a infra do backend Python (FastAPI) e do banco PostgreSQL gerenciado,
integrados em um único VCN com isolamento por NSG. Spec do backend:
[`ost-backend.python`](https://github.com/Oneshift-Organization/ost-backend.python).

## Estrutura

```
ost-iac.terraform/
├── modules/
│   ├── backend/      # VCN + IGW + subnet pública + VM-NSG + VM Ampere A1
│   └── database/     # subnet privada + DB-NSG + Postgres gerenciado
└── envs/
    └── dev/          # compõe backend + database para o ambiente dev
```

- `backend` é dono da rede (VCN + IGW). Faz sentido porque a VM é o único recurso
  com IP público e a rede existe pra servi-la.
- `database` recebe `vcn_id` + `vm_nsg_id` do backend e cria sua própria subnet
  privada + NSG. A regra `5432` libera **apenas** ingress do NSG da VM —
  ninguém de fora do VCN, nem ninguém dentro do VCN que não esteja no NSG da VM,
  acessa o banco.

## Estado atual

| Recurso | Spec |
|---|---|
| VCN | `10.0.0.0/16` |
| Subnet pública (VM) | `10.0.1.0/24` — rota default → IGW |
| Subnet privada (DB) | `10.0.2.0/24` — sem rota default |
| VM | `VM.Standard.E4.Flex` (AMD x86), 2 OCPU / 12 GB / 50 GB boot — **pago** (~US$ 36–50/mês) |
| Postgres | versão 16, `VM.Standard.E4.Flex`, 2 OCPU / 8 GB / 50 GB regional storage, backup diário 7 dias — **pago** |
| Auth Postgres | usuário `ostadmin`, senha gerada via `random_password`, exposta no output `database_url` (sensitive) |

## Pré-requisitos

1. Conta OCI + tenancy.
2. Chave de API gerada e fingerprint copiado (`oci setup keys` ou OCI Console).
3. Compartment de destino criado.
4. Terraform ≥ 1.6.
5. Chave SSH pública para acessar a VM.

## Como rodar

```bash
cd envs/dev
cp terraform.tfvars.example terraform.tfvars
# preencha terraform.tfvars com seus OCIDs e chave SSH

terraform init
terraform plan
terraform apply
```

Após o `apply`, recupere credenciais sensíveis:

```bash
terraform output -raw db_admin_password
terraform output -raw database_url
```

Cole `database_url` no `.env` da VM (`/etc/ost-backend/.env`) e rode as migrations:

```bash
ssh opc@$(terraform output -raw vm_public_ip)
# bootstrap do app é manual (repo privado) — seguir deploy/deployPlan.md do backend
```

## Backend (state)

State local por padrão. Para usar **OCI Object Storage** como backend (S3-compatible):

1. Crie um bucket no OCI Object Storage (`ost-iac-tfstate`).
2. Em **Identity → My Profile → Customer Secret Keys**, gere uma access key.
3. Pegue o namespace do tenancy: `oci os ns get`.
4. Descomente o bloco `backend "s3" {...}` em `envs/dev/versions.tf` e preencha.
5. Exporte `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (são as credenciais do customer secret key).
6. `terraform init -migrate-state`.

## Custos esperados (MVP, região São Paulo)

| Item | Custo aproximado |
|---|---|
| VM E4.Flex (2 OCPU / 12 GB / 50 GB) | ~US$ 36–50/mês |
| VCN + IGW + NSG | US$ 0 |
| Postgres (2 OCPU / 8 GB / 50 GB regional) | ~US$ 90–110/mês |
| Backup (7 dias) | incluso |
| Egress típico MVP (< 10 GB/mês) | < US$ 1 |

**Total estimado: ~US$ 130–160/mês.**

Pra zerar o custo da VM (e perder x86): trocar `vm_shape = "VM.Standard.A1.Flex"` —
Ampere ARM cabe no Always Free (até 4 OCPU / 24 GB / 200 GB block storage por tenancy).

Pra cortar custo no DB: `db_is_regionally_durable = false` (storage AD-local) economiza
~20 %. `instance_count = 1` (default) já é single-node.

## Segurança

- DB **não tem IP público**. `prohibit_public_ip_on_vnic = true` na subnet privada.
- Acesso ao Postgres só de dentro do NSG da VM (regra por NSG source, não CIDR).
- Senha admin nunca em log: marcada `sensitive` em todos os outputs.
- SSH na VM controlado por `ssh_allowed_cidr` — **restrinja antes de subir prod**.
- Para evoluir: mover senha pro **OCI Vault** e referenciar via `secret_id`
  em vez de `PLAIN_TEXT` no bloco `credentials.password_details` do módulo database.

## Próximos passos

- [ ] Backend remoto de state em OCI Object Storage
- [ ] Ambiente `envs/prod` (copy de dev com sizing maior + `ssh_allowed_cidr` restrito)
- [ ] Mover senha do DB pro OCI Vault
- [ ] Adicionar `module "object_storage"` para o bucket de uploads de billing CSVs
- [ ] cloud-init que clona o repo do backend e roda alembic upgrade automaticamente (após resolver auth pro repo privado)
