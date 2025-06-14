#!/usr/bin/env bash
# Usage: $0 [PRODUCT] [SPEC_CHANGELOG] [MAINTAINER]
PRODUCT=${1:-"docspace"}
SPEC_CHANGELOG=${2:-"../rpm/SPECS/changelog.spec"}
MAINTAINER=${3:-"%{packager}"}

TMP_CHANGELOG=$(mktemp)
trap 'rm -f "$TMP_CHANGELOG $TMP_FILE $NEW_SPEC"' EXIT
curl -sL "https://raw.githubusercontent.com/ONLYOFFICE/${PRODUCT}/refs/heads/master/CHANGELOG.md" > "${TMP_CHANGELOG}"

touch "${SPEC_CHANGELOG}"
declare -A EXISTING_VERSIONS=()
while IFS= read -r LINE; do
  [[ ${LINE} =~ -[[:space:]]([0-9]+\.[0-9]+\.[0-9]+)$ ]] && EXISTING_VERSIONS["${BASH_REMATCH[1]}"]=1
done < "${SPEC_CHANGELOG}"

TMP_FILE=$(mktemp)
for VERSION in $(awk '/^## /{print $2}' "${TMP_CHANGELOG}"); do
  [[ ${EXISTING_VERSIONS[${VERSION}]:-} ]] && continue
  printf '* %s %s - %s\n' "$(date +"%a %b %d %Y")" "${MAINTAINER}" "${VERSION}" >> "${TMP_FILE}"
  sed -n "/^## ${VERSION}/,/^## /{/^\* /{s/^\* /  - /;p}}" "${TMP_CHANGELOG}" >> "${TMP_FILE}"
  printf '\n' >> "${TMP_FILE}"
  echo "Added version ${VERSION} in rpm changelog"
done

if [[ -s "${TMP_FILE}" ]]; then
  TMP_SPEC_FILE=$(mktemp)
  {
    printf '%%changelog\n'
    cat "${TMP_FILE}"
    grep -v '^%changelog$' "${SPEC_CHANGELOG}"
  } > "${TMP_SPEC_FILE}"
  mv "${TMP_SPEC_FILE}" "${SPEC_CHANGELOG}"
fi

rm -f "${TMP_FILE}"
