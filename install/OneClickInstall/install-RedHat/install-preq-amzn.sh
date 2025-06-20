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

if grep -q "Amazon Linux 2023" /etc/os-release; then
  dnf install -y --nogpgcheck https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-9.noarch.rpm

  dnf config-manager --set-enabled crb || true

  dnf --enablerepo=rpmfusion-free install -y ffmpeg-free

  dnf config-manager --set-disabled rpmfusion-free
fi


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
			valkey \
			expect \
			java-${JAVA_VERSION}-amazon-corretto-headless

#######################################
#  FIXES FOR AMAZON LINUX 2023
#######################################

sudo tee /etc/yum.repos.d/alma-appstream.repo << 'EOF'
[alma-appstream]
name = AlmaLinux 9 – AppStream (SDL2)
baseurl = https://repo.almalinux.org/almalinux/9/AppStream/x86_64/os/
enabled = 1
gpgcheck = 0
EOF

sudo dnf install -y SDL2 SDL2-devel

sudo dnf config-manager --set-disabled alma-appstream


# # 2. Меняем curl-minimal -> curl (и libcurl)
# dnf swap -y curl-minimal curl
# dnf swap -y libcurl-minimal libcurl

# # 3. Ставим зависимости для .NET без конфликтов
# dnf install -y libicu zlib krb5-libs openssl lttng-ust libunwind libuuid

# #######################################
# #  INSTALL .NET SDK 9.0
# #######################################
# DOTNET_VER=9.0.301
# DOTNET_ROOT=/opt/dotnet

# mkdir -p "$DOTNET_ROOT"
# curl -sSL "https://dotnetcli.blob.core.windows.net/dotnet/Sdk/${DOTNET_VER}/dotnet-sdk-${DOTNET_VER}-linux-x64.tar.gz" | tar -xz -C "$DOTNET_ROOT"

# # Экспортируем PATH
# cat >/etc/profile.d/dotnet.sh <<EOF
# export DOTNET_ROOT=${DOTNET_ROOT}
# export PATH=\$DOTNET_ROOT:\$PATH
# EOF
# source /etc/profile.d/dotnet.sh

# 1. Ключ Microsoft
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

# 2. Репозиторий (RHEL 9 пакеты подходят Amazon Linux 2023)
sudo tee /etc/yum.repos.d/microsoft-dotnet9.repo <<'EOF'
[microsoft-dotnet9]
name=Microsoft .NET 9 (RHEL9) – works on AL2023
baseurl=https://packages.microsoft.com/yumrepos/microsoft-rhel9.0-prod
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# 3. Обновляем метаданные
sudo dnf clean all && sudo dnf makecache

# 4. Ставим SDK 9.0 (при конфликте со старыми версиями – разрешаем замену)
sudo dnf install -y dotnet-sdk-9.0 --allowerasing


# Проверяем
dotnet --info || { echo "❌ dotnet install failed"; exit 1; }

dotnet --info
java --version
valkey-server -v
psql --version
node -v

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

postgresql-setup --initdb || true

sed -E -i "s/(host\s+(all|replication)\s+all\s+(127\.0\.0\.1\/32|\:\:1\/128)\s+)(ident|trust|md5)/\1scram-sha-256/" /var/lib/pgsql/data/pg_hba.conf
sed -i "s/^#\?password_encryption = .*/password_encryption = 'scram-sha-256'/" /var/lib/pgsql/data/postgresql.conf

if ! command -v semanage &> /dev/null; then
	yum install -y policycoreutils-python-utils
fi 

semanage permissive -a httpd_t

package_services="rabbitmq-server postgresql valkey mysqld"
rpm -q valkey &>/dev/null && package_services="${package_services//redis/valkey}" || true # https://fedoraproject.org/wiki/Changes/Replace_Redis_With_Valkey 
