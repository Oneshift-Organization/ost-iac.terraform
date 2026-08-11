# Acesso ao cluster OneShift

Guia para configurar o `kubectl` no cluster **`oke-oneshift-prd`** (Oracle Kubernetes Engine, região `us-ashburn-1`).

Leva uns 10 minutos. Ao final você consegue ver e mexer nos deployments da aplicação.

---

## Como o acesso funciona

Você passa por **duas portas**, e é útil saber disso porque os erros de cada uma são diferentes:

| Porta | O que faz | Erro quando falha |
|---|---|---|
| **OCI** | Autentica você na Oracle Cloud e emite um token temporário | `NotAuthorized` / `NotAuthenticated` |
| **Kubernetes (RBAC)** | Decide o que você pode fazer dentro do cluster | `403 Forbidden` |

A primeira usa uma **chave de API** — um par de chaves que você gera na sua máquina. A privada nunca sai do seu computador; você envia só a pública.

A segunda já está configurada para você. Não precisa fazer nada.

---

## Pré-requisitos

### OCI CLI

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

Aceite os padrões. Ao final, reabra o terminal e confirme:

```bash
oci --version
```

### kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

No macOS: `brew install kubectl`.

---

## Passo 1 — Gerar seu par de chaves

Na **sua** máquina:

```bash
mkdir -p ~/.oci
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
chmod 600 ~/.oci/oci_api_key.pem
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
```

Isso cria dois arquivos:

- `oci_api_key.pem` — **privada**. Nunca envie para ninguém, nunca commite, nunca cole em chat.
- `oci_api_key_public.pem` — **pública**. É esta que você envia.

O `chmod 600` não é decorativo: o OCI CLI recusa a chave se ela estiver com permissão aberta.

## Passo 2 — Enviar a chave pública

Mande o conteúdo de `~/.oci/oci_api_key_public.pem` para o Luiz. Ele sobe na OCI e te devolve um **fingerprint**, algo como `0e:dd:50:bc:...`.

Confira que o que você está enviando começa com `-----BEGIN PUBLIC KEY-----`. Se aparecer `PRIVATE`, você pegou o arquivo errado.

Você pode calcular seu próprio fingerprint para comparar:

```bash
openssl rsa -pubin -in ~/.oci/oci_api_key_public.pem -outform DER | openssl md5 -c
```

## Passo 3 — Configurar o `~/.oci/config`

Crie o arquivo `~/.oci/config` com este conteúdo, trocando `user` e `fingerprint` pelos **seus**:

```ini
[DEFAULT]
user=<seu OCID da tabela abaixo>
fingerprint=<o fingerprint que o Luiz te passou>
tenancy=ocid1.tenancy.oc1..aaaaaaaatthjpjeq6vms6avlgw3wtv5w2qzvf5zjuavjcrn3vqi3hxl54hha
region=us-ashburn-1
key_file=~/.oci/oci_api_key.pem
```

```bash
chmod 600 ~/.oci/config
```

### OCIDs do time

| Dev | E-mail | OCID |
|---|---|---|
| Anderson Huang | rm565920@fiap.com.br | `ocid1.user.oc1..aaaaaaaaprpb74vxj6f2dcuvqnb4fnntdu7le2lo7c5yickscofd5v5w3cha` |
| Bruno Henrique | rm566277@fiap.com.br | `ocid1.user.oc1..aaaaaaaaz3xded56p4tygzsaap3yk5lseymofm5o5tbzmqbxc75q2agc2eaq` |
| Ronaldo Attamah | rm564630@fiap.com.br | `ocid1.user.oc1..aaaaaaaax3d7auhg35imvmrf4uqdnosjlviililexwwy4njall4r6flgnena` |
| Guylherme Miguel | rm562374@fiap.com.br | `ocid1.user.oc1..aaaaaaaaaem3kpxrbtirrkhmugwjcmab4hxgk5rpzgiywlyyjgpjtphxembq` |

Teste que a primeira porta abriu:

```bash
oci iam region list --output table
```

Se listar as regiões, sua autenticação na OCI está OK.

## Passo 4 — Gerar o kubeconfig

```bash
oci ce cluster create-kubeconfig \
  --cluster-id ocid1.cluster.oc1.iad.aaaaaaaarwnc3t4dv2itd6z3vkv7okwxoxmmovft2girgqde5coomege2era \
  --file $HOME/.kube/config \
  --region us-ashburn-1 \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT
```

O comando **não** guarda senha nenhuma. Ele grava um `~/.kube/config` que chama o `oci` para gerar um token novo a cada comando — por isso o OCI CLI precisa continuar instalado e configurado.

> Se você já usa `kubectl` para outros clusters, este comando **adiciona** um contexto ao seu config, sem apagar os existentes. Alterne com `kubectl config use-context`.

## Passo 5 — Validar

```bash
kubectl auth whoami
```

Deve mostrar seu OCID em `Username`. Este é o comando que resolve quase todo problema de permissão — ele mostra exatamente qual identidade o cluster está enxergando.

```bash
kubectl -n production get pods
kubectl get nodes
```

Se os dois responderem, está tudo pronto.

---

## O que você pode fazer

Seu acesso é de **desenvolvedor no namespace `production`**, onde rodam a API e o MCP.

**Pode:**

