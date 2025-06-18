#!/bin/bash
set -e

cat<<EOF

#######################################
#  INSTALL PREREQUISITES (Amazon Linux 2023)
#######################################

EOF

DIST="amzn"
REV="2023"
ELASTIC_VERSION="2.18.0"
NODE_VERSION="18"
JAVA_VERSION="21"
MYSQL_DISTR_NAME="el"
OPENRESTY_DISTR_NAME="amazon"
UPDATE_AVAILABLE_CODE=100
package_manager="yum"

${package_manager} clean all
${package_manager} -y install yum-utils

${package_manager} install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

yum remove -y mysql* mariadb* || true

curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | os=el dist=9 bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | os=el dist=9 bash

# Node.js
curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | sed '/update -y/d' | bash -

# MySQL
yum install -y https://repo.mysql.com/mysql84-community-release-el9-1.noarch.rpm || true

# OpenSearch
curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.x.repo -o /etc/yum.repos.d/opensearch-2.x.repo
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="admin!A1"

INSTALL_FLUENT_BIT=true
if [ "$INSTALL_FLUENT_BIT" == "true" ]; then
    curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.x/opensearch-dashboards-2.x.repo -o /etc/yum.repos.d/opensearch-dashboards-2.x.repo
    DASHBOARDS_VERSION="2.18.0"
fi

cat >/etc/yum.repos.d/nginx.repo <<'END'
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/amzn/2023/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
priority=9
END

rpm --import https://openresty.org/package/pubkey.gpg
curl -o /etc/yum.repos.d/openresty.repo https://openresty.org/package/amazon/openresty.repo

yum -y install \
    python3 \
    nodejs \
    dotnet-sdk-8.0 \
    opensearch-${ELASTIC_VERSION} \
    mysql-community-server \
    postgresql16 \
    postgresql16-server \
    rabbitmq-server \
    valkey \
    SDL2 \
    expect \
    java-21-amazon-corretto-headless \
    policycoreutils-python-utils \
    --enablerepo=opensearch-2.x

postgresql-setup --initdb || true
sed -E -i "s/(host\s+(all|replication)\s+all\s+(127\.0\.0\.1\/32|\:\:1\/128)\s+)(ident|trust|md5)/\1scram-sha-256/" /var/lib/pgsql/data/pg_hba.conf
sed -i "s/^#\?password_encryption = .*/password_encryption = 'scram-sha-256'/" /var/lib/pgsql/data/postgresql.conf

JAVA_PATH=$(dirname $(readlink -f /usr/bin/java))
alternatives --install /usr/bin/java java "$JAVA_PATH/java" 100
alternatives --set java "$JAVA_PATH/java"

if [ "$INSTALL_FLUENT_BIT" == "true" ]; then 
    curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | bash
    yum -y install opensearch-dashboards-"$DASHBOARDS_VERSION" --enablerepo=opensearch-dashboards-2.x
fi

semanage permissive -a httpd_t

echo "✅ Prerequisites installation completed for Amazon Linux 2023."
