# Zero Trust (Palier 3) : plus AUCUNE confiance accordée à la position dans le réseau. Chaque service
# prouve QUI il est, à chaque connexion, par un certificat court (24 h au plus) que lui délivre — et
# renouvelle en continu — OpenBao. L'application ne répond qu'au répartiteur (identité « lb ») ; ses
# métriques, qu'à la supervision (identité « supervision ») ; la base exige TLS, et des applications
# un certificat. Une adresse IP volée ou une machine compromise dans le bon sous-réseau ne suffisent
# plus : il faut une identité, qui expire vite.
#
# Une autorité DÉDIÉE aux identités de service : l'intermédiaire de la console ne peut pas en signer
# une autre (pathlen:0 — c'était voulu au Palier 1), et une AC de services tourne à un tout autre
# rythme (des certificats de quelques heures, émis par milliers).

resource "vault_mount" "pki" {
  path                      = "pki-services"
  type                      = "pki"
  max_lease_ttl_seconds     = 5 * 365 * 24 * 3600
  default_lease_ttl_seconds = 3600
}
resource "vault_pki_secret_backend_root_cert" "ac" {
  backend     = vault_mount.pki.path
  type        = "internal" # la clé privée ne quitte jamais le coffre
  common_name = "Marché — identités de service"
  ttl         = "43800h"
  key_type    = "ec"
  key_bits    = 256
}

# un rôle par identité : QUEL nom peut être demandé, pour QUELLE durée au plus
locals {
  identites = {
    app         = { nom = "app.svc.marche.test", serveur = true, client = true }
    lb          = { nom = "lb.svc.marche.test", serveur = false, client = true }
    supervision = { nom = "supervision.svc.marche.test", serveur = false, client = true }
    db          = { nom = "db.marche.test", serveur = true, client = true }
  }
}
resource "vault_pki_secret_backend_role" "identite" {
  for_each           = local.identites
  backend            = vault_mount.pki.path
  name               = each.key
  allowed_domains    = [each.value.nom]
  allow_bare_domains = true
  allow_subdomains   = false
  allow_ip_sans      = false
  server_flag        = each.value.serveur
  client_flag        = each.value.client
  key_type           = "ec"
  key_bits           = 256
  ttl                = 24 * 3600 # 24 h : une identité volée ne sert pas longtemps
  max_ttl            = 24 * 3600
  depends_on         = [vault_pki_secret_backend_root_cert.ac]
}

# qui peut demander quelle identité : l'instance s'authentifie avec le certificat de sa création
# (méthode « cert »), et sa politique ne l'autorise qu'à SA propre identité
resource "vault_policy" "identite" {
  for_each = local.identites
  name     = "identite-${each.key}"
  policy   = <<-EOT
    path "pki-services/issue/${each.key}" { capabilities = ["update"] }
    path "pki-services/cert/ca"           { capabilities = ["read"] }
  EOT
}
resource "vault_cert_auth_backend_role" "lb" {
  name                 = "lb"
  backend              = vault_auth_backend.cert.path
  certificate          = local.regions.ac_intermediaire
  allowed_common_names = ["lb*.marche.test"]
  token_policies       = [vault_policy.identite["lb"].name]
  token_ttl            = 3600
}
resource "vault_cert_auth_backend_role" "supervision" {
  name                 = "supervision"
  backend              = vault_auth_backend.cert.path
  certificate          = local.regions.ac_intermediaire
  allowed_common_names = ["supervision.marche.test"]
  token_policies       = [vault_policy.identite["supervision"].name]
  token_ttl            = 3600
}

output "ac_services" {
  description = "l'AC des identités de service (à distribuer aux vérificateurs)"
  value       = vault_pki_secret_backend_root_cert.ac.certificate
}
