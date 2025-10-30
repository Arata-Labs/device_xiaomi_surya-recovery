#!/bin/bash
set -euo pipefail

# =========================
# Usage & Args Validation
# =========================
usage() {
  cat <<'USAGE'
Usage:
  magisk_prebuilt.sh <OUT_DIRECTORY> <Version...>

Examples:
  magisk_prebuilt.sh /path/to/dest Original
  magisk_prebuilt.sh /path/to/dest Original Alpha
  magisk_prebuilt.sh /path/to/dest Delta
Allowed versions (case-insensitive): Original, Alpha, Delta
USAGE
}

if [[ $# -lt 2 ]]; then
  echo "[ERR] Need OUT_DIRECTORY and at least one Version." >&2
  usage
  exit 1
fi

OUT_DIRECTORY="$1"; shift
REQUESTED_VERSIONS=("$@")

# Verifying version
normalize_ver() {
  local v="${1,,}"  # lower
  case "$v" in
    original) echo "Original" ;;
    alpha)    echo "Alpha" ;;
    delta)    echo "Delta" ;;
    *)        echo "" ;;
  esac
}

# Validate
SELECTED=()
for v in "${REQUESTED_VERSIONS[@]}"; do
  nv="$(normalize_ver "$v")"
  if [[ -z "$nv" ]]; then
    echo "[ERR] Unknown version: $v (allowed: Original, Alpha, Delta)" >&2
    usage
    exit 1
  fi
  if [[ ! " ${SELECTED[*]} " =~ " ${nv} " ]]; then
    SELECTED+=("$nv")
  fi
done

# =========================
# Paths & Tools
# =========================
MAGISK_DIR="${OUT_DIRECTORY}/Magisk"
MAGISKVERIFY_SHA256="verify.sha256sum"

# Official
MAGISK_ZIP="Magisk.apk"
MAGISK_VER="MagiskVer"
MAGISK_ZIP_PATH="${MAGISK_DIR}/${MAGISK_ZIP}"
MAGISK_VER_PATH="${MAGISK_DIR}/${MAGISK_VER}"

# Alpha
MAGISK_ALPHA_ZIP="MagiskAlpha.apk"
MAGISK_ALPHA_VER="MagiskAlphaVer"
MAGISK_ALPHA_ZIP_PATH="${MAGISK_DIR}/${MAGISK_ALPHA_ZIP}"
MAGISK_ALPHA_VER_PATH="${MAGISK_DIR}/${MAGISK_ALPHA_VER}"

# Delta
MAGISK_DELTA_ZIP="MagiskDelta.apk"
MAGISK_DELTA_VER="MagiskDeltaVer"
MAGISK_DELTA_ZIP_PATH="${MAGISK_DIR}/${MAGISK_DELTA_ZIP}"
MAGISK_DELTA_VER_PATH="${MAGISK_DIR}/${MAGISK_DELTA_VER}"

MAGISK_URL="https://raw.githubusercontent.com/Arata-Labs/twrp_prebuilt/master/Magisk"

CURL="curl"
[[ -f "/sbin/curl"     ]] && CURL="/sbin/curl"
[[ -f "/bin/curl"      ]] && CURL="/bin/curl"
[[ -f "/usr/bin/curl"  ]] && CURL="/usr/bin/curl"

mkdir -p "${MAGISK_DIR}"

# =========================
# Logging Helpers
# =========================
logYR(){ echo -e "\e[33m $1\e[m\e[91m$2\e[m"; }
logYG(){ echo -e "\e[33m $1\e[m\e[92m$2\e[m"; }

# =========================
# Curl Helpers
# =========================
curl_dl() {
  # $1=url $2=out
  "${CURL}" -sSL --fail "$1" -H 'Cache-Control: no-cache' \
    --connect-timeout 3 -m 35 --retry 2 -o "$2"
}

curl_read() {
  # $1=url -> stdout
  "${CURL}" -sSL --fail "$1" -H 'Cache-Control: no-cache' \
    --connect-timeout 3 -m 5 --retry 3
}

# =========================
# Download per Versi
# =========================
download_original() {
  [[ -f "${MAGISK_ZIP_PATH}" ]] || curl_dl "${MAGISK_URL}/${MAGISK_ZIP}" "${MAGISK_ZIP_PATH}"
  [[ -f "${MAGISK_VER_PATH}" ]] || curl_dl "${MAGISK_URL}/${MAGISK_VER}" "${MAGISK_VER_PATH}"
}

