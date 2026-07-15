terraform {
  required_version = ">= 1.6.6"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 8.19.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }

  backend "s3" {}
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.region
}

provider "oci" {
  alias        = "home"
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.home_region
}

provider "cloudflare" {
  api_token = var.cloudflare_account_api_token
}

provider "helm" {
  kubernetes = {
    host                   = module.oke.cluster_endpoints.public_endpoint
    cluster_ca_certificate = base64decode(module.oke.cluster_ca_cert)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "oci"
      args = [
        "ce", "cluster", "generate-token",
        "--cluster-id", module.oke.cluster_id,
        "--region", var.region,
      ]
    }
  }
}

provider "kubernetes" {
  host                   = module.oke.cluster_endpoints.public_endpoint
  cluster_ca_certificate = base64decode(module.oke.cluster_ca_cert)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "oci"
    args = [
      "ce", "cluster", "generate-token",
      "--cluster-id", module.oke.cluster_id,
      "--region", var.region,
    ]
  }
}
