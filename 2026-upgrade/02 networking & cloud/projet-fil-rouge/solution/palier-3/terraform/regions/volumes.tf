# Les DONNÉES des machines à état, sur des volumes qui survivent au remplacement de la machine
# (l'équivalent des disques EBS d'une instance). Une instance se remplace ; ses données, non.
# prevent_destroy : Terraform refusera tout plan qui détruirait l'un d'eux.

locals {
  donnees = {
    db       = { "/var/lib/postgresql" = "db-donnees" }
    db-lome  = { "/var/lib/postgresql" = "db-lome-donnees" }
    coffre   = { "/var/lib/bao" = "coffre-donnees" }
    stockage = { "/var/lib/weed" = "stockage-donnees" }
    ns1      = { "/var/lib/pdns" = "ns1-gslb" }
    ns2      = { "/var/lib/pdns" = "ns2-gslb" }
  }
}

resource "docker_volume" "donnees" {
  for_each = toset(flatten([for m, v in local.donnees : values(v)]))
  name     = each.key
  dynamic "labels" {
    for_each = merge(local.etiquettes, { donnees = "oui" })
    content {
      label = labels.key
      value = labels.value
    }
  }
  lifecycle {
    prevent_destroy = true
  }
}
