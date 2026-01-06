#!/bin/bash

set -e

while [ "$1" != "" ]; do
	case $1 in
    -ds  | --download-scripts  ) [ -n "$2" ] && DOWNLOAD_SCRIPTS="$2"      && shift ;;
    -arg | --arguments         ) [ -n "$2" ] && ARGUMENTS="$2"             && shift ;;
    -tr  | --test-repo         ) [ -n "$2" ] && TEST_REPO_ENABLE="$2"      && shift ;;
  esac
  shift
done

export TERM=xterm-256color

# --- minimal debug bundle (prints only on failure) ---
on_fail_debug() {
  rc=$?
  [ "$rc" -eq 0 ] && exit 0

  echo
  echo "#########################################"
  echo "# DEBUG (script failed), rc=$rc"
  echo "#########################################"
  echo

  echo "### /etc/os-release"
  cat /etc/os-release || true
  echo
  echo "### uname -a"
  uname -a || true
  echo
  echo "### SELinux"
  (command -v getenforce >/dev/null 2>&1 && getenforce) || echo "n/a"
  echo
  echo "### systemd failed units"
  systemctl --failed --no-pager || true

  if command -v dnf >/dev/null 2>&1; then
    echo
    echo "### dnf repolist --enabled"
    dnf repolist --enabled || true
    echo
    echo "### dnf module list redis (enabled)"
    dnf -y module list redis --enabled || true
  fi

  if command -v rpm >/dev/null 2>&1; then
    echo
    echo "### packages: redis/valkey"
    rpm -q redis valkey || true
  fi

  echo
  echo "### redis service / port"
  systemctl status redis --no-pager -l || true
  ss -lntp | egrep '(:6379|:6380)' || true

  if command -v redis-cli >/dev/null 2>&1; then
    echo
    echo "### redis-cli PING"
    redis-cli -h 127.0.0.1 -p 6379 PING || true
    echo
    echo "### redis-cli HELLO 3 (should work for Redis >= 6)"
    redis-cli -h 127.0.0.1 -p 6379 HELLO 3 || true
    echo
    echo "### redis-cli INFO server"
    redis-cli -h 127.0.0.1 -p 6379 INFO server | egrep 'redis_version|tcp_port' || true
  fi

  echo
  echo "### /etc/redis.conf key lines"
  [ -f /etc/redis.conf ] && egrep -n '^(bind|port|protected-mode|requirepass|aclfile|user )' /etc/redis.conf || true
  [ -f /etc/redis.conf.rpmnew ] && echo "NOTE: /etc/redis.conf.rpmnew exists"

  echo
  echo "### identity services status/logs"
  for s in docspace-identity-api docspace-identity-authorization docspace-identity-registration; do
    echo
    echo "---- systemctl status $s ----"
    systemctl status "$s" --no-pager -l || true
    echo
    echo "---- journalctl -u $s -n 200 ----"
    journalctl -u "$s" -n 200 --no-pager || true
  done

  echo
  echo "### DocSpace logs (tail 200): /var/log/onlyoffice/docspace/identity-*.log"
  if [ -d /var/log/onlyoffice/docspace ]; then
    for f in /var/log/onlyoffice/docspace/identity-*.log; do
      [ -f "$f" ] || continue
      echo
      echo "---- $f ----"
      tail -n 200 "$f" || true
    done
  fi

  echo
  echo "### Java runtime (CLI)"
  command -v java >/dev/null 2>&1 && {
    echo "which java: $(command -v java)"
    readlink -f "$(command -v java)" || true
    java -version 2>&1 || true
  } || echo "java: not found"

  if command -v alternatives >/dev/null 2>&1; then
    echo
    echo "### alternatives --display java"
    alternatives --display java || true
  fi

  echo
  echo "### Identity unit files (systemd cat)"
  for s in docspace-identity-api docspace-identity-authorization; do
    echo
    echo "---- systemctl cat $s ----"
    systemctl cat "$s" --no-pager || true

    echo
    echo "---- parsed ExecStart / Environment ($s) ----"
    systemctl show "$s" -p ExecStart -p Environment -p EnvironmentFiles --no-pager || true
  done

  echo
  echo "### Check jar classfile version (first main class found)"
  for jar in \
    /var/www/docspace/services/ASC.Identity.Registration/app.jar \
    /var/www/docspace/services/ASC.Identity.Authorization/app.jar \
    /var/www/docspace/services/ASC.Identity.Api/app.jar \
    /var/www/docspace/services/ASC.Identity.Registration/app.jar; do

    [ -f "$jar" ] || continue
    echo
    echo "---- $jar ----"
    ls -la "$jar" || true

    if command -v jar >/dev/null 2>&1; then
      main_class="$(jar tf "$jar" 2>/dev/null | grep -E '\.class$' | head -n 1 | sed 's|/|.|g; s|\.class$||')"
      echo "sample class: ${main_class:-n/a}"
      if [ -n "$main_class" ] && command -v javap >/dev/null 2>&1; then
        echo "javap -verbose (major version):"
        javap -verbose -classpath "$jar" "$main_class" 2>/dev/null | egrep -m1 'major version' || true
      else
        echo "javap not available or no class found"
      fi
    else
      echo "jar tool not available"
    fi
  done

  exit "$rc"
}
trap on_fail_debug EXIT
# --- end debug bundle ---