download_alpha() {
  [[ -f "${MAGISK_ALPHA_ZIP_PATH}" ]] || curl_dl "${MAGISK_URL}/${MAGISK_ALPHA_ZIP}" "${MAGISK_ALPHA_ZIP_PATH}"
  [[ -f "${MAGISK_ALPHA_VER_PATH}" ]] || curl_dl "${MAGISK_URL}/${MAGISK_ALPHA_VER}" "${MAGISK_ALPHA_VER_PATH}"
}

download_delta() {
  [[ -f "${MAGISK_DELTA_ZIP_PATH}" ]] || curl_dl "${MAGISK_URL}/${MAGISK_DELTA_ZIP}" "${MAGISK_DELTA_ZIP_PATH}"
  [[ -f "${MAGISK_DELTA_VER_PATH}" ]] || curl_dl "${MAGISK_URL}/${MAGISK_DELTA_VER}" "${MAGISK_DELTA_VER_PATH}"
}

download_magisk() {
  for v in "${SELECTED[@]}"; do
    case "$v" in
      Original) download_original ;;
      Alpha)    download_alpha    ;;
      Delta)    download_delta    ;;
    esac
  done
}

# =========================
# Verify Helpers
# =========================
do_verify() {
  local verify_item="$1" target="$2"
  local verify_sha256 verify_file target_sha
  verify_sha256="$(echo "${verify_item}" | awk -F '-' '{print $1}')"
  verify_file="$(echo "${verify_item}" | awk -F '-' '{print $2}')"

  local fail=0
  if [[ -f "$target" && ${#verify_sha256} -ge 64 && ${#verify_file} -gt 1 ]]; then
    target_sha="$(sha256sum "$target" | awk '{print $1}')"
    if [[ "$verify_sha256" == "$target_sha" ]]; then
      logYG "${verify_file}: " "Verification succeeded !"
    else
      # retry sekali
      curl_dl "${MAGISK_URL}/${verify_file}" "$target"
      target_sha="$(sha256sum "$target" | awk '{print $1}')"
      if [[ "$verify_sha256" == "$target_sha" ]]; then
        logYG "${verify_file}: " "Verification succeeded !"
      else
        rm -f "$target" >/dev/null 2>&1 || true
        logYR "${verify_file}: " "Verification failed !"
        fail=1
      fi
    fi
  else
    logYR "magisk_prebuilt: " "Download file failed or bad sha line!"
    fail=1
  fi
  return $fail
}

verify() {
  local vf
  if ! vf="$(curl_read "${MAGISK_URL}/${MAGISKVERIFY_SHA256}")"; then
    logYR "magisk_prebuilt: " "Read sha256 file failed !"
    exit 1
  fi
  vf="$(echo "${vf}" | sed 's/  /-/g')"
  [[ ${#vf} -lt 64 ]] && logYR "magisk_prebuilt: " "Invalid sha256 manifest!" && exit 1

  local any_fail=0

  for v in "${SELECTED[@]}"; do
    case "$v" in
      Original)
        do_verify "$(echo "${vf}" | grep -F "${MAGISK_VER}")" "${MAGISK_VER_PATH}" || any_fail=1
        do_verify "$(echo "${vf}" | grep -F "${MAGISK_ZIP}")" "${MAGISK_ZIP_PATH}" || any_fail=1
        ;;
      Alpha)
        do_verify "$(echo "${vf}" | grep -F "${MAGISK_ALPHA_VER}")" "${MAGISK_ALPHA_VER_PATH}" || any_fail=1
        do_verify "$(echo "${vf}" | grep -F "${MAGISK_ALPHA_ZIP}")" "${MAGISK_ALPHA_ZIP_PATH}" || any_fail=1
        ;;
      Delta)
        do_verify "$(echo "${vf}" | grep -F "${MAGISK_DELTA_VER}")" "${MAGISK_DELTA_VER_PATH}" || any_fail=1
        do_verify "$(echo "${vf}" | grep -F "${MAGISK_DELTA_ZIP}")" "${MAGISK_DELTA_ZIP_PATH}" || any_fail=1
        ;;
    esac
  done

  if [[ $any_fail -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}

# =========================
# Run
# =========================
download_magisk
verify