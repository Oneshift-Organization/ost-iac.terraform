# Diagrama de infraestrutura

Visão de alto nível de como o tráfego chega até a API e o MCP no cluster
`oke-oneshift-prd`, e como os dois ambientes (`production` e `develop`)
compartilham o mesmo Postgres.

```mermaid
flowchart LR
    Internet((Internet)) -->|DNS via Cloudflare| NGINX[ingress-nginx]

    subgraph Production["namespace: production"]
        API["api\napi.oneshift.com.br"]
        MCP["mcp\nmcp.oneshift.com.br"]
    end

    subgraph Develop["namespace: develop"]
        APIDev["api\napi-dev.oneshift.com.br"]
        MCPDev["mcp\nmcp-dev.oneshift.com.br"]
    end

    subgraph SharedServices["namespace: shared-services"]
        Postgres[(Postgres)]
    end

    NGINX --> API
    NGINX --> MCP
    NGINX --> APIDev
    NGINX --> MCPDev

    API -->|DATABASE_URL| Postgres
    APIDev -->|DATABASE_URL| Postgres
```

## Notas

- production e develop: api e mcp cada, develop com database própria
  (`ost_dev`) na mesma instância de Postgres.
- `ingress-nginx` e o Postgres rodam em `shared-services`, compartilhados
  pelos dois ambientes.
- O diagrama não distingue database dentro da instância de Postgres — tanto
  `production` (`ost`) quanto `develop` (`ost_dev`) apontam para o mesmo nó.
- Todos os deployments são reconciliados pelo FluxCD a partir de
  `fluxcd/production/`, `fluxcd/develop/` e `fluxcd/shared-services/` neste
  repositório.
