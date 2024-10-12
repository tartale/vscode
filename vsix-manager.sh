#!/usr/bin/env bash
# shellcheck disable=SC1083,SC1090,SC2044,SC2086,SC2155,SC2164

set -Eeuo pipefail

THIS_SCRIPT_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})"; pwd)
source "${THIS_SCRIPT_DIR}/vsix-helpers.sh"

usage() {
  echo "
usage: ${0} download <extension> [<extension...]|installed
            install  <extension> [<extension...]|<dir>
            [-f|--force]
            [-h|--help]

download: fetches the .vsix file for the given <extensions>. If <extensions> is 'installed', then
  the .vsix file for all currently-installed extensions will be downloaded. If the extension has
  dependencies, the .vsix files for those extensions will be downloaded as well.

install: installs the given <extensions> using the VS Code CLI. If the argument is a directory,
  then each .vsix file in the directory will be installed. If an extension has any dependencies,
  those extensions will be installed first.

<extension>; the name of the extension to download and/or install. The name may optionally include
  the version number and platform; e.g. 'ms-python.python-2024.17.2024100801@$(vsixPlatform)'.
  The version number and platform default to latest@$(vsixPlatform).

Flag                            Purpose
-f|--force                      Optional; if provided, any existing .vsix file will be overwritten

Environment variable            Purpose
VSIX_DOWNLOAD_DIR               Optional; dirctory in which to store .vsix files; defaults to '${VSIX_DOWNLOAD_DIR}'
VSIX_PLATFORMS                  Optional; space-separated list of target platforms to download; defaults to '${VSIX_PLATFORMS}'
DEBUG                           Optional; set to 'true' to echo commands

" >&2

    exit 1
}

command=""
extensions=()
force="false"
while [[ $# -gt 0 ]]
do
  key="${1}"

  case ${key} in
      -h|--help)
        usage
      ;;
      download)
        command="download"
        shift # past key
      ;;
      install)
        command="install"
        shift # past key
      ;;
      -f|--force)
        force="true"
        shift # past key
      ;;
      *)      
        extensions+=("${key}")
        shift # past key
      ;;
  esac
done

if [[ -z "${command}" ]]; then
  echo "no value provided for <command>" >&2
  exit
fi

if [[ -z "${extensions[@]}" ]]; then
  echo "no values provided for <extensions>" >&2
  exit
fi

for extension in "${extensions[@]}"; do
  case ${command} in
    download)
      if [[ "${extension}" == "installed" ]]; then
        downloadInstalledExtensions "${force}"
      else
        downloadExtension "${extension}" "${force}"
      fi
    ;;
    install)
      extension="${extension:-${VSIX_DOWNLOAD_DIR}}"
      if [[ -d "${extension}" ]]; then
        vsixInstallFromDir "${extension}"
      else
        vsixInstallFromPath "${extension}"
      fi
    ;;
  esac
done