get_colors() {
    export LINE_SEPARATOR="-----------------------------------------"
    export COLOR_BLUE=$'\e[34m' COLOR_GREEN=$'\e[32m' COLOR_RED=$'\e[31m' COLOR_RESET=$'\e[0m' COLOR_YELLOW=$'\e[33m'
}

check_hw() {
    echo "${COLOR_RED} $(free -h) ${COLOR_RESET}"
    echo "${COLOR_RED} $(nproc) ${COLOR_RESET}"
}

add-repo-deb() {
  mkdir -p "$HOME"/.gnupg && chmod 700 "$HOME"/.gnupg
  echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://nexus.onlyoffice.com/repository/4testing-debian stable main" | \
  sudo tee /etc/apt/sources.list.d/onlyoffice4testing.list
  curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | \
  gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/onlyoffice.gpg --import
  chmod 644 /usr/share/keyrings/onlyoffice.gpg
}

add-repo-rpm() {
  cat > /etc/yum.repos.d/onlyoffice4testing.repo <<END
[onlyoffice4testing]
name=onlyoffice4testing repo
baseurl=https://nexus.onlyoffice.com/repository/centos-testing/4testing/main/noarch
gpgcheck=1
enabled=1
gpgkey=https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE
END
}

prepare_vm() {
  # Ensure curl and gpg are installed
  if ! command -v curl >/dev/null 2>&1; then
    (command -v apt-get >/dev/null 2>&1 && apt-get update -y && apt-get install -y curl) || (command -v dnf >/dev/null 2>&1 && dnf install -y curl)
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    (command -v apt-get >/dev/null 2>&1 && apt-get update -y && apt-get install -y gnupg) || (command -v dnf >/dev/null 2>&1 && dnf install -y gnupg2)
  fi

  if [ -f /etc/os-release ]; then
    source /etc/os-release
case $ID in
  ubuntu|debian)
      [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-deb
      ;;

  centos|fedora|rhel)
      [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-rpm

        if [ "$ID" = "rhel" ] && [ "${VERSION_ID%%.*}" = "8" ]; then
          cat <<'EOF' | sudo tee /etc/yum.repos.d/centos-stream-8.repo
[centos8s-baseos]
name=CentOS Stream 8 - BaseOS (vault)
baseurl=https://dl.rockylinux.org/vault/centos/8-stream/BaseOS/x86_64/os/
enabled=1
gpgcheck=0

[centos8s-appstream]
name=CentOS Stream 8 - AppStream (vault)
baseurl=https://dl.rockylinux.org/vault/centos/8-stream/AppStream/x86_64/os/
enabled=1
gpgcheck=0

[centos8s-powertools]
name=CentOS Stream 8 - PowerTools (vault)
baseurl=https://dl.rockylinux.org/vault/centos/8-stream/PowerTools/x86_64/os/
enabled=1
gpgcheck=0

[centos8s-extras]
name=CentOS Stream 8 - Extras (vault)
baseurl=https://dl.rockylinux.org/vault/centos/8-stream/extras/x86_64/os/
enabled=1
gpgcheck=0
EOF
      fi

      # --- ADD THIS BLOCK: RHEL 8 dotnet-sdk-10.0 provider repo (CI only) ---
      if [ "$ID" = "rhel" ] && [ "${VERSION_ID%%.*}" = "8" ]; then
          cat <<'EOF' | sudo tee /etc/yum.repos.d/ol8-appstream-dotnet.repo
[ol8_appstream_dotnet]
name=Oracle Linux 8 - AppStream (dotnet)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL8/appstream/x86_64/
enabled=0
gpgcheck=0
EOF
          sudo dnf -y install dotnet-sdk-10.0 --enablerepo=ol8_appstream_dotnet
      fi
      # --- END BLOCK ---

      if [ "$ID" = "rhel" ] && [ "${VERSION_ID%%.*}" = "9" ]; then
          cat <<'EOF' | sudo tee /etc/yum.repos.d/centos-stream-9.repo
[centos9s-baseos]
name=CentOS Stream 9 - BaseOS
baseurl=http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/
enabled=1
gpgcheck=0

[centos9s-appstream]
name=CentOS Stream 9 - AppStream
baseurl=http://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/
enabled=1
gpgcheck=0
EOF
      fi
      ;;

  *)
      echo "${COLOR_RED}Failed to determine Linux dist${COLOR_RESET}"; exit 1
      ;;
