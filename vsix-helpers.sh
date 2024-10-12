#!/usr/bin/env bash
# shellcheck disable=SC1083,SC1090,SC2044,SC2086,SC2155,SC2164

set -Eeuo pipefail

THIS_SCRIPT_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})"; pwd)

function debug() {
  [[ "${DEBUG}" == "true" ]]
}

function dryrun() {
  [[ "${DRY_RUN}" == "true" ]]
}

function vsixPlatform() {
  local path="${1:-}"
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

function getExtensionInfo() {
  local extension="${1}"
  if [[ ! "${extension}" =~ .*\..* ]]; then
    echo "expected format for extension: publisher.package[-version][@platform]" >&2
    echo "got: ${extension}" >&2
    return 1    
  fi
  local name=$(echo "${extension%-*}")
  local publisher=$(echo "${name%.*}")
  local package=$(echo "${name##*.}")

  local version="latest"
  if [[ "${extension}" =~ .*-.* ]]; then
    local info=$(echo "${extension##*-}")
    version=$(echo "${info%@*}")
  fi
  local platform=""
  if [[ "${extension}" =~ .*@(.*) ]]; then
    platform="${BASH_REMATCH[1]}"
  fi

  echo "${publisher}" "${package}" "${version}" "${platform}"
}

function downloadExtension() {
  local outputDir="${VSIX_DOWNLOAD_DIR}"
  local extension="${1}"
  local force="${2}"
  local extensionInfo=$(getExtensionInfo "${extension}")
  if [[ -z "${extensionInfo}" ]]; then
    return 1
  fi
  read -r publisher package version platform <<<${extensionInfo}
  local url="https://${publisher}.gallery.vsassets.io/_apis/public/gallery/publisher/${publisher}/extension/${package}/${version:-latest}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"
  local outputFilename="${publisher}.${package}-${version}.vsix"
  local outputPath="${outputDir}/${outputFilename}"
  if [[ -f "${outputPath}" && "${force}" != "true" ]]; then
    echo "skipping download of existing file: ${outputFilename}"
  fi
  mkdir -p "${outputDir}"
  if [[ -n "${platform}" ]]; then
    url="${url}?targetPlatform=${platform}"
    outputPath="${outputPath/.vsix/@${platform}.vsix}"
  fi
  echo "downloading: ${extension} to ${outputPath}"
  echo "  url: ${url}"
  if dryrun; then
    return
  fi
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
    downloadExtension "${extension}@${p}" "${force}"
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

DEBUG="${DEBUG:-false}"
if [[ "${DEBUG}" == "true" ]]; then
  SET_DEBUG="-x"
else
  SET_DEBUG="+x"
fi
set ${SET_DEBUG}
VSIX_DOWNLOAD_DIR="${VSIX_DOWNLOAD_DIR:-${THIS_SCRIPT_DIR}/downloads}"
VSIX_PLATFORMS="${VSIX_PLATFORMS:-$(vsixPlatform)}"
