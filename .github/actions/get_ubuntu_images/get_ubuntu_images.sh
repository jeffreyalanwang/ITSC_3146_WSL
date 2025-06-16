#!/bin/bash
set -e -o pipefail

temp_dir="/tmp"
if [[ -n "$RUNNER_TEMP" ]]; then
    temp_dir=$RUNNER_TEMP # use GitHub Actions' temp dir if available
fi
temp_dir="${temp_dir}/get_ubuntu_images"
mkdir -p "$temp_dir"

# Ensure a function is provided the correct number of arguments.
#
# $1:       Expected number of arguments.
# $2:       Actual number of arguments.
#
param_count() {
    local expected; expected=$1;
    local actual; actual=$2;

    if [[ -z $1 ]] || [[ -z $2 ]] || [[ -n $3 ]]; then
        echo "Error: param_count requires exactly 2 arguments." >&2
        exit 1
    fi

    if [[ $expected -ne $actual ]]; then
        echo "Error: This function requires exactly $expected arguments, got $actual." >&2
        exit 1
    fi

    return 0
}

# For use with unit tests.
echo_args() {
    echo "$2"
}

# Get the most up-to-date Ubuntu WSL image file links + checksums.
#
# Output stored in shell variables:
# populated_links:  Whether the output variables can be used yet.
# amd64url:         str
# amd64sha256:      str
# arm64url:         str
# arm64sha256:      str
#
populated_links=false
# shellcheck disable=SC2120 # param_count is 0
get_wsl_image_links() { #TODO test using expected string lengths or URL format and expected substring presence (arm/amd)
    param_count 0 $#
    # Latest Ubuntu WSL image available at:
    # https://github.com/microsoft/WSL/blob/master/distributions/DistributionInfo.json
    # (access using raw link: https://raw.githubusercontent.com/microsoft/WSL/refs/heads/master/distributions/DistributionInfo.json)

    local all_ubuntu_json_objs
    all_ubuntu_json_objs="$(curl 'https://raw.githubusercontent.com/microsoft/WSL/refs/heads/master/distributions/DistributionInfo.json' | jq '.ModernDistributions.Ubuntu[]')"
    # # value of $all_ubuntu_json_objs
    # # (note the lack of comma at top-level. this works for jq)
    # {
    #   "Name": "Ubuntu",
    #   "FriendlyName": "Ubuntu",
    #   "Default": true,
    #   "Amd64Url": {
    #     "Url": "https://releases.ubuntu.com/noble/ubuntu-24.04.2-wsl-amd64.wsl",
    #     "Sha256": "5d1eea52103166f1c460dc012ed325c6eb31d2ce16ef6a00ffdfda8e99e12f43"
    #   },
    #   "Arm64Url": {
    #     "Url": "https://cdimages.ubuntu.com/releases/24.04.2/release/ubuntu-24.04.2-wsl-arm64.wsl",
    #     "Sha256": "75e6660229fabb38a6fdc1c94eec7d834a565fa58a64b7534e540da5319b2576"
    #   }
    # }
    # {
    #   "Name": "Ubuntu-24.04",
    #   "FriendlyName": "Ubuntu 24.04 LTS",
    #   "Default": false,
    #   "Amd64Url": {
    #     "Url": "https://releases.ubuntu.com/noble/ubuntu-24.04.2-wsl-amd64.wsl",
    #     "Sha256": "5d1eea52103166f1c460dc012ed325c6eb31d2ce16ef6a00ffdfda8e99e12f43"
    #   },
    #   "Arm64Url": {
    #     "Url": "https://cdimages.ubuntu.com/releases/24.04.2/release/ubuntu-24.04.2-wsl-arm64.wsl",
    #     "Sha256": "75e6660229fabb38a6fdc1c94eec7d834a565fa58a64b7534e540da5319b2576"
    #   }
    # }

    local ubuntu_version select_version_query ubuntu_json_obj
    ubuntu_version="Ubuntu-24.04" # You may also set this to 'Ubuntu' for the latest version.
    select_version_query='select(.Name == "'"$ubuntu_version"'")'
    ubuntu_json_obj="$(echo "$all_ubuntu_json_objs" | jq "$select_version_query")"
    # # value of $ubuntu_json_obj
    # {
    #   "Name": "Ubuntu-24.04",
    #   "FriendlyName": "Ubuntu 24.04 LTS",
    #   "Default": false,
    #   "Amd64Url": {
    #     "Url": "https://releases.ubuntu.com/noble/ubuntu-24.04.2-wsl-amd64.wsl",
    #     "Sha256": "5d1eea52103166f1c460dc012ed325c6eb31d2ce16ef6a00ffdfda8e99e12f43"
    #   },
    #   "Arm64Url": {
    #     "Url": "https://cdimages.ubuntu.com/releases/24.04.2/release/ubuntu-24.04.2-wsl-arm64.wsl",
    #     "Sha256": "75e6660229fabb38a6fdc1c94eec7d834a565fa58a64b7534e540da5319b2576"
    #   }
    # }

    amd64url="$(echo "$ubuntu_json_obj" | jq --raw-output '.Amd64Url.Url')"
    amd64sha256="$(echo "$ubuntu_json_obj" | jq --raw-output '.Amd64Url.Sha256')"
    arm64url="$(echo "$ubuntu_json_obj" | jq --raw-output '.Arm64Url.Url')"
    arm64sha256="$(echo "$ubuntu_json_obj" | jq --raw-output '.Arm64Url.Sha256')"

    populated_links=true
}

