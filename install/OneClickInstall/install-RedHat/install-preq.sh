#!/usr/bin/env bash
# install-preq‑amzn.sh — ONLYOFFICE DocSpace prerequisites for Amazon Linux 2023
set -euo pipefail

cat <<'EOF'

#######################################
#  INSTALL PREREQUISITES (Amazon 2023)
#######################################

EOF

##############################################################################
# 1. Базовые переменные окружения (переданы из tools.sh, но ставим дефолты)
##############################################################################
DIST="${DIST:-amazon}"             # «нормализованное» имя дистрибутива
REV="${REV:-9}"                    # совместим с RHEL 9 (el9)
package_manager="dnf"
MYSQL_DISTR_NAME="el"
OPENRESTY_DISTR_NAME="amazon"

##############################################################################
# 2. Обновление метаданных и yum-utils
##############################################################################
${package_manager} clean all
${package_manager} -y install yum-utils

##############################################################################
# 3. MariaDB‑конфликт
##############################################################################
if rpm -qa | grep -Eq 'mariadb.*config'; then
    echo "$RES_MARIADB"
    exit 1
fi

##############################################################################
# 4. RabbitMQ & Erlang (репозитории packagecloud, именно os=amzn dist=2023)
##############################################################################
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh \
    | os=amzn dist=2023 bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh \
    | os=amzn dist=2023 bash

##############################################################################
# 5. Node.js 18 LTS
##############################################################################
NODE_VERSION=18
curl -fsSL "https://rpm.nodesource.com/setup_${NODE_VERSION}.x" \
    | sed '/update -y/d' | bash - || true

##############################################################################
# 6. MySQL 8.4 Community
##############################################################################
dnf -y remove @mysql || true
dnf -y module reset  mysql || true
dnf -y module disable mysql || true

MYSQL_REPO_PKG="mysql84-community-release-el${REV}-1.noarch.rpm"
yum -y install "https://repo.mysql.com/${MYSQL_REPO_PKG}" || true
if ! rpm -q mysql-community-server &>/dev/null; then
    MYSQL_FIRST_TIME_INSTALL=true
fi

##############################################################################
# 7. OpenSearch 2.x (и Dashboards при INSTALL_FLUENT_BIT=true)
##############################################################################
curl -sSL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.x.repo \
     -o /etc/yum.repos.d/opensearch-2.x.repo
ELASTIC_VERSION="2.18.0"
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="${package_sysname:-onlyoffice}!A1"

if [[ "${INSTALL_FLUENT_BIT:-false}" == "true" ]]; then
    curl -sSL https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.x/opensearch-dashboards-2.x.repo \
         -o /etc/yum.repos.d/opensearch-dashboards-2.x.repo
    DASHBOARDS_VERSION="2.18.0"
fi

##############################################################################
# 8. Репозитории nginx и OpenResty
##############################################################################
cat > /etc/yum.repos.d/nginx.repo <<EOF_NGX
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/${REV}/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF_NGX

rpm --import https://openresty.org/package/pubkey.gpg
curl -o /etc/yum.repos.d/openresty.repo \
     "https://openresty.org/package/${OPENRESTY_DISTR_NAME}/openresty2.repo"

##############################################################################
# 9. .NET SDK (8 LTS или 9 preview)
##############################################################################
if [[ "${DOTNET_CHANNEL:-lts}" == "preview" ]]; then
    rpm -Uvh https://packages.microsoft.com/config/centos/9.0-preview/packages-microsoft-prod.rpm
    DOTNET_PKG="dotnet-sdk-9.0-preview"
else
    rpm -Uvh https://packages.microsoft.com/config/amazonlinux/2023/packages-microsoft-prod.rpm
    DOTNET_PKG="dotnet-sdk-8.0"
fi

##############################################################################
# 10. Выбор Redis / Valkey
##############################################################################
if dnf list --available valkey &>/dev/null; then
    REDIS_PKG="valkey"
else
    REDIS_PKG="redis"
fi

##############################################################################
# 11. Установка всех пакетов
##############################################################################
JAVA_VERSION=21
${package_manager} -y install \
    python3 \
    nodejs ${NODEJS_OPTION:-} \
    "${DOTNET_PKG}" \
    opensearch-${ELASTIC_VERSION} \
    mysql-community-server \
    postgresql15 \
    postgresql15-server \
    rabbitmq-server \
    "${REDIS_PKG}" \
    SDL2 \
    expect \
    java-${JAVA_VERSION}-corretto-headless \
    --enablerepo=opensearch-2.x

##############################################################################
# 12. Инициализация / апгрейд PostgreSQL 15
##############################################################################
postgresql-setup --initdb || true
sed -E -i \
    "s/(host\s+(all|replication)\s+all\s+(127\.0\.0\.1\/32|\:\:1\/128)\s+)(ident|trust|md5)/\1scram-sha-256/" \
    /var/lib/pgsql/data/pg_hba.conf
sed -i \
    "s/^#\?password_encryption = .*/password_encryption = 'scram-sha-256'/" \
    /var/lib/pgsql/data/postgresql.conf

##############################################################################
# 13. SELinux — включаем semanage и ослабляем httpd_t
##############################################################################
if ! command -v semanage &>/dev/null; then
    dnf -y install policycoreutils-python-utils
fi
semanage permissive -a httpd_t || true

##############################################################################
# 14. Автозапуск сервисов (можно снять, если логика делает это позже)
##############################################################################
systemctl enable --now \
    postgresql-15 \
    mysqld \
    rabbitmq-server \
    "${REDIS_PKG}" || true

echo
echo "✅  Prerequisites for ONLYOFFICE DocSpace on Amazon Linux 2023 installed."
