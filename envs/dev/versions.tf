terraform {
  required_version = ">= 1.6.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.20"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Backend remoto via OCI Object Storage (S3-compatible).
  # Descomente após criar o bucket + access key e definir variáveis:
  #   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (do customer secret key OCI)
  #
  # backend "s3" {
  #   bucket                      = "ost-iac-tfstate"
  #   key                         = "envs/dev/terraform.tfstate"
  #   region                      = "sa-saopaulo-1"
  #   endpoints                   = { s3 = "https://<namespace>.compat.objectstorage.sa-saopaulo-1.oraclecloud.com" }
  #   skip_credentials_validation = true
  #   skip_region_validation      = true
  #   skip_metadata_api_check     = true
  #   skip_requesting_account_id  = true
  #   use_path_style              = true
  # }
}