```bash
kubectl -n production get pods                      # listar
kubectl -n production logs -f deploy/api            # acompanhar logs
kubectl -n production describe pod <nome>           # investigar
kubectl -n production rollout restart deploy/api    # reiniciar
kubectl -n production port-forward svc/api 8000:80  # acessar local
kubectl get nodes                                   # ver os nós
```

No `shared-services` você alcança **apenas o Postgres** — ver a seção do banco abaixo.

**Não pode** — e isso é intencional, não é bug:

- Ler `secrets` do `flux-system` (onde ficam as credenciais de infra)
- Criar `RoleBinding` ou alterar permissões
- Mexer em `kube-system` ou apagar namespaces
- Abrir túnel para outros pods do `shared-services`, como o ingress-nginx

Se precisar de algo dessa lista, fale com o Luiz em vez de contornar.

### Um aviso sobre o namespace `production`

Este é o ambiente de **produção** — o nome do namespace já deixa isso claro. `rollout restart` derruba o pod e sobe outro — o serviço fica alguns segundos fora. E não adianta editar um deployment com `kubectl edit`: o cluster é gerenciado por GitOps (FluxCD), e qualquer alteração manual é **revertida em até 5 minutos** para o que está no repositório.

Para mudar algo de verdade, abra PR em `ost-iac.terraform` alterando os manifestos em `fluxcd/production/`.

### E o namespace `develop`?

Mesmo cluster, mesma forma de acesso (`kubectl -n develop get pods` etc.),
mesmas regras de GitOps — editar com `kubectl edit` também é revertido em
até 5 minutos, porque é o mesmo FluxCD cuidando dos dois namespaces.

A diferença é o dado: `develop` usa a database `ost_dev`, vazia, sem nada de
produção. Pode testar, quebrar, e reiniciar sem o cuidado extra da seção
acima.

---

## Acessando o banco de dados

O Postgres roda dentro do cluster e **não é exposto para a internet**. Você chega nele abrindo um túnel com `port-forward`.

### 1. Pegar a senha

```bash
kubectl -n shared-services get secret postgres-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### 2. Abrir o túnel

```bash
kubectl -n shared-services port-forward pod/postgres-0 5432:5432
```

Deixe esse terminal aberto — o túnel só existe enquanto o comando roda.

### 3. Conectar

Em outro terminal:

```bash
psql -h localhost -p 5432 -U ostadmin -d ost
```

Pra conectar em `ost_dev` em vez de `ost` (mesmo túnel, mesma instância):

```bash
kubectl -n shared-services get secret postgres-dev-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

psql -h localhost -p 5432 -U ostadmin_dev -d ost_dev
```

| Campo | Valor |
|---|---|
| Host | `localhost` |
| Porta | `5432` |
| Banco | `ost` |
| Usuário | `ostadmin` |
| Senha | a do passo 1 |

Serve igual para DBeaver, TablePlus, pgAdmin ou o cliente que você preferir — basta apontar para `localhost:5432` com o túnel aberto.

Se a porta 5432 já estiver ocupada na sua máquina (Postgres local, por exemplo), use outra: `port-forward pod/postgres-0 55432:5432` e conecte na `55432`.

### Antes de rodar qualquer coisa

Este é o **banco de produção**, com os dados reais de billing. Não existe réplica nem ambiente de staging, e o acesso é de administrador — dá para alterar e apagar qualquer tabela.

Duas precauções que valem o hábito:

- Rode `SELECT` antes do `UPDATE`/`DELETE` correspondente, para conferir quais linhas serão afetadas
- Use transação explícita no que for destrutivo, para poder voltar atrás:

```sql
BEGIN;
DELETE FROM tabela WHERE condicao;
-- confira o resultado; se estiver errado:
ROLLBACK;
-- se estiver certo:
COMMIT;
```

A credencial é a mesma que a aplicação usa, então o banco não registra quem fez o quê. Na dúvida sobre um comando destrutivo, pergunte antes.

---

## Problemas comuns

### `NotAuthenticated` ou `NotAuthorized` ao rodar `oci`

A primeira porta não abriu. Verifique nesta ordem:

1. `key_file` aponta para a chave **privada** (`oci_api_key.pem`, sem `_public`)
2. `fingerprint` está idêntico ao que o Luiz te passou
3. `user` é o seu OCID, não o de outra pessoa
4. `chmod 600 ~/.oci/oci_api_key.pem`

### `error: You must be logged in to the server (Unauthorized)`

O token não foi gerado. Quase sempre é o OCI CLI fora do `PATH` — o `kubectl` chama `oci` por baixo. Teste com `oci iam region list`.

### `Error from server (Forbidden)`

A primeira porta abriu, a segunda não. Rode `kubectl auth whoami` e compare o OCID com o da tabela acima. Se bater, avise o Luiz — pode ser que seu OCID ainda não esteja no RoleBinding.

Lembre que `Forbidden` também aparece quando você tenta algo fora do seu escopo, como `kubectl get pods -n flux-system`. Confira se você usou `-n production` (ou `-n develop`).

### `Unable to connect to the server: dial tcp ... i/o timeout`

Rede. O control plane é público, então normalmente é firewall corporativo ou VPN bloqueando a porta `6443`.

---

## Referências

- Cluster: `oke-oneshift-prd`, Kubernetes v1.34.2, região `us-ashburn-1`
- Infra e manifestos: [`ost-iac.terraform`](https://github.com/Oneshift-Organization/ost-iac.terraform)
- Permissões: `terraform/05-iam-time.tf` (OCI) e `fluxcd/shared-services/rbac/` (Kubernetes)
