#!/bin/bash

set -e

cat<<EOF

#######################################
#  INSTALL PREREQUISITES
#######################################


EOF

# ---------- AL2023 specifics ----------
DIST="amazon"                     # дистрибутив
REV="$(rpm -E %{rhel})"           # вернёт 9 на AL23
package_manager="dnf"             # yum → dnf на AL23 :contentReference[oaicite:0]{index=0}
MYSQL_DISTR_NAME="el"             # репо MySQL → el9
OPENRESTY_DISTR_NAME="amazon"     # путь к openresty repo для AL23
# --------------------------------------

# clean yum cache
${package_manager} clean all

$package_manager -y install yum-utils jq policycoreutils-python-utils

{ yum check-update postgresql; PSQLExitCode=$?; } || true #Checking for postgresql update
{ yum check-update "$DIST"*-release; exitCode=$?; } || true #Checking for distribution update
UPDATE_AVAILABLE_CODE=100
if [[ $exitCode -eq $UPDATE_AVAILABLE_CODE ]]; then
    res_unsupported_version
    echo $RES_UNSUPPORTED_VERSION
    echo $RES_SELECT_INSTALLATION
    echo $RES_ERROR_REMINDER
    echo $RES_QUESTIONS
    read_unsupported_installation
fi
#add rabbitmq repo
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | os=el dist=9 bash
if rpm -q rabbitmq-server; then
    if [ "$(yum list installed rabbitmq-server | awk 'NR>1 {gsub(/^@/, "", $NF); print $NF}')" != "$(repoquery rabbitmq-server --qf='%{ui_from_repo}')" ]; then
        res_rabbitmq_update
        echo $RES_RABBITMQ_VERSION
        echo $RES_RABBITMQ_REMINDER
        echo $RES_RABBITMQ_INSTALLATION
        read_rabbitmq_update
    fi
fi
#add erlang repo
#or download the RPM package for the latest erlang release
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

if ! rpm -q mysql-community-server; then
	MYSQL_FIRST_TIME_INSTALL="true"
fi

#add opensearch repo
curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.x.repo -o /etc/yum.repos.d/opensearch-2.x.repo
ELASTIC_VERSION="2.18.0"
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="$(echo "${package_sysname}!A1")"

#add opensearch dashboards repo
if [ ${INSTALL_FLUENT_BIT} == "true" ]; then
	curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.x/opensearch-dashboards-2.x.repo -o /etc/yum.repos.d/opensearch-dashboards-2.x.repo
	DASHBOARDS_VERSION="2.18.0"
fi

cat > /etc/yum.repos.d/nginx.repo <<END
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/$REV/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
END

rpm --import https://openresty.org/package/pubkey.gpg
# Для Amazon используем единый openresty.repo
if [ "$DIST" = "amazon" ]; then
  OPENRESTY_REPO_FILE="openresty.repo"
else
  OPENRESTY_REPO_FILE=$( [[ "$REV" -ge 9 && "$DIST" != "fedora" ]] && echo "openresty2.repo" || echo "openresty.repo" )
fi
curl -o /etc/yum.repos.d/openresty.repo \
  "https://openresty.org/package/${OPENRESTY_DISTR_NAME}/${OPENRESTY_REPO_FILE}"


JAVA_VERSION=21
${package_manager} -y install \
			python3 \
			nodejs ${NODEJS_OPTION} \
			dotnet-sdk-9.0 \
			opensearch-${ELASTIC_VERSION} \
			mysql-community-server \
			postgresql${PSQL_VERSION} \
			postgresql${PSQL_VERSION}-server \
			rabbitmq-server \
			redis \
			SDL2 \
			expect \
			java-${JAVA_VERSION}-openjdk-headless \
			--enablerepo=opensearch-2.x

if [[ ${PSQLExitCode} -eq ${UPDATE_AVAILABLE_CODE} ]]; then
    yum -y install postgresql${PSQL_INSTALLED_VERSION}-upgrade
    postgresql-setup --upgrade || true
fi
postgresql-setup initdb	|| true

sed -E -i "s/(host\s+(all|replication)\s+all\s+(127\.0\.0\.1\/32|\:\:1\/128)\s+)(ident|trust|md5)/\1scram-sha-256/" /var/lib/pgsql/data/pg_hba.conf
sed -i "s/^#\?password_encryption = .*/password_encryption = 'scram-sha-256'/" /var/lib/pgsql/data/postgresql.conf

semanage permissive -a httpd_t

if [ -e /etc/valkey.conf ]; then
    sed -i "s/bind .*/bind 127.0.0.1/g" /etc/valkey.conf
    sed -r "/^save\s[0-9]+/d" -i /etc/valkey.conf
fi

package_services="rabbitmq-server postgresql redis mysqld"
rpm -q valkey &>/dev/null && package_services="${package_services//redis/valkey}"

