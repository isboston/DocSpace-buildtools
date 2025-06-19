#!/bin/bash

set -e

cat<<EOF

#######################################
#  INSTALL PREREQUISITES
#######################################

EOF

# clean yum cache
${package_manager} clean all

${package_manager} -y install yum-utils

{ yum check-update postgresql; PSQLExitCode=$?; } || true #Checking for postgresql update
{ yum check-update "$DIST"*-release; exitCode=$?; } || true #Checking for distribution update

if rpm -qa | grep 'mariadb.*config' >/dev/null 2>&1; then
   echo "$RES_MARIADB" && exit 0
fi

#add rabbitmq & erlang repo
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | os=el dist=9 bash
# curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | os=el dist=9 bash

if rpm -q rabbitmq-server; then
    if [ "$(yum list installed rabbitmq-server | awk 'NR>1 {gsub(/^@/, "", $NF); print $NF}')" != "$(repoquery rabbitmq-server --qf='%{ui_from_repo}')" ]; then
        res_rabbitmq_update
        echo $RES_RABBITMQ_VERSION
        echo $RES_RABBITMQ_REMINDER
        echo $RES_RABBITMQ_INSTALLATION
        read_rabbitmq_update
    fi
fi

if [[ "$(uname -m)" =~ (arm|aarch) ]]; then
    ERLANG_LATEST_URL=$(curl -s https://api.github.com/repos/rabbitmq/erlang-rpm/releases | \
        jq -r '.[] | .assets[]? | select(.name | test("erlang-[0-9\\.]+-1\\.el" + 9 + "\\.aarch64\\.rpm$")) | .browser_download_url' | head -n1)
    yum install -y "${ERLANG_LATEST_URL}"
else
    curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | os=el dist=9 bash
fi

PSQL_INSTALLED_VERSION=$(rpm -qa | grep -Eo '^postgresql[0-9]+' | sed 's/^postgresql//' | sort -nr | head -1)
PSQL_AVAILABLE_VERSION=$(yum list postgresql\*-server --available | awk '/^postgresql[0-9]+-server/ {gsub("postgresql|-server.*","",$1); print $1}' | sort -nr | head -1)
PSQL_VERSION=${PSQL_INSTALLED_VERSION:-$PSQL_AVAILABLE_VERSION}
{ yum check-update postgresql${PSQL_VERSION}; PSQLExitCode=$?; } || true

#add nodejs repo
NODE_VERSION="18"
curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | sed '/update -y/d' | bash - || true

#add mysql repo
dnf remove -y @mysql && dnf module -y reset mysql && dnf module -y disable mysql
MYSQL_REPO_VERSION="$(curl https://repo.mysql.com | grep -oP "mysql84-community-release-${MYSQL_DISTR_NAME}${REV}-\K.*" | grep -o '^[^.]*' | sort | tail -n1)"
yum install -y https://repo.mysql.com/mysql84-community-release-"${MYSQL_DISTR_NAME}""${REV}"-"${MYSQL_REPO_VERSION}".noarch.rpm || true

#add opensearch repo
curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.x.repo -o /etc/yum.repos.d/opensearch-2.x.repo
ELASTIC_VERSION="2.18.0"
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="$(echo "${package_sysname}!A1")"

#add opensearch dashboards repo
if [ ${INSTALL_FLUENT_BIT} == "true" ]; then
	curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.x/opensearch-dashboards-2.x.repo -o /etc/yum.repos.d/opensearch-dashboards-2.x.repo
	DASHBOARDS_VERSION="2.18.0"
fi

rpm --import https://openresty.org/package/pubkey.gpg
curl -o /etc/yum.repos.d/openresty.repo https://openresty.org/package/centos/openresty.repo
sed -i "s/\$releasever/9/g" /etc/yum.repos.d/openresty.repo

JAVA_VERSION=21
${package_manager} -y install \
			python3 \
			nodejs ${NODEJS_OPTION} \
			opensearch-${ELASTIC_VERSION} \
			mysql-community-server \
			postgresql${PSQL_VERSION} \
			postgresql${PSQL_VERSION}-server \
			rabbitmq-server$rabbitmq_version \
            SDL2-devel \
			valkey \
			expect \
			java-${JAVA_VERSION}-amazon-corretto



# === dotnet-sdk 9.0: ручная установка ===

DOTNET_VERSION=9.0.100
DOTNET_DIR=/opt/dotnet
DOTNET_BIN=${DOTNET_DIR}/dotnet
DOTNET_TGZ_URL="https://download.visualstudio.microsoft.com/download/pr/70ccf458-471b-4e90-8040-bb474395b3f7/f7b7c6f8b5fd99cd85fc26f845cbb1c6/dotnet-sdk-${DOTNET_VERSION}-linux-x64.tar.gz"

# === Установка .NET SDK 9 вручную ===
DOTNET_VER=9.0.301
DOTNET_DIR=/opt/dotnet

echo "Installing .NET SDK ${DOTNET_VER} manually..."

# установить зависимости
${package_manager} install -y libicu zlib krb5-libs openssl curl libcurl lttng-ust libunwind libuuid

# загрузка и распаковка
curl -sSL "https://dotnetcli.blob.core.windows.net/dotnet/Sdk/${DOTNET_VER}/dotnet-sdk-${DOTNET_VER}-linux-x64.tar.gz" | sudo tar -xz -C "${DOTNET_DIR}"


sudo tee /etc/profile.d/dotnet.sh >/dev/null <<EOF
export DOTNET_ROOT=${DOTNET_DIR}
export PATH=\$DOTNET_ROOT:\$PATH
EOF
source /etc/profile.d/dotnet.sh

# проверка
dotnet --info || { echo "❌ dotnet install failed"; exit 1; }
echo "FINISH .NET SDK ${DOTNET_VERSION} manually..."
dotnet --info
java --version

# Set Java ${JAVA_VERSION} as the default version
JAVA_PATH=$(find /usr/lib/jvm/ -name "java" -path "*java-${JAVA_VERSION}*" | head -1)
alternatives --install /usr/bin/java java "$JAVA_PATH" 100 && alternatives --set java "$JAVA_PATH"

#add repo, install fluent-bit
if [ "${INSTALL_FLUENT_BIT}" == "true" ]; then 
	[ "$DIST" != "fedora" ] && curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | bash || yum -y install fluent-bit
	${package_manager} -y install opensearch-dashboards-"${DASHBOARDS_VERSION}" --enablerepo=opensearch-dashboards-2.x
fi

if [[ $PSQLExitCode -eq $UPDATE_AVAILABLE_CODE ]]; then
	yum -y install postgresql-upgrade
	postgresql-setup --upgrade || true
fi

/usr/bin/postgresql-setup --initdb --unit postgresql-${PSQL_VERSION} || true

sed -E -i "s/(host\s+(all|replication)\s+all\s+(127\.0\.0\.1\/32|\:\:1\/128)\s+)(ident|trust|md5)/\1scram-sha-256/" /var/lib/pgsql/${PSQL_VERSION}/data/pg_hba.conf
sed -i "s/^#\?password_encryption = .*/password_encryption = 'scram-sha-256'/" /var/lib/pgsql/${PSQL_VERSION}/data/postgresql.conf

if ! command -v semanage &> /dev/null; then
	yum install -y policycoreutils-python-utils
fi 

semanage permissive -a httpd_t

package_services="rabbitmq-server postgresql valkey mysqld"
rpm -q valkey &>/dev/null && package_services="${package_services//redis/valkey}" || true # https://fedoraproject.org/wiki/Changes/Replace_Redis_With_Valkey 
