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


#######################################
#  FFMPEG START
#######################################

########################################
# Install static ffmpeg + dummy rpm
########################################
if grep -q "Amazon Linux 2023" /etc/os-release; then
  echo "→ Installing static ffmpeg"

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  FFMPEG_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz" ;;
    aarch64) FFMPEG_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-arm64-static.tar.xz" ;;
    *) echo "Unsupported arch: $ARCH"; exit 1 ;;
  esac

  tmpdir=$(mktemp -d)
  for i in {1..3}; do
    curl -L --connect-timeout 15 --max-time 60 -o "$tmpdir/ffmpeg.tar.xz" "$FFMPEG_URL" && [ -s "$tmpdir/ffmpeg.tar.xz" ] && break
    echo "Download attempt $i failed. Retrying in 5s..."
    sleep 5
  done

  if [ ! -s "$tmpdir/ffmpeg.tar.xz" ]; then
    echo "Failed to download FFmpeg static archive after multiple attempts. Aborting."
    rm -rf "$tmpdir"
    exit 1
  fi

  tar -xJf "$tmpdir/ffmpeg.tar.xz" -C "$tmpdir"
  ffmpeg_dir=$(find "$tmpdir" -type d -name 'ffmpeg-*' | head -1)

  if [ -x "$ffmpeg_dir/ffmpeg" ] && [ -x "$ffmpeg_dir/ffprobe" ]; then
    install -m755 "$ffmpeg_dir/ffmpeg" "$ffmpeg_dir/ffprobe" /usr/local/bin/
  else
    echo "ffmpeg or ffprobe binary not found in archive. Aborting."
    rm -rf "$tmpdir"
    exit 1
  fi

  rm -rf "$tmpdir"

  echo "→ Creating dummy ffmpeg-free rpm to satisfy DocSpace"

  dnf install -y rpm-build rpmdevtools
  rpmdev-setuptree

  cp /usr/local/bin/ffmpeg  ~/rpmbuild/SOURCES/
  cp /usr/local/bin/ffprobe ~/rpmbuild/SOURCES/

  cat > ~/rpmbuild/SPECS/ffmpeg-free.spec <<'EOF'
Name:           ffmpeg-free
Version:        7.0.2
Release:        1%{?dist}
Summary:        Static FFmpeg binary provider (for DocSpace)
License:        GPLv3+
Provides:       ffmpeg-free

%description
Dummy package that satisfies DocSpace dependency on ffmpeg-free.

%prep
%build
%install
mkdir -p %{buildroot}/usr/local/bin
install -m755 %{_sourcedir}/ffmpeg  %{buildroot}/usr/local/bin/
install -m755 %{_sourcedir}/ffprobe %{buildroot}/usr/local/bin/

%files
/usr/local/bin/ffmpeg
/usr/local/bin/ffprobe

%changelog
* Fri Jun 20 2025 You <you@example.com> 7.0.2-1
- Initial dummy provider
EOF

  rpmbuild -bb ~/rpmbuild/SPECS/ffmpeg-free.spec
  dnf install -y ~/rpmbuild/RPMS/${ARCH}/ffmpeg-free-*.rpm
fi


#######################################
#  FFMPEG FINISH
#######################################

rpm --import https://openresty.org/package/pubkey.gpg
curl -o /etc/yum.repos.d/openresty.repo https://openresty.org/package/amazon/openresty.repo
sed -i "s/\$releasever/2023/g" /etc/yum.repos.d/openresty.repo

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

# java-${JAVA_VERSION}-amazon-corretto-headless

#######################################
#  SDL and JAVA START
#######################################
sudo tee /etc/yum.repos.d/alma-appstream.repo <<'EOF'
[alma-appstream]
name = AlmaLinux 9 – AppStream (SDL2, OpenJDK 21)
baseurl = https://repo.almalinux.org/almalinux/9/AppStream/x86_64/os/
enabled = 1
gpgcheck = 0
EOF

sudo dnf install -y SDL2 SDL2-devel java-21-openjdk-headless

sudo dnf config-manager --set-disabled alma-appstream
#######################################
#  SDL and JAVA FINISH
#######################################


#######################################
#  DOTNET START
#######################################
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

sudo tee /etc/yum.repos.d/microsoft-dotnet9.repo <<'EOF'
[microsoft-dotnet9]
name=Microsoft .NET 9 (RHEL9) - works on AL2023
baseurl=https://packages.microsoft.com/yumrepos/microsoft-rhel9.0-prod
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

sudo dnf clean all && sudo dnf makecache
sudo dnf install -y dotnet-sdk-9.0 --allowerasing

#######################################
#  DOTNET FINISH
#######################################


dotnet --version
java --version
valkey-server --version
psql --version
node --version
ffmpeg -version
rpm -q ffmpeg-free
dnf list installed ffmpeg-free


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
