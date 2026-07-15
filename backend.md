# Bootstrap do backend (compartment + bucket de state)

Passo manual, único, via **OCI CLI** (`oci` — sem `aws cli`). Motivo: o
bucket de state precisa viver dentro de um compartment, mas o Terraform que
gerenciaria esse compartment também guardaria seu state nesse mesmo bucket —
ovo-e-galinha. Não dá pra automatizar o próprio pré-requisito do backend.

## 1. Compartment

```bash
oci iam compartment create \
  --compartment-id <ocid-da-tenancy> \
  --name oneshift \
  --description "Compartment raiz do projeto oneshift"
```

Guarde o OCID retornado — é o `compartment_id` usado pelo Terraform (ver
`terraform.tfvars.example`) e o valor do GitHub Secret `OCI_COMPARTMENT_ID`.

## 2. Bucket de state (OCI Object Storage)

```bash
oci os bucket create \
  --compartment-id <ocid-do-compartment-oneshift> \
  --name oneshift-tfstate-prd \
  --region sa-saopaulo-1
```

## 3. Customer Secret Key (auth S3-compatible)

O backend `s3` do Terraform autentica via **Customer Secret Key**, não a API
Key usada pelo provider `oci`. Crie uma em: Console OCI → Identity → Users →
seu usuário → Customer Secret Keys.

## 4. Ligando os valores

Local: copie `backend.hcl.example` para `backend.hcl` (gitignored) e
preencha bucket, região, endpoint S3-compatible e o par access/secret key.
Use com:

```bash
cd terraform
terraform init -backend-config=../backend.hcl
```

Pipeline: os mesmos valores viram GitHub Secrets — `TF_STATE_BUCKET`,
`TF_STATE_S3_ENDPOINT`, `TF_STATE_ACCESS_KEY`, `TF_STATE_SECRET_KEY` — mais
`OCI_COMPARTMENT_ID` (OCID do compartment do passo 1).
