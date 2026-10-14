# gslb.marche.test : la bascule entre régions par le DNS (l'équivalent d'une politique de routage
# « failover » de Route 53). Servie par PowerDNS dans CHAQUE région — le DNS qui doit secourir une
# région ne peut pas vivre uniquement dans celle-ci. Mêmes données des deux côtés, par l'API.

provider "powerdns" {
  alias      = "europe"
  server_url = "http://10.0.1.54:8081" # par le VPN
  api_key    = local.regions.pdns_api
}
provider "powerdns" {
  alias      = "lome"
  server_url = "http://10.1.0.84:8081" # par le VPN, via l'Europe (hub-and-spoke)
  api_key    = local.regions.pdns_api
}

locals {
  gslb = {
    # www : Lomé d'abord (la région la plus proche des clients), l'Europe si Lomé n'est plus EN SANTÉ :
    # http://…/sante (L7 : au moins une application en service — pas seulement « le port répond »).
    # Les ensembles {…} sont des priorités : le premier qui a une adresse vivante l'emporte.
    # Vérifié en continu par le serveur DNS lui-même ; réponse de 30 s pour que la bascule soit rapide.
    "www.gslb.marche.test." = { type = "LUA", ttl = 30, contenu = "A \"ifurlup('http://www.marche.test/sante', {{'192.0.2.100'}, {'203.0.113.10'}})\"" }
  }
}

resource "powerdns_zone" "gslb_europe" {
  provider    = powerdns.europe
  name        = "gslb.marche.test."
  kind        = "Native"
  nameservers = ["gslb1.marche.test.", "gslb2.marche.test."]
}
resource "powerdns_zone" "gslb_lome" {
  provider    = powerdns.lome
  name        = "gslb.marche.test."
  kind        = "Native"
  nameservers = ["gslb1.marche.test.", "gslb2.marche.test."]
}
resource "powerdns_record" "gslb_europe" {
  provider = powerdns.europe
  for_each = local.gslb
  zone     = powerdns_zone.gslb_europe.name
  name     = each.key
  type     = each.value.type
  ttl      = each.value.ttl
  records  = [each.value.contenu]
}
resource "powerdns_record" "gslb_lome" {
  provider = powerdns.lome
  for_each = local.gslb
  zone     = powerdns_zone.gslb_lome.name
  name     = each.key
  type     = each.value.type
  ttl      = each.value.ttl
  records  = [each.value.contenu]
}

# ------------------------------------------------------------------ la découverte des applications
# apps-<région>.gslb.marche.test : un A par instance du groupe ACTIF de la région (le « target group »).
# Le répartiteur de la région le lit (server-template) : publier = mettre en service ; retirer = sortir
# de la rotation. Le déploiement bleu/vert, c'est changer couleur_active — une seconde, et réversible.
variable "couleur_active" {
  description = "le groupe servi par le répartiteur de chaque région"
  type        = map(string)
  default     = { europe = "bleu", lome = "bleu" }
  validation {
    condition     = alltrue([for c in values(var.couleur_active) : contains(["bleu", "vert"], c)])
    error_message = "Couleurs : bleu ou vert."
  }
}
locals {
  actives = { for r in ["europe", "lome"] : r => sort([
    for n, a in local.regions.applications : a.ip
    if a.region == r && a.couleur == var.couleur_active[r] && !contains(var.retrait, n)
  ]) }
}
# Les instances qu'on s'apprête à éteindre (réduction) : retirées de la publication AVANT, le temps
# que le répartiteur cesse d'y envoyer des requêtes (le « deregistration delay » d'un target group).
variable "retrait" {
  type    = list(string)
  default = []
}
# Les DEUX noms sur les DEUX serveurs : deux serveurs qui font autorité pour une même zone doivent en
# servir le même contenu. (Vécu : apps-europe publié seulement en Europe — un résolveur qui demandait
# au serveur de Lomé recevait « inexistant », et la supervision perdait la moitié des instances.)
# apps_europe = publiés sur le serveur d'Europe ; la clé est la région des instances.
locals {
  publiees = { for r, ips in local.actives : r => ips if length(ips) > 0 } # (un enregistrement ne peut pas être vide)
}
resource "powerdns_record" "apps_europe" {
  provider = powerdns.europe
  for_each = local.publiees
  zone     = powerdns_zone.gslb_europe.name
  name     = "apps-${each.key}.gslb.marche.test."
  type     = "A"
  ttl      = 5
  records  = each.value
}
resource "powerdns_record" "apps_lome" {
  provider = powerdns.lome
  for_each = local.publiees
  zone     = powerdns_zone.gslb_lome.name
  name     = "apps-${each.key}.gslb.marche.test."
  type     = "A"
  ttl      = 5
  records  = each.value
}
moved {
  from = powerdns_record.apps_europe[0]
  to   = powerdns_record.apps_europe["europe"]
}
moved {
  from = powerdns_record.apps_lome[0]
  to   = powerdns_record.apps_lome["lome"]
}

# Le SOA de la zone : son dernier champ est la durée de mise en cache des RÉPONSES NÉGATIVES. Le
# fournisseur remplace un enregistrement (suppression, puis création) quand ses adresses changent :
# une requête tombée entre les deux reçoit « inexistant »… que les résolveurs gardent pendant cette
# durée (PowerDNS : 1 h par défaut — vécu : la supervision ne voyait plus aucune instance). 5 s.
locals {
  soa_gslb = "gslb1.marche.test. hostmaster.marche.test. 1 10800 3600 604800 5"
}
resource "powerdns_record" "soa_europe" {
  provider = powerdns.europe
  zone     = powerdns_zone.gslb_europe.name
  name     = "gslb.marche.test."
  type     = "SOA"
  ttl      = 300
  records  = [local.soa_gslb]
}
resource "powerdns_record" "soa_lome" {
  provider = powerdns.lome
  zone     = powerdns_zone.gslb_lome.name
  name     = "gslb.marche.test."
  type     = "SOA"
  ttl      = 300
  records  = [local.soa_gslb]
}
