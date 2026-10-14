# La couche « regions » : réseaux et machines des deux régions (et le nœud CDN).
# Lancée depuis la console : elle lit la PKI (/root/pki), la clé SSH et les clés WireGuard
# générées par bootstrap.sh (/root/cles). Son état est dans le S3 du fournisseur (backend « s3 »).

terraform {
  required_version = ">= 1.10"
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "3.9.0" }
    tls    = { source = "hashicorp/tls" }
    random = { source = "hashicorp/random" }
  }
  backend "s3" {} # configuration : etat.hcl (bootstrap.sh) — terraform init -backend-config=../etat.hcl
}

provider "docker" {}

# ------------------------------------------------------------------ le décor fourni par le lab
data "docker_network" "internet_europe" { name = "marche-cloud_europe" }
data "docker_network" "internet_lome" { name = "marche-cloud_lome" }

locals {
  etiquettes = { equipe = "plateforme", env = "prod", projet = "marche" }
  admin      = "10.99.0.0/24"
  racine     = file("/root/pki/racine.crt")
  roles_dir  = "${path.module}/../../roles"
  wg         = { for n in ["europe", "lome", "console"] : n => { prive = trimspace(file("/root/cles/wg/${n}.key")), public = trimspace(file("/root/cles/wg/${n}.pub")) } }

  # Les réseaux de chaque région. Lomé : un plan VLSM (des sous-réseaux à la taille du besoin).
  reseaux = {
    "europe-pub"  = { region = "europe", sous_reseau = "10.0.1.0/24", passerelle_docker = "10.0.1.254" }
    "europe-baie" = { region = "europe", sous_reseau = "172.31.255.0/24", passerelle_docker = "172.31.255.254" }
    "lome-pub"    = { region = "lome", sous_reseau = "10.1.0.80/28", passerelle_docker = "10.1.0.94" }
    "lome-baie"   = { region = "lome", sous_reseau = "172.31.254.0/24", passerelle_docker = "172.31.254.254" }
  }
}

resource "docker_network" "region" {
  for_each = local.reseaux
  name     = each.key
  driver   = "macvlan" # un commutateur isolé (voir lab/README.md : pas de « bridge » interne)
  internal = true
  ipam_config {
    subnet  = each.value.sous_reseau
    gateway = each.value.passerelle_docker
  }
  dynamic "labels" {
    for_each = merge(local.etiquettes, { region = each.value.region })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

# ------------------------------------------------------------------ secrets (dans l'état : chiffré, restreint)
resource "random_password" "s3_admin" {
  length  = 32
  special = false
}
resource "random_password" "bao_db" {
  length  = 32
  special = false
}
resource "random_password" "replication" {
  length  = 32
  special = false
}
resource "random_password" "pdns_api" {
  length  = 32
  special = false
}
resource "random_bytes" "tsig" { # la clé qui authentifie les transferts de zone vers le secondaire
  length = 32
}
resource "random_bytes" "tsig_interne" { # la même chose pour la vue interne (une clé par vue)
  length = 32
}

# ------------------------------------------------------------------ la région qui porte la base PRIMAIRE
# Bascule de région : terraform apply -var region_primaire=lome (voir solution/palier-2/basculer.sh).
# La réplique de cette région est PROMUE, l'autre base devient sa réplique (reconstruite), et les
# résolveurs des deux régions font pointer db.marche.test vers la nouvelle primaire.
variable "region_primaire" {
  type    = string
  default = "europe"
  validation {
    condition     = contains(["europe", "lome"], var.region_primaire)
    error_message = "region_primaire : europe ou lome."
  }
}
locals {
  bases = {
    europe = { machine = "db", ip = "10.0.3.10", slot = "europe" }
    lome   = { machine = "db-lome", ip = "10.1.0.70", slot = "lome" }
  }
  primaire = local.bases[var.region_primaire]
  # les paramètres de la base d'une région : primaire, ou réplique de l'autre
  parametres_base = { for r, b in local.bases : r => r == var.region_primaire ? {
    MODE = "primaire", REPLIQUES = local.bases[r == "europe" ? "lome" : "europe"].ip, SLOTS = local.bases[r == "europe" ? "lome" : "europe"].slot
    } : {
    MODE = "replique", PRIMAIRE = local.primaire.ip, SLOT = b.slot
  } }
}
