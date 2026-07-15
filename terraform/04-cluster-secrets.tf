resource "kubernetes_secret_v1" "sops_age" {
  metadata {
    name      = "sops-age"
    namespace = "flux-system"
  }

  data = {
    "age.agekey" = var.sops_age_private_key
  }

  type = "Opaque"

  depends_on = [helm_release.flux]
}

resource "kubernetes_secret_v1" "flux_git_auth" {
  metadata {
    name      = "flux-git-auth"
    namespace = "flux-system"
  }

  data = {
    username = var.flux_git_username
    password = var.flux_git_token
  }

  type = "Opaque"

  depends_on = [helm_release.flux]
}
