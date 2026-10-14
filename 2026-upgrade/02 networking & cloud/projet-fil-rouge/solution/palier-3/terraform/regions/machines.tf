# Les machines des deux régions. Chacune : un rôle (../../roles/<role>.sh), ses interfaces, ses
# paramètres (écrits dans /lab/parametres.sh) et ses fichiers. Le script de démarrage est le même
# pour toutes : il lance le rôle.

locals {
  ie = data.docker_network.internet_europe.name
  il = data.docker_network.internet_lome.name

  # (toutes les machines savent qui les administre, et qui les supervise)
  commun = { ADMIN = local.admin, SUPERVISION = "10.1.0.85" }
  # les deux bases acceptent les MÊMES clients (l'une ou l'autre peut devenir primaire) : les
  # applications des deux régions, et le coffre (qui crée les identifiants temporaires)
  base_commun = {
    CLIENTS_HBA = "10.0.2.0/24 fd00:4d41:5243:20::/64 10.1.0.0/26 fd00:4d41:5243:120::/64"
    COFFRE_HBA  = "10.0.3.30/32" # le coffre : TLS, sans certificat client (il crée les comptes)
    BAO_MDP     = random_password.bao_db.result, REPL_MDP = random_password.replication.result
  }

  # (les instances d'application viennent de flotte.tf)
  machines = merge(local.app, {
    # =========================================================== région Europe (VPC 10.0.0.0/16)
    passerelle = {
      role = "passerelle", region = "europe"
      interfaces = [
        { reseau = local.ie, ipv4 = "203.0.113.10", sous_reseau = "203.0.113.0/24", nom = "internet" },
        { reseau = "europe-pub", ipv4 = "10.0.1.1", sous_reseau = "10.0.1.0/24", nom = "pub" },
        { reseau = "europe-baie", ipv4 = "172.31.255.1", sous_reseau = "172.31.255.0/24", nom = "baie" },
        # Palier 3 : le second transitaire, et le circuit dédié vers Lomé
        { reseau = data.docker_network.transit_b_europe.name, ipv4 = "198.18.2.10", sous_reseau = "198.18.2.0/24", nom = "transit-b" },
        { reseau = data.docker_network.fibre_europe.name, ipv4 = "198.18.9.2", sous_reseau = "198.18.9.0/29", nom = "fibre" },
      ]
      parametres = {
        # --- BGP (Palier 3) : TransAtlantique en priorité (local-pref 200), OuestNet en secours (100) —
        # et vu du monde, on allonge le chemin par OuestNet (2 fois notre AS) pour que le trafic ENTRANT
        # arrive aussi par TransAtlantique. Vers Lomé : le circuit (BFD), le tunnel en secours.
        ASN            = local.asn, BGP_ID = "203.0.113.10", ESPACE = local.espace
        BGP_VOISINS    = "203.0.113.1:65010:transit:200:0 198.18.2.1:65020:transit:100:2 198.18.9.10:64500:fibre 10.99.0.3:64500:vpn"
        ANNONCES       = "198.51.100.0/26 ${local.anycast.prefixe}", ANYCAST_PREFIXE = local.anycast.prefixe
        PI             = "198.51.100.10", ANYCAST_WWW = local.anycast.www, ANYCAST_DNS = local.anycast.dns
        SANTE          = "http://10.0.1.10/sante"
        FIBRE          = "198.18.9.2 198.18.9.8/29 198.18.9.1" # mon adresse, le réseau d'en face, le routeur du circuit
        VPN_EXTREMITE  = "192.0.2.100" # l'autre bout du tunnel de secours : par Internet, toujours
        AUTRES_LIENS   = "transit-b fibre", UPLINKS_BGP = "transit-b"
        IDS            = "oui" # Suricata en ligne sur les liens amont (Palier 3)
        IDS_AUTORISES  = "192.0.2.60" # le scanner de conformité (la console) : il cherche SSH, c'est son travail
        SDWAN_INTERNET = "8333" # le volumineux (stockage objet) par le tunnel Internet ; l'interactif par le circuit
        PUBLIQUE = "203.0.113.10", AMONT = "203.0.113.1", PUB4 = "10.0.1.1/24", PUB6 = "fd00:4d41:5243:1::1/64"
        VLANS    = "20=10.0.2.1/24=fd00:4d41:5243:20::1/64 30=10.0.3.1/24=fd00:4d41:5243:30::1/64"
        VPC      = "10.0.0.0/16", AUTRES_VPC = "10.1.0.0/16", AUTRES_VPC6 = "fd00:4d41:5243:100::/56"
        LB       = "10.0.1.10", LB_SOURCE = "10.0.1.10", NS = "10.0.1.53", NS_PRIVE = "10.0.1.53 10.1.0.83"
        GSLB     = "10.0.1.54", GSLB_PUBLIQUE = "203.0.113.11"
        DB       = "10.0.3.10", DB6 = "fd00:4d41:5243:30::10", DB_PRIMAIRE = local.primaire.ip
        # la base (primaire OU réplique : les règles ne changent pas à la bascule) : les applications des
        # DEUX régions, le coffre, et la base de l'autre région (réplication, dans un sens ou dans l'autre)
        DB_CLIENTS   = "10.0.2.0/24, 10.1.0.0/26, 10.1.0.70"
        DB_DISTANTE  = "10.1.0.70"
        DB_CLIENTS6  = "fd00:4d41:5243:20::/64, fd00:4d41:5243:120::/64"
        STOCKAGE     = "10.0.3.20", S3_CLIENTS = "10.0.2.0/24, 10.0.1.10, 10.1.0.82, 10.99.0.0/24"
        COFFRE       = "10.0.3.30", COFFRE_CLIENTS = "10.0.2.0/24, 10.1.0.0/26, 10.1.0.70, 10.99.0.0/24, 10.0.1.10, 10.1.0.82"
        WG_ADRESSE   = "10.99.0.1/24", WG_PORT = "51820"
        DEBIT_TUNNEL = "18mbit" # juste sous la capacité du câble (20 Mbit/s) : la file se forme chez nous
      }
      fichiers = {
        "/lab/wg/prive.key"          = local.wg.europe.prive
        "/lab/wg/pairs/console.conf" = "[Peer]  # la console (administration)\nPublicKey = ${local.wg.console.public}\nAllowedIPs = 10.99.0.2/32\n"
        "/lab/wg/pairs/lome.conf"    = "[Peer]  # la passerelle de Lomé (VPN site à site)\nPublicKey = ${local.wg.lome.public}\nEndpoint = 192.0.2.100:51820\nAllowedIPs = 10.99.0.3/32, 10.1.0.0/16, fd00:4d41:5243:100::/56\nPersistentKeepalive = 25\n"
      }
    }
    lb = {
      role       = "lb", region = "europe"
      interfaces = [{ reseau = "europe-pub", ipv4 = "10.0.1.10", sous_reseau = "10.0.1.0/24", nom = "pub" }]
      parametres = {
        GW = "10.0.1.1", ADRESSE6 = "fd00:4d41:5243:1::10/64"
        # les applications : découvertes par le DNS (publiées par la couche plateforme)
        DECOUVERTE = "apps-europe.gslb.marche.test", DNS_DECOUVERTE = "10.0.1.54", STATIQUE = "10.0.3.20:8333"
      }
      fichiers = { "/lab/tls/www.pem" = local.pem.www }
    }
    ns1 = {
      role       = "ns", region = "europe"
      interfaces = [{ reseau = "europe-pub", ipv4 = "10.0.1.53", sous_reseau = "10.0.1.0/24", nom = "pub" }]
      parametres = {
        MODE_DNS         = "primaire", GW = "10.0.1.1", RESOLVEUR = "10.0.1.1", ADRESSE4 = "10.0.1.53", ADRESSE6 = "fd00:4d41:5243:1::53/64"
        CLIENTS_INTERNES = "10.0.0.0/16; 10.1.0.0/16; 10.99.0.0/24; fd00:4d41:5243::/48"
        SECONDAIRES      = "10.1.0.83", TSIG = random_bytes.tsig.base64, TSIG_INTERNE = random_bytes.tsig_interne.base64
        GSLB_ADRESSE     = "10.0.1.54/24", PDNS_API = random_password.pdns_api.result
      }
      fichiers = { "/lab/zones/externe" = local.zone_externe, "/lab/zones/interne" = local.zone_interne }
    }
    db = {
      role       = "db", region = "europe"
      interfaces = [{ reseau = "europe-baie", ipv4 = "172.31.255.31", sous_reseau = "172.31.255.0/24", nom = "baie" }]
      parametres = merge(local.base_commun, local.parametres_base.europe, {
        VLAN = "30", ADRESSE4 = "10.0.3.10/24", GW = "10.0.3.1", ADRESSE6 = "fd00:4d41:5243:30::10/64"
      })
      fichiers = {}
    }
    stockage = {
      role       = "stockage", region = "europe"
      interfaces = [{ reseau = "europe-baie", ipv4 = "172.31.255.41", sous_reseau = "172.31.255.0/24", nom = "baie" }]
      parametres = {
        VLAN            = "30", ADRESSE4 = "10.0.3.20/24", GW = "10.0.3.1", ADRESSE6 = "fd00:4d41:5243:30::20/64"
        S3_ADMIN_SECRET = random_password.s3_admin.result
        S3_CLIENTS      = "10.0.2.0/24, 10.0.1.10, 10.1.0.82, 10.99.0.0/24"
      }
      fichiers = {}
    }
    coffre = {
      role       = "coffre", region = "europe"
      interfaces = [{ reseau = "europe-baie", ipv4 = "172.31.255.51", sous_reseau = "172.31.255.0/24", nom = "baie" }]
      parametres = {
        VLAN = "30", ADRESSE4 = "10.0.3.30/24", GW = "10.0.3.1", ADRESSE6 = "fd00:4d41:5243:30::30/64"
        # + les bases (la primaire sauvegarde avec un secret du coffre ; même VLAN pour db : CE pare-feu décide)
        COFFRE_CLIENTS = "10.0.2.0/24, 10.1.0.0/26, 10.99.0.0/24, 10.0.3.10, 10.1.0.70, 10.0.1.10, 10.1.0.82" # + les répartiteurs (leur identité de service, Palier 3)
      }
      fichiers = {
        "/lab/tls/coffre.key" = tls_private_key.cle["coffre"].private_key_pem
        "/lab/tls/coffre.crt" = "${tls_locally_signed_cert.cert["coffre"].cert_pem}${local.ac_cert}"
        "/lab/tls/racine.crt" = local.racine
      }
    }

    # =========================================================== région Lomé (VPC 10.1.0.0/16, VLSM)
    passerelle-lome = {
      role = "passerelle", region = "lome"
      interfaces = [
        { reseau = local.il, ipv4 = "192.0.2.100", sous_reseau = "192.0.2.0/24", nom = "internet" },
        { reseau = "lome-pub", ipv4 = "10.1.0.81", sous_reseau = "10.1.0.80/28", nom = "pub" },
        { reseau = "lome-baie", ipv4 = "172.31.254.1", sous_reseau = "172.31.254.0/24", nom = "baie" },
        # Palier 3 : le second transitaire, le point d'échange TGIX, et le circuit dédié vers l'Europe
        { reseau = data.docker_network.transit_b_lome.name, ipv4 = "198.18.3.100", sous_reseau = "198.18.3.0/24", nom = "transit-b" },
        { reseau = data.docker_network.ixp.name, ipv4 = "198.18.1.64", sous_reseau = "198.18.1.0/24", nom = "ixp" },
        { reseau = data.docker_network.fibre_lome.name, ipv4 = "198.18.9.10", sous_reseau = "198.18.9.8/29", nom = "fibre" },
      ]
      parametres = {
        # --- BGP (Palier 3) : l'IXP d'abord (local, direct, gratuit : 300), puis TransAtlantique (200),
        # OuestNet en dernier recours (100, et chemin allongé vers lui)
        ASN          = local.asn, BGP_ID = "192.0.2.100", ESPACE = local.espace
        BGP_VOISINS  = "198.18.1.254:65100:ixp:300 192.0.2.1:65010:transit:200:0 198.18.3.1:65020:transit:100:2 198.18.9.2:64500:fibre 10.99.0.1:64500:vpn"
        ANNONCES     = "198.51.100.64/26 ${local.anycast.prefixe}", ANYCAST_PREFIXE = local.anycast.prefixe
        PI           = "198.51.100.100", ANYCAST_WWW = local.anycast.www, ANYCAST_DNS = local.anycast.dns
        SANTE        = "http://10.1.0.82/sante"
        FIBRE        = "198.18.9.10 198.18.9.0/29 198.18.9.9"
        VPN_EXTREMITE = "203.0.113.10"
        AUTRES_LIENS = "transit-b ixp fibre", UPLINKS_BGP = "transit-b ixp"
        IDS          = "oui"
        IDS_AUTORISES = "192.0.2.60"
        SDWAN_INTERNET = "8333"
        PUBLIQUE     = "192.0.2.100", AMONT = "192.0.2.1", PUB4 = "10.1.0.81/28", PUB6 = "fd00:4d41:5243:101::1/64"
        VLANS        = "20=10.1.0.1/26=fd00:4d41:5243:120::1/64 30=10.1.0.65/28=fd00:4d41:5243:130::1/64"
        VPC          = "10.1.0.0/16", AUTRES_VPC = "10.0.0.0/16", AUTRES_VPC6 = "fd00:4d41:5243::/56"
        LB           = "10.1.0.82", LB_SOURCE = "10.1.0.82", NS = "10.1.0.83", NS_PRIVE = "10.1.0.83 10.0.1.53"
        GSLB         = "10.1.0.84", GSLB_PUBLIQUE = "192.0.2.101"
        DB           = "10.1.0.70", DB6 = "fd00:4d41:5243:130::70", DB_PRIMAIRE = local.primaire.ip
        DB_CLIENTS   = "10.1.0.0/26, 10.0.2.0/24, 10.0.3.10, 10.0.3.30"
        DB_CLIENTS6  = "fd00:4d41:5243:120::/64, fd00:4d41:5243:20::/64"
        DB_DISTANTE  = "10.0.3.10", COFFRE_DISTANT = "10.0.3.30" # la base, si elle devient primaire, sauvegarde
        WG_ADRESSE   = "10.99.0.3/24", WG_PORT = "51820"
        DEBIT_TUNNEL = "18mbit"
      }
      fichiers = {
        "/lab/wg/prive.key"         = local.wg.lome.prive
        "/lab/wg/pairs/europe.conf" = "[Peer]  # la passerelle d'Europe (VPN site à site)\nPublicKey = ${local.wg.europe.public}\nEndpoint = 203.0.113.10:51820\nAllowedIPs = 10.99.0.0/24, 10.0.0.0/16, fd00:4d41:5243::/56\nPersistentKeepalive = 25\n"
      }
    }
    lb-lome = {
      role       = "lb", region = "lome"
      interfaces = [{ reseau = "lome-pub", ipv4 = "10.1.0.82", sous_reseau = "10.1.0.80/28", nom = "pub" }]
      parametres = {
        GW         = "10.1.0.81", ADRESSE6 = "fd00:4d41:5243:101::82/64"
        DECOUVERTE = "apps-lome.gslb.marche.test", DNS_DECOUVERTE = "10.1.0.84", STATIQUE = "10.0.3.20:8333"
      }
      fichiers = { "/lab/tls/www.pem" = local.pem.www }
    }
    ns2 = {
      role       = "ns", region = "lome"
      interfaces = [{ reseau = "lome-pub", ipv4 = "10.1.0.83", sous_reseau = "10.1.0.80/28", nom = "pub" }]
      parametres = {
        MODE_DNS         = "secondaire", PRIMAIRE_DNS = "10.0.1.53", TSIG = random_bytes.tsig.base64, TSIG_INTERNE = random_bytes.tsig_interne.base64
        CLIENTS_INTERNES = "10.0.0.0/16; 10.1.0.0/16; 10.99.0.0/24; fd00:4d41:5243::/48"
        GW               = "10.1.0.81", RESOLVEUR = "10.1.0.81", ADRESSE4 = "10.1.0.83", ADRESSE6 = "fd00:4d41:5243:101::83/64"
        GSLB_ADRESSE     = "10.1.0.84/28", PDNS_API = random_password.pdns_api.result
      }
      fichiers = {}
    }
    db-lome = {
      role       = "db", region = "lome"
      interfaces = [{ reseau = "lome-baie", ipv4 = "172.31.254.31", sous_reseau = "172.31.254.0/24", nom = "baie" }]
      parametres = merge(local.base_commun, local.parametres_base.lome, {
        VLAN = "30", ADRESSE4 = "10.1.0.70/28", GW = "10.1.0.65", ADRESSE6 = "fd00:4d41:5243:130::70/64"
      })
      fichiers = {}
    }

    # la supervision : à Lomé, pour survivre à la perte de l'Europe
    supervision = {
      role       = "supervision", region = "lome"
      interfaces = [{ reseau = "lome-pub", ipv4 = "10.1.0.85", sous_reseau = "10.1.0.80/28", nom = "pub" }]
      parametres = { GW = "10.1.0.81", ADRESSE6 = "fd00:4d41:5243:101::85/64" }
      fichiers   = { "/lab/tls/racine.crt" = local.racine }
    }

    # =========================================================== le nœud CDN, à Lomé
    edge = {
      role       = "edge", region = "lome"
      interfaces = [{ reseau = local.il, ipv4 = "192.0.2.80", sous_reseau = "192.0.2.0/24", nom = "internet" }]
      parametres = { GW = "192.0.2.1", ADRESSE4 = "192.0.2.80", RESOLVEUR = "192.0.2.35", CONSOLE = "192.0.2.60" }
      fichiers   = { "/lab/tls/static.pem" = local.pem.static, "/lab/tls/racine.crt" = local.racine }
    }
  })
}