esac

    if [[ "$ID" == "debian" ]]; then
      if dpkg -s postfix &>/dev/null; then
        apt-get remove -y postfix && echo "${COLOR_GREEN}[OK] PREPARE_VM: Postfix was removed${COLOR_RESET}"
      fi
    fi
  else
      echo "${COLOR_RED}File /etc/os-release doesn't exist${COLOR_RESET}"; exit 1
  fi

  # Clean up home folder
  rm -rf /home/vagrant/*
  [ -d /tmp/docspace ] && mv /tmp/docspace/* /home/vagrant

  echo '127.0.0.1 host4test' | sudo tee -a /etc/hosts
  echo "${COLOR_GREEN}[OK] PREPARE_VM: Hostname was setting up${COLOR_RESET}"
}

install_docspace() {
  [[ "${DOWNLOAD_SCRIPTS}" == 'true' ]] && curl -fsSLO https://download.onlyoffice.com/docspace/docspace-install.sh || sed 's/set -e/set -xe/' -i *.sh
  bash docspace-install.sh package ${ARGUMENTS} -log false || { echo "Exit code non-zero. Exit with 1."; exit 1; }
  echo "Exit code 0. Continue..."
}

healthcheck_systemd_services() {
  for service in "${SERVICES_SYSTEMD[@]}"; do
    [[ "$service" == *migration* ]] && continue;
    if systemctl is-active --quiet "${service}"; then
      echo "${COLOR_GREEN}[OK] Service ${service} is running${COLOR_RESET}"
    else
      echo "${COLOR_RED}[FAILED] Service ${service} is not running${COLOR_RESET}"
      echo "::error::Service ${service} is not running"
      SYSTEMD_SVC_FAILED="true"
    fi
  done
  if [ -n "${SYSTEMD_SVC_FAILED}" ]; then
    exit 1
  fi
}

services_logs() {
  mapfile -t SERVICES_SYSTEMD < <(awk '/SERVICE_NAME=\(/{flag=1; next} /\)/{flag=0} flag' "build.sh" | sed -E 's/^[[:space:]]*|[[:space:]]*$//g; s/^/docspace-/; s/$/.service/')
  SERVICES_SYSTEMD+=("ds-converter.service" "ds-docservice.service" "ds-metrics.service")

  for service in "${SERVICES_SYSTEMD[@]}"; do
    echo $LINE_SEPARATOR && echo "${COLOR_GREEN}Check logs for systemd service: $service${COLOR_RESET}" && echo $LINE_SEPARATOR
    journalctl -u "$service" -n 30 || true
  done

  local DOCSPACE_LOGS_DIR="/var/log/onlyoffice/docspace"
  local DOCUMENTSERVER_LOGS_DIR="/var/log/onlyoffice/documentserver"

  for LOGS_DIR in "${DOCSPACE_LOGS_DIR}" "${DOCUMENTSERVER_LOGS_DIR}"; do
    echo $LINE_SEPARATOR && echo "${COLOR_YELLOW}Check logs for $(basename "${LOGS_DIR}"| tr '[:lower:]' '[:upper:]') ${COLOR_RESET}" && echo $LINE_SEPARATOR

    find "${LOGS_DIR}" -type f -name "*.log" ! -name "*sql*" ! -name "*nginx*" | while read -r FILE; do
      echo $LINE_SEPARATOR && echo "${COLOR_GREEN}Logs from file: ${FILE}${COLOR_RESET}" && echo $LINE_SEPARATOR
      tail -30 "${FILE}" || true
    done
  done
}

main() {
  get_colors
  prepare_vm
  check_hw
  install_docspace
  sleep 180
  services_logs
  healthcheck_systemd_services
}

main
