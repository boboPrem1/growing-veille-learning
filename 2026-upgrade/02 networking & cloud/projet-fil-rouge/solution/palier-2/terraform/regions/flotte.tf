# La flotte d'applications : des GROUPES d'instances identiques (l'équivalent d'un groupe
# d'auto-scaling), deux couleurs par région pour déployer en bleu/vert. La taille et la version de
# chaque groupe sont des VARIABLES : pipeline.sh (déploiements) et autoscaler.sh (charge) les
# changent dans flotte.auto.tfvars.json, puis passent par plan → apply comme tout le monde.
# Le répartiteur ne connaît pas les instances : il les DÉCOUVRE par le DNS (apps-<région>.gslb…),
# que la couche plateforme publie — ajouter ou retirer une instance ne touche pas au répartiteur.

variable "groupes" {
  description = "taille et version de chaque groupe (<région>-<couleur>)"
  type        = map(object({ taille = number, version = string }))
  default = {
    europe-bleu = { taille = 2, version = "1.0.0" }
    europe-vert = { taille = 0, version = "1.0.0" }
    lome-bleu   = { taille = 2, version = "1.0.0" }
    lome-vert   = { taille = 0, version = "1.0.0" }
  }
  validation {
    condition     = alltrue([for g in values(var.groupes) : g.taille >= 0 && g.taille <= 8])
    error_message = "Un groupe compte de 0 à 8 instances (le plan d'adressage réserve 8 adresses par couleur)."
  }
  validation {
    condition     = alltrue([for g in keys(var.groupes) : contains(["europe-bleu", "europe-vert", "lome-bleu", "lome-vert"], g)])
    error_message = "Groupes connus : europe-bleu, europe-vert, lome-bleu, lome-vert."
  }
}

locals {
  # le « launch template » de chaque région
  gabarits = {
    europe = { reseau = "europe-baie", baie = "172.31.255", ip = "10.0.2", masque = 24, gw = "10.0.2.1", v6 = "fd00:4d41:5243:20", lb = "10.0.1.10" }
    lome   = { reseau = "lome-baie", baie = "172.31.254", ip = "10.1.0", masque = 26, gw = "10.1.0.1", v6 = "fd00:4d41:5243:120", lb = "10.1.0.82" }
  }
  # plan d'adressage : bleu en .11 à .18, vert en .21 à .28 (sous-réseau des applications) ;
  # côté « baie » (l'adresse du fournisseur) : bleu .21 à .28, vert .61 à .68
  plages = { bleu = { ip = 10, baie = 20 }, vert = { ip = 20, baie = 60 } }

  apps = merge([for g, v in var.groupes : {
    for i in range(1, v.taille + 1) : "app-${g}-${i}" => {
      region  = split("-", g)[0]
      couleur = split("-", g)[1]
      version = v.version
      ip      = "${local.gabarits[split("-", g)[0]].ip}.${local.plages[split("-", g)[1]].ip + i}"
      baie    = "${local.gabarits[split("-", g)[0]].baie}.${local.plages[split("-", g)[1]].baie + i}"
    }
  }]...)

  app = { for n, a in local.apps : n => {
    role       = "app", region = a.region
    interfaces = [{ reseau = local.gabarits[a.region].reseau, ipv4 = a.baie, sous_reseau = "${local.gabarits[a.region].baie}.0/24", nom = "baie" }]
    parametres = {
      VLAN     = "20", ADRESSE4 = "${a.ip}/${local.gabarits[a.region].masque}", GW = local.gabarits[a.region].gw
      ADRESSE6 = "${local.gabarits[a.region].v6}::${split(".", a.ip)[3]}/64", LB_SOURCE = local.gabarits[a.region].lb
      VERSION  = a.version
    }
    fichiers   = {}
    etiquettes = { groupe = "${a.region}-${a.couleur}", couleur = a.couleur, version = a.version }
  } }
}

output "applications" {
  description = "les instances d'application : nom → région, couleur, version, adresse"
  value       = { for n, a in local.apps : n => { region = a.region, couleur = a.couleur, version = a.version, ip = a.ip } }
}
