# Les certificats sont du code : émis par l'AC intermédiaire de la console (celle du Palier 1),
# réémis AUTOMATIQUEMENT par « terraform apply » dans les 30 derniers jours de leur validité.
# (Leurs clés privées sont dans l'état Terraform : un état se chiffre et s'isole.)

locals {
  ac_cert = file("/root/pki/intermediaire.crt")
  ac_cle  = file("/root/pki/intermediaire.key")

  certificats = merge(
    {
      www    = { noms = ["www.marche.test", "marche.test"], usages = ["server_auth"] }
      static = { noms = ["static.marche.test"], usages = ["server_auth"] }
      coffre = { noms = ["coffre.marche.test"], usages = ["server_auth"] }
    },
    # un certificat CLIENT par instance d'application : son identité auprès d'OpenBao
    { for n in concat(keys(local.apps), ["db", "db-lome"]) : n => { noms = ["${n}.marche.test"], usages = ["client_auth"] } }
  )
}

resource "tls_private_key" "cle" {
  for_each    = local.certificats
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "demande" {
  for_each        = local.certificats
  private_key_pem = tls_private_key.cle[each.key].private_key_pem
  dns_names       = each.value.noms
  subject {
    common_name = each.value.noms[0]
  }
}

resource "tls_locally_signed_cert" "cert" {
  for_each              = local.certificats
  cert_request_pem      = tls_cert_request.demande[each.key].cert_request_pem
  ca_private_key_pem    = local.ac_cle
  ca_cert_pem           = local.ac_cert
  validity_period_hours = 90 * 24
  early_renewal_hours   = 30 * 24
  allowed_uses          = concat(["digital_signature"], each.value.usages)
}

locals {
  # ce que présente un serveur : sa clé, sa feuille, puis l'intermédiaire
  pem = { for n, _ in local.certificats : n => join("", [
    tls_private_key.cle[n].private_key_pem, tls_locally_signed_cert.cert[n].cert_pem, local.ac_cert
  ]) }
}
