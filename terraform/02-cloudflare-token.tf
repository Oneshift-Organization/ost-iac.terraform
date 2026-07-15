data "cloudflare_api_token_permission_groups_list" "dns_write" {
  name  = "DNS%20Write"
  scope = "com.cloudflare.api.account.zone"
}

resource "cloudflare_api_token" "external_dns" {
  name = "external-dns-oneshift-prd"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = data.cloudflare_api_token_permission_groups_list.dns_write.result[0].id
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${var.cloudflare_zone_id}" = "*"
    })
  }]
}

output "cloudflare_api_token" {
  description = "Token usado pelo external-dns para editar DNS na zona da oneshift"
  value       = cloudflare_api_token.external_dns.value
  sensitive   = true
}