module "machine" {
  source   = "../modules/instance"
  for_each = local.machines

  nom        = each.key
  role       = each.value.role
  interfaces = each.value.interfaces
  etiquettes = merge(local.etiquettes, { region = each.value.region }, try(each.value.etiquettes, {}))
  demarrage  = "#!/bin/bash\n# user data : lancé à chaque démarrage (lab-init.service)\nexec >>/var/log/demarrage.log 2>&1\necho \"=== $(date -Is)\"\nbash /lab/roles/${each.value.role}.sh\n"
  fichiers = merge(
    # SEULEMENT son rôle (et la bibliothèque commune) : modifier un rôle ne remplace que ses machines
    {
      "/lab/roles/commun.sh"             = file("${local.roles_dir}/commun.sh")
      "/lab/roles/${each.value.role}.sh" = file("${local.roles_dir}/${each.value.role}.sh")
    },
    each.value.fichiers,
    {
      "/lab/parametres.sh" = join("", [for k, v in merge(local.commun, { REGION = each.value.region }, each.value.parametres) : "${k}='${v}'\n"])
      "/lab/admin.pub"     = file("/root/.ssh/id_ed25519.pub")
    },
    contains(["app", "db", "lb", "supervision"], each.value.role) ? { # son identité auprès du coffre
      "/lab/tls/client.key" = tls_private_key.cle[each.key].private_key_pem
      "/lab/tls/client.crt" = "${tls_locally_signed_cert.cert[each.key].cert_pem}${local.ac_cert}"
      "/lab/tls/racine.crt" = local.racine
    } : {}
  )

  volumes = lookup(local.donnees, each.key, {})

  depends_on = [docker_network.region, docker_volume.donnees]
}
