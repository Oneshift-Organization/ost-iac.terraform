resource "helm_release" "flux" {
  name             = "flux2"
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  version          = "2.19.0"
  namespace        = "flux-system"
  create_namespace = true
}

resource "helm_release" "flux_sync" {
  name       = "flux2-sync"
  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2-sync"
  version    = "1.15.0"
  namespace  = "flux-system"

  set = [
    {
      name  = "gitRepository.spec.url"
      value = "https://github.com/Oneshift-Organization/ost-iac.terraform"
    },
    {
      name  = "gitRepository.spec.ref.branch"
      value = "main"
    },
    {
      name  = "kustomization.spec.path"
      value = "./fluxcd"
    },
    {
      name  = "kustomization.spec.decryption.provider"
      value = "sops"
    },
    {
      name  = "kustomization.spec.decryption.secretRef.name"
      value = "sops-age"
    },
    {
      name  = "gitRepository.spec.secretRef.name"
      value = "flux-git-auth"
    },
  ]

  depends_on = [
    helm_release.flux,
    kubernetes_secret_v1.sops_age,
    kubernetes_secret_v1.flux_git_auth,
  ]
}