# Check a file against a SHA256 sum.
#
# $1: The file to check.
# $2: The expected checksum.
#
# returns:  0 (true) if file matches
#           1 (false) if not
#
check_file_sum() {
    param_count 2 $#
    local img; img="$1"
    local expected_sum; expected_sum="$2"

    local img_sum
    img_sum="$(sha256sum "$img" | awk '{print $1}')"

    if [[ "$img_sum" == "$expected_sum" ]]; then
        return 0
    else
        return 1
    fi
}

# Download a file to a path where a file may already be present.
# If a file is present, it will be used, if it matches the desired checksum.
#
# $1:       The URL to download.
# $2:       The filepath to try to save to.
#           May be modified if a file is already present there.
# $3:       The expected SHA256 checksum.
#
# stdout:   The filepath to which the file was ultimately downloaded to.
#
download_or_keep() {
    param_count 3 $#
    local url; url="$1"
    local path; path="$2"
    local sha256sum; sha256sum="$3"

    local needs_download
    needs_download=false
    if [[ -e "$path" ]]; then # file already exists at the expected destination
        
        if { check_file_sum "$path" "$sha256sum"; }; then # file has the desired hash
            needs_download=false

        else # file hash does not match
            needs_download=true

            # we will need to save with a new filename
            while [[ -e "$path" ]]; do
                path="${path}.1"
            done
        fi

    else # file doesn't exist yet
        needs_download=true
    fi

    if [[ "$needs_download" == 'true' ]]; then
        if [[ -e "$path" ]]; then
            echo "Error: unreachable situation occurred." >&2
            exit 1
        fi
        wget "$url" -O- > "$path"
    fi

    # output
    echo "$path"
}

# Download the Ubuntu WSL images to a temporary directory.
# `get_wsl_image_links` will be automatically called if needed.
#
# # Output stored in shell variables:
# populated_files:  Whether the output variables can be used yet.
# amd64img:         Path to the amd64 WSL image.
# arm64img:         Path to the arm64 WSL image.
#
# shellcheck disable=SC2120 # param_count is 0
download_wsl_images() {
    param_count 0 $#
    if [[ "$populated_links" != 'true' ]]; then
        get_wsl_image_links
    fi

    # These may not end up being the ultimate paths we use.
    local amd64img_path arm64img_path
    amd64img_path="${temp_dir}/amd64_base_img_${amd64sha256:0:5}.wsl"
    arm64img_path="${temp_dir}/arm64_base_img_${arm64sha256:0:5}.wsl"

    # Download
    amd64img_path="$(download_or_keep "$amd64url" "$amd64img_path" "$amd64sha256")"
    arm64img_path="$(download_or_keep "$arm64url" "$arm64img_path" "$arm64sha256")"

    # Output
    amd64img="$amd64img_path"
    arm64img="$arm64img_path"
    populated_files=true
}

# Check downloaded WSL images against their provided SHA256 sums.
#
# Requires (from `get_wsl_image_links` and `download_wsl_images`):
#    `[[ "$populated_links" = 'true' ]]` \
# && `[[ "$populated_files" = 'true' ]]`
#
# No output, but exits script with failure code (`exit 1`) on failure.
#
# shellcheck disable=SC2120 # param_count is 0
check_images() {
    param_count 0 $#
    
    if [[ ! ("$populated_links" == 'true' && "$populated_files" == 'true') ]]; then
        echo "Required values not present (did you run get_wsl_image_links and download_wsl_images?)." >&2
        echo "populated_links: $populated_links" >&2
        echo "populated_files: $populated_files" >&2
        exit 1
    fi

    # Check amd64 image
    if ! { check_file_sum "$amd64img" "$amd64sha256"; }; then
        echo "amd64 image did not match expected checksum." >&2
        echo "File: $amd64img" >&2
        echo "Expected: $amd64sha256" >&2
        exit 1
    fi

    # Check arm64 image
    if ! { check_file_sum "$arm64img" "$arm64sha256"; }; then
        echo "amd64 image did not match expected checksum." >&2
        echo "File: $arm64img" >&2
        echo "Expected: $arm64sha256" >&2
        exit 1
    fi
}

# Download the most up-to-date Ubuntu WSL image files.
# 
# stdout:       Each line provides the path to one of the downloaded images.
#               Read into an array with:
#                   declare -A var_name="( $(main) )"
#               Format:
#                   [amd64]="/path/to/file"
#                   [arm64]="/path/to/file"
#
# shellcheck disable=SC2120 # param_count is 0
main() {
    param_count 0 $#

    get_wsl_image_links
    download_wsl_images
    check_images

    echo -n '[amd64]='
    echo -n '"'
    echo -n "$amd64img"
    echo '"'

    echo -n '[arm64]='
    echo -n '"'
    echo -n "$arm64img"
    echo '"'
}

# Call a function within this script:
#
# $ ./add_archive_file.sh function_name arg_1 arg_2 ...
# > [...]
#
fn_args=( "${@:2}" )
$1 "${fn_args[@]}"