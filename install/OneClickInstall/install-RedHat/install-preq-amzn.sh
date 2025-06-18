#!/usr/bin/env bash
set -euo pipefail

#######################################
#  INSTALL PREREQUISITES (universal)
#######################################

# ---- 1. Авто-детект дистрибутива ------------------------------------------
source /etc/os-release
DIST="${ID,,}"                  # amzn / centos / rhel / fedora …
REV="${VERSION_ID%%.*}"         # 2023 / 9 / 40 …

pkg_mgr="yum"                   # на AL2023 это алиас dnf, но yum есть всегда

# ---- 2. Базовые инструменты ----------------------------------------------
${pkg_mgr} clean all
${pkg_mgr} -y install yum-utils curl

# ---- 3. EPEL --------------------------------------------------------------
if [[ "$DIST" == "amzn" ]]; then            # Amazon Linux 2023
    amazon-linux-extras enable epel
    ${pkg_mgr} -y install epel-release
else                                        # RHEL / CentOS / Rocky / Alma / Fedora
    ${pkg_mgr} -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${REV}.noarch.rpm"
fi

# ---- 4. RabbitMQ  ---------------------------------------------------------
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh   | os=el dist=9 bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh            | os=el dist=9 bash

# ---- 5. NodeJS  -----------------------------------------------------------
NODE_VER="18"
curl -fsSL https://rpm.nodesource.com/setup_${NODE_VER}.x | sed '/update -y/d' | bash -

# ---- 6. MySQL -------------------------------------------------------------
${pkg_mgr} -y module disable mysql || true   # Fedora/RHEL модули
${pkg_mgr} -y install https://repo.mysql.com/mysql84-community-release-el9-1.noarch.rpm

# ---- 7. OpenSearch (repo выдаёт свежий RPM) -------------------------------
curl -sSL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.x.repo \
     -o /etc/yum.repos.d/opensearch-2.x.repo
OS_DASHBOARDS="true"   # если нужна веб-морда

if [[ "$OS_DASHBOARDS" == "true" ]]; then
    curl -sSL https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.x/opensearch-dashboards-2.x.repo \
         -o /etc/yum.repos.d/opensearch-dashboards-2.x.repo
fi

# ---- 8. Nginx / OpenResty -------------------------------------------------
if [[ "$DIST" != "fedora" ]]; then
  NGINX_BASE="https://nginx.org/packages"
  case "$DIST" in
       amzn)   NGINX_PATH="amzn/${REV}" ;;
       centos) NGINX_PATH="centos/${REV}" ;;
       rhel)   NGINX_PATH="rhel/${REV}"   ;;
  esac
  cat > /etc/yum.repos.d/nginx.repo <<EOF
[nginx-stable]
name=Nginx stable
baseurl=${NGINX_BASE}/${NGINX_PATH}/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
EOF
fi

rpm --import https://openresty.org/package/pubkey.gpg
curl -s -o /etc/yum.repos.d/openresty.repo \
     https://openresty.org/package/${DIST//rhel/centos}/openresty.repo

# ---- 9. Пакеты ------------------------------------------------------------
JAVA_VER="21"      # можно 17/21 – что нужно
${pkg_mgr} -y install \
    python3 \
    nodejs \
    dotnet-sdk-$(rpm -qa 'dotnet-sdk-*' --qf '%{VERSION}\n' 2>/dev/null | sort -Vr | head -1 || echo 8.0) \
    opensearch                                   \
    mysql-community-server                       \
    postgresql\*server                           \
    rabbitmq-server                              \
    valkey                                       \
    SDL2-devel                                   \
    expect                                       \
    java-${JAVA_VER}-amazon-corretto-headless    \
    policycoreutils-python-utils                 \
    --enablerepo=opensearch-2.x

# ----10. PostgreSQL (инициализация) ----------------------------------------
if systemctl list-unit-files | grep -q postgresql.*16; then
  id postgres &>/dev/null || useradd -r -u 26 -g 26 -s /bin/bash postgres
  [[ -d /var/lib/pgsql/data ]] || {
      mkdir -p /var/lib/pgsql/data
      chown -R postgres:postgres /var/lib/pgsql
      sudo -u postgres initdb -D /var/lib/pgsql/data
  }
  sed -Ei "s/(host\s+(all|replication)\s+all\s+(127\.0\.0\.1\/32|\:\:1\/128)\s+)(ident|trust|md5)/\1scram-sha-256/" \
      /var/lib/pgsql/data/pg_hba.conf
  sed -i "s/^#\?password_encryption = .*/password_encryption = 'scram-sha-256'/" \
      /var/lib/pgsql/data/postgresql.conf
fi

# ----11. semanage (если доступен) -----------------------------------------
command -v semanage &>/dev/null && semanage permissive -a httpd_t \
    || echo "⚠️  semanage отсутствует – SELinux не настроен"

echo -e "\n✅  Зависимости установлены на ${PRETTY_NAME}\n"
