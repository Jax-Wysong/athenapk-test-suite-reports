#!/usr/bin/env bash

## How to update reports
# ./update_reports.sh \
#   /path/to/new_2D_report.zip \
#   /path/to/new_3D_report.zip
# then commit and push
# git add -A
# git commit -m "Update 2D and 3D test reports"
# git push

set -euo pipefail

usage() {
  echo "Usage: $0 PATH_TO_2D_REPORT.zip PATH_TO_3D_REPORT.zip" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

for command_name in cp find git mktemp mv realpath rsync unzip; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Error: required command '${command_name}' was not found." >&2
    exit 1
  fi
done

for zip_path in "$1" "$2"; do
  if [[ ! -f "${zip_path}" ]]; then
    echo "Error: report archive does not exist: ${zip_path}" >&2
    exit 1
  fi
done

report_2d_zip=$(realpath "$1")
report_3d_zip=$(realpath "$2")
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(git -C "${script_dir}" rev-parse --show-toplevel)

if [[ "${script_dir}" != "${repo_root}" ]]; then
  echo "Error: update_reports.sh must remain at the report repository root." >&2
  exit 1
fi

if [[ -n $(git -C "${repo_root}" status --porcelain) ]]; then
  echo "Error: the report repository has uncommitted changes." >&2
  echo "Commit or discard them before replacing the reports." >&2
  git -C "${repo_root}" status --short >&2
  exit 1
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/athenapk-report-update.XXXXXX")
trap 'rm -rf -- "${temporary_root}"' EXIT

prepare_report() {
  local dimension=$1
  local archive=$2
  local unpack_dir="${temporary_root}/${dimension}-unpacked"
  local staged_site="${temporary_root}/${dimension}-site"
  local source_dir
  local -a report_files

  mkdir -p "${unpack_dir}" "${staged_site}"
  unzip -q "${archive}" -d "${unpack_dir}"

  mapfile -d '' report_files < <(
    find "${unpack_dir}" -type f -name report.html -print0
  )

  if [[ ${#report_files[@]} -ne 1 ]]; then
    echo "Error: expected exactly one report.html in ${archive}; found ${#report_files[@]}." >&2
    exit 1
  fi

  source_dir=$(dirname -- "${report_files[0]}")
  if [[ ! -d "${source_dir}/data" ]]; then
    echo "Error: ${archive} does not contain a data directory next to report.html." >&2
    exit 1
  fi

  cp -a "${source_dir}/." "${staged_site}/"
  mv "${staged_site}/report.html" "${staged_site}/index.html"

  if [[ ! -s "${staged_site}/index.html" ]]; then
    echo "Error: staged ${dimension} index.html is empty." >&2
    exit 1
  fi
}

# Validate both archives completely before replacing either published report.
prepare_report "2D" "${report_2d_zip}"
prepare_report "3D" "${report_3d_zip}"

for dimension in 2D 3D; do
  target_dir="${repo_root}/${dimension}"
  expected_target="${repo_root}/${dimension}"

  if [[ ! -d "${target_dir}" || $(realpath "${target_dir}") != "${expected_target}" ]]; then
    echo "Error: refusing to replace unexpected target: ${target_dir}" >&2
    exit 1
  fi

  rsync -a --delete -- "${temporary_root}/${dimension}-site/" "${target_dir}/"
done

echo "Updated the local 2D and 3D report directories."
echo
git -C "${repo_root}" status --short
echo
echo "Review the changes, then publish them with:"
echo "  git -C '${repo_root}' add -A"
echo "  git -C '${repo_root}' commit -m 'Update 2D and 3D test reports'"
echo "  git -C '${repo_root}' push"
