#!/bin/bash

set -e

cat<<EOF

#######################################
#  INSTALL PREREQUISITES
#######################################

EOF

${package_manager} clean all

{ ${package_manager} check-update "$DIST"*-release; exitCode=$?; } || true #Checking for distribution update

if rpm -qa | grep 'mariadb.*config' >/dev/null 2>&1; then
   echo "$RES_MARIADB" && exit 0
fi

# Add RabbitMQ and Erlang repositories
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | os=el dist=9 bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | os=el dist=9 bash

# Detect installed or available PostgreSQL version
PSQL_INSTALLED_VERSION=$(rpm -qa | grep -Eo '^postgresql[0-9]+' | sed 's/^postgresql//' | sort -nr | head -1)
PSQL_AVAILABLE_VERSION=$(${package_manager} list postgresql\*-server --available | awk '/^postgresql[0-9]+-server/ {gsub("postgresql|-server.*","",$1); print $1}' | sort -nr | head -1)
PSQL_VERSION=${PSQL_INSTALLED_VERSION:-$PSQL_AVAILABLE_VERSION}
{ ${package_manager} check-update postgresql"${PSQL_VERSION}"; PSQLExitCode=$?; } || true

# Add Node.js repository
NODE_VERSION="18"
curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | sed '/update -y/d' | bash - || true

# Add MySQL repository
${package_manager} remove -y @mysql && ${package_manager} module -y reset mysql && ${package_manager} module -y disable mysql
MYSQL_REPO_VERSION="$(curl https://repo.mysql.com | grep -oP "mysql84-community-release-${MYSQL_DISTR_NAME}${REV}-\K.*" | grep -o '^[^.]*' | sort | tail -n1)"
${package_manager} install -y https://repo.mysql.com/mysql84-community-release-"${MYSQL_DISTR_NAME}""${REV}"-"${MYSQL_REPO_VERSION}".noarch.rpm || true

if ! rpm -q mysql-community-server; then
    MYSQL_FIRST_TIME_INSTALL="true"
fi

# Add OpenSearch repository
curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.x.repo -o /etc/yum.repos.d/opensearch-2.x.repo
ELASTIC_VERSION="2.18.0"
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="$(echo "${package_sysname}!A1")"

# Add OpenSearch Dashboards repository
if [ "${INSTALL_FLUENT_BIT}" == "true" ]; then
    curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.x/opensearch-dashboards-2.x.repo -o /etc/yum.repos.d/opensearch-dashboards-2.x.repo
    DASHBOARDS_VERSION="2.18.0"
fi

# Add OpenResty repository
rpm --import https://openresty.org/package/pubkey.gpg
curl -o /etc/yum.repos.d/openresty.repo https://openresty.org/package/"${OPENRESTY_DISTR_NAME}"/openresty.repo
sed -i "s/\$releasever/2023/g" /etc/yum.repos.d/openresty.repo

JAVA_VERSION=21
${package_manager} -y install \
			python3 \
			nodejs \
			opensearch-${ELASTIC_VERSION} \
			mysql-community-server \
			postgresql${PSQL_VERSION} \
			postgresql${PSQL_VERSION}-server \
			rabbitmq-server$rabbitmq_version \
			valkey \
			expect

# Use AlmaLinux and EPEL repos to install ffmpeg-free, SDL2, and OpenJDK
tee /etc/yum.repos.d/alma-temporary.repo <<'EOF'
[alma-appstream]
name=AlmaLinux 9 AppStream
baseurl=https://repo.almalinux.org/almalinux/9/AppStream/$basearch/os/
enabled=0
gpgcheck=0

[alma-crb]
name=AlmaLinux 9 CRB
baseurl=https://repo.almalinux.org/almalinux/9/CRB/$basearch/os/
enabled=0
gpgcheck=0

[epel-9]
name=EPEL 9 Everything
baseurl=https://dl.fedoraproject.org/pub/epel/9/Everything/$basearch/
enabled=0
gpgcheck=0
EOF

${package_manager} install -y --enablerepo=alma-appstream,alma-crb,epel-9 ffmpeg-free SDL2 java-${JAVA_VERSION}-openjdk-headless
${package_manager} config-manager --set-disabled alma-appstream alma-crb epel-9

# Add Microsoft .NET 9 repository and install SDK
rpm --import https://packages.microsoft.com/keys/microsoft.asc

tee /etc/yum.repos.d/microsoft-dotnet9.repo <<'EOF'
[microsoft-dotnet9]
name=Microsoft .NET 9 (RHEL9)
baseurl=https://packages.microsoft.com/yumrepos/microsoft-rhel9.0-prod
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

${package_manager} clean all && ${package_manager} makecache
${package_manager} install -y dotnet-sdk-9.0 --allowerasing

# Set Java ${JAVA_VERSION} as system default
JAVA_PATH=$(find /usr/lib/jvm/ -name "java" -path "*java-${JAVA_VERSION}*" | head -1)
alternatives --install /usr/bin/java java "$JAVA_PATH" 100 && alternatives --set java "$JAVA_PATH"

# Add repository and install Fluent Bit
if [ "${INSTALL_FLUENT_BIT}" == "true" ]; then
    curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | bash || ${package_manager} -y install fluent-bit
    ${package_manager} -y install opensearch-dashboards-"${DASHBOARDS_VERSION}" --enablerepo=opensearch-dashboards-2.x
fi

if [[ $PSQLExitCode -eq $UPDATE_AVAILABLE_CODE ]]; then
    ${package_manager} -y install postgresql-upgrade
    postgresql-setup --upgrade || true
fi

postgresql-setup --initdb || true

sed -E -i "s/(host\s+(all|replication)\s+all\s+(127\.0\.0\.1\/32|\:\:1\/128)\s+)(ident|trust|md5)/\1scram-sha-256/" /var/lib/pgsql/data/pg_hba.conf
sed -i "s/^#\?password_encryption = .*/password_encryption = 'scram-sha-256'/" /var/lib/pgsql/data/postgresql.conf

if ! command -v semanage &> /dev/null; then
    ${package_manager} install -y policycoreutils-python-utils
fi

semanage permissive -a httpd_t

package_services="rabbitmq-server postgresql valkey mysqld"

