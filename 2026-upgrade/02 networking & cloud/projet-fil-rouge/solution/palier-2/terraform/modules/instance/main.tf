# Une « instance » : un conteneur de l'image du lab qui se comporte comme une machine virtuelle.
# Son script de démarrage (/lab/init.sh) joue le rôle du « user data » de cloud-init : il est
# exécuté à chaque démarrage. Le modifier REMPLACE l'instance (infrastructure immuable).
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker" }
  }
}

resource "docker_container" "this" {
  name          = var.nom
  hostname      = var.nom
  image         = var.image
  privileged    = true # systemd, pare-feu, VLAN, WireGuard dans un conteneur
  cgroupns_mode = "host"
  restart       = "unless-stopped"
  stop_signal   = "SIGRTMIN+3"
  stop_timeout  = 20
  tmpfs         = { "/run" = "rw", "/run/lock" = "rw" }

  dynamic "volumes" { # les données (base, coffre, stockage) survivent au remplacement de la machine
    for_each = var.volumes
    content {
      container_path = volumes.key
      volume_name    = volumes.value
    }
  }

  volumes {
    host_path      = "/sys/fs/cgroup"
    container_path = "/sys/fs/cgroup"
  }

  dynamic "networks_advanced" {
    for_each = var.interfaces
    content {
      name         = networks_advanced.value.reseau
      ipv4_address = networks_advanced.value.ipv4
    }
  }

  # les noms d'interface, d'après leur sous-réseau (lab-interfaces.service, avant le réseau)
  upload {
    file    = "/etc/lab/interfaces"
    content = join("", [for i in var.interfaces : "${i.sous_reseau} ${i.nom}\n"])
  }
  upload {
    file       = "/lab/init.sh"
    content    = var.demarrage
    executable = true
  }
  dynamic "upload" {
    # (pas de for_each sur une valeur sensible : on itère sur les CHEMINS, qui ne sont pas secrets)
    for_each = nonsensitive(toset(keys(var.fichiers)))
    content {
      file       = upload.value
      content    = var.fichiers[upload.value]
      executable = endswith(upload.value, ".sh")
    }
  }

  dynamic "labels" {
    for_each = merge(var.etiquettes, { projet = "marche", role = var.role })
    content {
      label = labels.key
      value = labels.value
    }
  }
}
