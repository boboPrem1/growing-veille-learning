# La couche « trafic » : le DNS qui dirige les clients (GSLB entre régions) et les répartiteurs
# (découverte des instances, bleu/vert). Séparée de « plateforme » parce qu'elle change à CHAQUE
# déploiement et à chaque mise à l'échelle : son plan doit être rapide (un seul fournisseur, peu de
# ressources), et une erreur ici ne doit pas pouvoir toucher aux secrets ni aux sauvegardes.

terraform {
  required_version = ">= 1.10"
  required_providers {
    powerdns = { source = "pan-net/powerdns", version = "1.5.0" }
  }
  backend "s3" {}
}

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
