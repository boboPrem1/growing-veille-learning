# La zone marche.test, en split-horizon, comme du code. Une modification REMPLACE ns1 (le contenu
# est dans son « user data ») — ns2 la reçoit ensuite par transfert de zone. Ce qui change souvent
# (la bascule entre régions) vit ailleurs : dans PowerDNS (gslb.marche.test), piloté par API.
# ⚠️ Incrémenter la série à chaque modification : c'est ELLE qui déclenche le transfert vers ns2.

locals {
  serie_dns = "2026100105"

  entete_dns = <<-EOT
    $TTL 300
    @         IN SOA  ns1.marche.test. hostmaster.marche.test. ( ${local.serie_dns} 3600 600 1209600 300 )
    @         IN NS   ns1.marche.test.
    @         IN NS   ns2.marche.test.
    @         IN TXT  "v=spf1 -all"
    _dmarc    IN TXT  "v=DMARC1; p=reject"
    static    IN A    192.0.2.80
    ; gslb.marche.test : la bascule entre régions, déléguée à PowerDNS dans CHAQUE région
    gslb      IN NS   gslb1.marche.test.
    gslb      IN NS   gslb2.marche.test.
  EOT

  zone_externe = <<-EOT
    ${local.entete_dns}
    ns1       IN A     203.0.113.10
    ns2       IN A     192.0.2.100
    gslb1     IN A     203.0.113.11
    gslb2     IN A     192.0.2.101
    @         IN A     203.0.113.10
    ; www : la région choisie par le GSLB (Lomé, la plus proche des clients ; l'Europe en secours)
    www       IN CNAME www.gslb.marche.test.
  EOT

  zone_interne = <<-EOT
    ${local.entete_dns}
    ; --- Europe
    ns1        IN A     10.0.1.53
    ns1        IN AAAA  fd00:4d41:5243:1::53
    gslb1      IN A     10.0.1.54
    @          IN A     10.0.1.10
    www        IN A     10.0.1.10
    lb         IN A     10.0.1.10
    passerelle IN A     10.0.1.1
    ; les applications ne sont PAS ici : leurs instances vont et viennent (groupes, bleu/vert) — elles
    ; sont publiées dans gslb.marche.test (PowerDNS, par API) : apps-europe…, apps-lome…
    ; « db » (le point d'accès de la base PRIMAIRE) n'est PAS ici : le résolveur de chaque région le
    ; sert (local-data, variable region_primaire) — il doit pouvoir changer quand ns1 est injoignable.
    db-europe  IN A     10.0.3.10
    db-europe  IN AAAA  fd00:4d41:5243:30::10
    stockage   IN A     10.0.3.20
    coffre     IN A     10.0.3.30
    ; --- Lomé
    ns2        IN A     10.1.0.83
    gslb2      IN A     10.1.0.84
    passerelle-lome IN A  10.1.0.81
    lb-lome    IN A     10.1.0.82
    db-lome    IN A     10.1.0.70
    supervision IN A    10.1.0.85
    db-lome    IN AAAA  fd00:4d41:5243:130::70
  EOT
}
