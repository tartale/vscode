#!/usr/bin/env bash
# shellcheck disable=SC1083,SC1090,SC2044,SC2086,SC2155,SC2164

set -Eeuo pipefail

usage() {
  echo "usage: ${0} [-d|--download] [<extension-name>]
                    [-i|--install]  <extension-name>|<dir>
                    [-h|--help]" >&2
  echo >&2
  echo "optional environment variable: VSIX_DOWNLOAD_DIR; dirctory to store vsix files" >&2
  echo "optional environment variable: VSIX_PLATFORMS; space-separated list of platforms to download" >&2
  echo "optional environment variable: DEBUG; set to 'true' to echo commands" >&2
  echo >&2
  echo "download: downloads the vsix file for the given extension name if supplied; or the vsix files" >&2
  echo "  for all the extensions that are already installed." >&2
  echo >&2
  echo "example: " >&2
  echo "> $0 -r internal-artifacts -i controlplane-main" >&2
  echo "" >&2
  exit 1
}

THIS_SCRIPT_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})"; pwd)
VSIX_DOWNLOAD_DIR="${VSIX_DOWNLOAD_DIR:-${THIS_SCRIPT_DIR}/downloads}}"
VSIX_PLATFORMS="${VSIX_PLATFORMS:-}"
DEBUG="${DEBUG:-false}"
if [[ "${DEBUG}" == "true" ]]; then
  SET_DEBUG="-x"
else
  SET_DEBUG="+x"
fi
set ${SET_DEBUG}

function debug() {
  [[ "${DEBUG}" == "true" ]]
}

function dryrun() {
  [[ "${DRY_RUN}" == "true" ]]
}

function vsixPlatform() {
  local path="${1}"
  local arch="$(uname -s)-$(uname -m)"
  arch=$(echo "${arch}" | tr '[:upper:]' '[:lower:]')
  arch="${arch/x86_64/x64}"
  if [[ -z "${path}" ]]; then
    echo "${arch}"
    return 0
  fi

  case "${path}" in
    *darwin*|*Darwin*)
      arch="darwin"
      ;;
    *linux*|*Linux*)
      arch="linux"
      ;;
  esac
  case "${path}" in
    *arm64*)
      arch="${arch}-arm64"
      ;;
    *x64*)
      arch="${arch}-x64"
      ;;
  esac
  echo "${arch}"
}

function vsixPlatformMatches() {
  local path="${1}"
  local thisArch=$(vsixPlatform)
  local pathArch=$(vsixPlatform "${path}")
  [[ "${thisArch}" == "${pathArch}" ]]
}

function downloadExtension() {
  local outputDir="${VSIX_DOWNLOAD_DIR}"
  local extension="${1}"
  local force="${2}"
  local publisher=$(cut -d '.' -f 1 <<< "${extension}")
  local package=$(cut -d '.' -f 2- <<< "${extension}" | cut -d '@' -f 1)
  local version=$(cut -d '@' -f 2- <<< "${extension}")
  local platform="${3}"
  local url="https://${publisher}.gallery.vsassets.io/_apis/public/gallery/publisher/${publisher}/extension/${package}/${version:-latest}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"
  local outputFilename="${publisher}.${package}-${version}.vsix"
  local outputPath="${outputDir}/${outputFilename}"
  if [[ -f "${outputPath}" && "${force}" != "TRUE" ]]; then
    echo "skipping download of existing file: ${outputFilename}"
  fi
  mkdir -p "${outputDir}"
  if [[ -n "${platform}" ]]; then
    url="${url}?targetPlatform=${platform}"
    outputPath="${outputPath/.vsix/@${platform}.vsix}"
  fi
  if debug; then
    echo "extension: ${extension}; url: ${url}" >&2
  fi
  echo "downloading: ${extension} to ${outputPath}"
  local statusCode=$(curl -s --write-out '%{http_code}' --output "${outputPath}" "${url}")
  if [[ "${statusCode}" != "200" ]]; then
    echo "error downloading ${extension}; status code: ${statusCode}" >&2
    return
  fi
  if [[ -n "${platform}" ]]; then
    return
  fi
  local manifest="$(unzip -p ${outputPath} extension.vsixmanifest)"
  local manifestTargetPlatform="$(xq -r '.PackageManifest.Metadata.Identity.["@TargetPlatform"]' <<< ${manifest} )"
  if [[ "${manifestTargetPlatform}" == "null" ]]; then
    return
  fi
  local newOutputPath="${outputPath/.vsix/@${manifestTargetPlatform}.vsix}"
  echo "renaming platform-specific extension to ${newOutputPath}"
  mv "${outputPath}" "${newOutputPath}"
  read -r -a platforms <<< "${VSIX_PLATFORMS}"
  for p in "${platforms[@]}"; do
    downloadExtension "${extension}" "${force}" "${p}"
  done
}

function downloadInstalledExtensions() {
  local force="${1}"
  IFS=$'\n' read -r -d '' -a extensions < <( code --list-extensions --show-versions )
  
  for e in "${extensions[@]}"; do
    downloadExtension "${e}" "${force}"
  done
}

function vsixInstallFromPath() {
  local path="${1}"
  if dryrun; then
    echo "code --verbose --install-extension ${path}" >&2
    return
  fi
  (trap 'echo "aborting install"; exit' SIGINT; code --verbose --install-extension "${path}")
}

function vsixInstallFromDir() {
  local dir="${1:-$(pwd)}"

  for path in $(find "${dir}" -name '*.vsix'); do
    if [[ "${path}" =~ .*pack.* ]]; then
      echo "skipping install of pack extension: $(basename ${path})" >&2
      continue
    fi
    if vsixPlatformMatches "${path}" ; then
      vsixInstallFromPath "${path}"
    fi
  done
}

command=""
extension=""
force="FALSE"
while [[ $# -gt 0 ]]
do
  key="${1}"

  case ${key} in
      -h|--help)
        usage
      ;;
      -d|--download)
        command="download"
        extension="${2}"
        shift # past key
        shift # past value
      ;;
      -i|--install)
        command="install"
        extension="${2}"
        shift # past key
        shift # past value
      ;;
      -f|--force)
        force="TRUE"
        shift # past key
      ;;
      *)    # unknown option
        usage
      ;;
  esac
done

case ${command} in
  download)
    if [[ -n "${extension}" || "${extension}" == "installed" ]]; then
      downloadInstalledExtensions "${force}"
    else
      downloadExtension "${extension}" "${force}"
    fi
  ;;
  install)
    extension="${extension:-${VSCODE_EXTENSION_DOWNLOAD_DIR}}"
    if [[ -d "${extension}" ]]; then
      vsixInstallFromDir "${extension}"
    else
      vsixInstallFromPath "${extension}"
    fi
  ;;

esac
