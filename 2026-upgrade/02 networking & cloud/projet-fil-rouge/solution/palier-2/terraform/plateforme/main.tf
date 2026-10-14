# La couche « plateforme » : ce qui se configure PAR API une fois les machines debout — secrets
# (OpenBao), stockage objet et IAM (API S3/IAM). Ce qui change à CHAQUE déploiement (le DNS de
# trafic) vit dans sa propre couche, « trafic » : un plan rapide, et un rayon d'action réduit.
# Elle passe par le VPN d'administration, et lit les sorties de la couche « regions ».

terraform {
  required_version = ">= 1.10"
  required_providers {
    vault  = { source = "hashicorp/vault", version = "5.12.0" }
    aws    = { source = "hashicorp/aws", version = "6.66.0" }
    random = { source = "hashicorp/random" }
  }
  backend "s3" {}
}

# ------------------------------------------------------------------ ce que la couche « regions » a créé
data "terraform_remote_state" "regions" {
  backend = "s3"
  config = {
    bucket                      = "marche-etat-terraform", key = "regions/terraform.tfstate", region = "us-east-1", profile = "fournisseur"
    endpoints                   = { s3 = "https://s3.fournisseur.test" }, use_path_style = true
    skip_credentials_validation = true, skip_requesting_account_id = true, skip_metadata_api_check = true, skip_region_validation = true
  }
}
locals {
  regions = data.terraform_remote_state.regions.outputs
}

# ------------------------------------------------------------------ fournisseurs
provider "vault" {
  address          = "https://10.0.3.30:8200" # par le VPN
  ca_cert_file     = "/root/pki/racine.crt"
  tls_server_name  = "coffre.marche.test"
  token            = jsondecode(file("/root/cles/bao-init.json")).root_token
  skip_child_token = true
}
provider "aws" {
  alias                       = "stockage" # le stockage S3 du VPC Europe (par le VPN)
  region                      = "us-east-1"
  access_key                  = "admin-marche"
  secret_key                  = local.regions.s3_admin_secret
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  endpoints {
    s3  = "http://10.0.3.20:8333"
    iam = "http://10.0.3.20:8333"
  }
}
