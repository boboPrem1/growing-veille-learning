# Image « machine » du lab Networking & Cloud : un serveur Ubuntu 24.04 (systemd, sshd) sur
# lequel TOUS les logiciels des trois paliers sont installés mais ARRÊTÉS et désactivés.
# Le projet porte sur le réseau et le cloud, pas sur « apt install » : vous configurez et
# démarrez vous-même chaque service, rien ne tourne par défaut.
FROM chrislusf/seaweedfs:4.48 AS seaweedfs
FROM quay.io/openbao/openbao:2.7.0 AS openbao

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN echo 'wireshark-common wireshark-common/install-setuid boolean false' | debconf-set-selections \
 && apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus openssh-server sudo cron rsyslog logrotate kmod \
      ca-certificates curl wget gnupg less nano vim tmux jq python3 python3-venv locales tzdata \
      unzip git bash-completion lsof psmisc procps \
      # --- réseau : diagnostic et capture
      iproute2 iputils-ping iputils-tracepath iputils-arping traceroute mtr-tiny tcpdump tshark ethtool \
      bind9-dnsutils netcat-openbsd socat iperf3 ndisc6 conntrack nftables \
      # --- services réseau
      bind9 unbound pdns-server pdns-backend-bind pdns-backend-sqlite3 sqlite3 haproxy nginx radvd \
      wireguard-tools frr apache2-utils \
      # --- données, PKI, sécurité, observabilité
      postgresql postgresql-client pgbackrest openssl certbot suricata \
      prometheus prometheus-node-exporter prometheus-blackbox-exporter prometheus-alertmanager \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /usr/sbin/policy-rc.d

# Terraform (dépôt officiel HashiCorp) et AWS CLI v2 : les mêmes outils qu'avec un vrai cloud
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com noble main" \
      > /etc/apt/sources.list.d/hashicorp.list \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update && apt-get install -y --no-install-recommends terraform docker-ce-cli && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip \
 && unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscli.zip

# Les fournisseurs Terraform des paliers 2 et 3, dans un miroir local : l'Internet du lab est
# fermé (sa racine DNS ne connaît pas registry.terraform.io) et « terraform init » doit marcher.
RUN mkdir -p /tmp/f && cd /tmp/f && cat > versions.tf <<'EOF' \
 && terraform providers mirror /usr/local/share/terraform/plugins >/dev/null && rm -rf /tmp/f
terraform {
  required_providers {
    docker   = { source = "kreuzwerker/docker", version = "3.9.0" }
    aws      = { source = "hashicorp/aws",      version = "6.66.0" }
    vault    = { source = "hashicorp/vault",    version = "5.12.0" }
    powerdns = { source = "pan-net/powerdns",   version = "1.5.0" }
    tls      = { source = "hashicorp/tls" }
    random   = { source = "hashicorp/random" }
    local    = { source = "hashicorp/local" }
  }
}
EOF

# Stockage objet compatible S3, avec une vraie API IAM (politiques JSON appliquées)
COPY --from=seaweedfs /usr/bin/weed /usr/local/bin/weed
# Gestionnaire de secrets (OpenBao : la branche libre de HashiCorp Vault, même API, même CLI)
COPY --from=openbao /usr/bin/bao /usr/local/bin/bao

# Rien ne démarre tout seul : c'est vous qui activez ce dont chaque machine a besoin.
RUN systemctl disable named unbound pdns haproxy nginx radvd frr postgresql suricata iperf3 \
      prometheus prometheus-node-exporter prometheus-blackbox-exporter prometheus-alertmanager \
      unbound-resolvconf certbot.timer 2>/dev/null; \
    systemctl enable ssh cron rsyslog \
 && systemctl mask systemd-logind.service getty.target console-getty.service \
      systemd-udevd.service systemd-udevd-kernel.socket systemd-udevd-control.socket \
 && usermod -aG sudo -s /bin/bash ubuntu \
 && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-cloud-init-users \
 && chmod 440 /etc/sudoers.d/90-cloud-init-users \
 && printf 'PasswordAuthentication no\n' > /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

# L'application Marché (la même que dans les cours Linux et Observabilité), prête à lancer :
# /opt/marche/app + son environnement Python. Les unités systemd sont fournies, désactivées.
COPY app/ /opt/marche/app/
RUN useradd --system --home /var/lib/marche --create-home --shell /usr/sbin/nologin marche \
 && python3 -m venv /opt/marche/venv \
 && /opt/marche/venv/bin/pip install --no-cache-dir -q -r /opt/marche/app/requirements.txt \
 && install -d -m 750 -o root -g marche /etc/marche
COPY lab/docker/fichiers/*.service lab/docker/fichiers/*.target /etc/systemd/system/
COPY lab/docker/fichiers/marche.env.exemple /etc/marche/marche.env.exemple
# La racine de l'« AC publique du lab » (générée par lab.sh au premier démarrage) : dans le magasin
# de confiance de TOUTES les machines, comme les AC publiques dans celui d'un système d'exploitation.
COPY lab/docker/internet/ac/ac.crt /usr/local/share/ca-certificates/ac-publique-lab.crt
RUN update-ca-certificates >/dev/null
COPY lab/docker/fichiers/lab-cles.sh /usr/local/sbin/lab-cles
COPY lab/docker/fichiers/lab-interfaces.sh /usr/local/sbin/lab-interfaces
RUN chmod 644 /etc/systemd/system/*.service /etc/systemd/system/*.target \
 && chmod 755 /usr/local/sbin/lab-cles /usr/local/sbin/lab-interfaces \
 && systemctl enable lab-interfaces.service \
 && rm -f /etc/ssh/ssh_host_* /etc/ssl/private/ssl-cert-snakeoil.key /etc/ssl/certs/ssl-cert-snakeoil.pem \
 && systemctl enable lab-cles.service lab-init.service

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
