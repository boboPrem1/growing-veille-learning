# Image « serveur Ubuntu 24.04 » pour le lab local : aussi proche que possible de l'image
# cloud ubuntu:24.04 utilisée par LXD (systemd, sshd, cron, rsyslog, ufw…).
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus systemd-timesyncd \
      openssh-server sudo cron rsyslog logrotate ufw unattended-upgrades \
      iproute2 iputils-ping bind9-dnsutils netcat-openbsd curl wget ca-certificates \
      less nano vim tmux htop lsof psmisc procps rsync git gnupg bash-completion \
      python3 locales tzdata kmod \
    && rm -rf /var/lib/apt/lists/* \
    # Les images Docker empêchent le démarrage des services pendant apt install : pas un vrai serveur
    && rm -f /usr/sbin/policy-rc.d \
    && systemctl enable ssh cron rsyslog \
    && systemctl mask systemd-logind.service getty.target console-getty.service \
       systemd-udevd.service systemd-udevd-kernel.socket systemd-udevd-control.socket \
    # Comme l'image cloud : l'utilisateur « ubuntu » (déjà présent) est sudoer sans mot de passe,
    # et l'authentification SSH par mot de passe est désactivée
    && usermod -aG sudo -s /bin/bash ubuntu \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-cloud-init-users \
    && chmod 440 /etc/sudoers.d/90-cloud-init-users \
    && printf 'PasswordAuthentication no\n' > /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

# « Disques secondaires » du lab : chaque /var/lib/lab/disques/*.img est rattaché à un
# périphérique loop au démarrage (voir lab.sh ajouter-disque).
COPY lab-cles-ssh.service /etc/systemd/system/lab-cles-ssh.service
RUN rm -f /etc/ssh/ssh_host_* && chmod 644 /etc/systemd/system/lab-cles-ssh.service && systemctl enable lab-cles-ssh.service

COPY lab-disques.sh /usr/local/sbin/lab-disques
COPY lab-disques.service /etc/systemd/system/lab-disques.service
RUN chmod 755 /usr/local/sbin/lab-disques && chmod 644 /etc/systemd/system/lab-disques.service \
    && systemctl enable lab-disques.service

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
