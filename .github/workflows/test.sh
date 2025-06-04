#!/bin/bash

SCRIPT_DIR="$(dirname "$0")"
GITHUB_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$GITHUB_DIR")"
if [[ ! -d "${REPO_DIR}/.git/" ]]; then
    echo "Error: REPO_DIR does not appear to be the base git repo directory." >&2
    exit 1
fi
BUILD_OUTPUT_DIR="${REPO_DIR}/build"

SCRIPT="${SCRIPT_DIR}/build.sh"

test_param_count() {
	bash -s -e -o pipefail <<- EOF
		source $SCRIPT
		assertTrue param_count 1 1
		assertTrue param_count 0 0
		assertFalse param_count 1 0
		assertFalse param_count 0 1
		assertFalse param_count 2 3
		assertFalse param_count 3 1
	EOF
}

test_files_to_copy_json() {

    # Setup: none

    # Execute

    # Attempt 1
    # setup: none
    # execute
    local json_obj
    json_obj="$($SCRIPT files_to_copy_json)"
    # asserts for keys
    local keys
    readarray keys < <(echo "$json_obj" | jq 'keys[]')
    # assert that there are more than 3 files to copy
    assertTrue "[[ 3 < ${#keys[@]} ]]"
    # assert that every key is a filename that exists
    for key in "${keys[@]}"; do
        assertTrue "[[ -f $key ]]"
    done
    
}

test_main() {

    # Setup

    # ensure files we use do not exist yet
    rm -f -r "/tmp/get_ubuntu_images/"
    rm -f -r "/tmp/add_archive_file/"
    rm -f -r "$BUILD_OUTPUT_DIR"

    # Execute
    local output

    # Attempt 1
    # setup: none
    # execute
    output="$($SCRIPT main)"
    # assert output
    assertContains "$output" "amd64"
    assertContains "$output" "arm64"
    assertContains "$output" "/build"
    # assert we now have 2 images
    assertEquals 2 "$(ls "$BUILD_OUTPUT_DIR" | wc -l)"
}

test_cmdline() {
    
    local output

    # Test that we can call main by calling script with no arguments.
    # setup: ensure files we use do not exist yet
    rm -f -r "/tmp/get_ubuntu_images/"
    rm -f -r "/tmp/add_archive_file/"
    rm -f -r "$BUILD_OUTPUT_DIR"
    # execute
    $SCRIPT
    # assert we now have 2 images
    assertEquals 2 "$(ls "$BUILD_OUTPUT_DIR" | wc -l)"

    # Test that we can quote files with spaces in them.
    # setup
    local arg1 arg2
    arg1="/tmp/directory with space/archive without extension"
    arg2="/tmp/directory with space/new archive"
    # execute
    output="$($SCRIPT echo_args "$arg1" "$arg2")"
    # assert
    assertSame "$arg2" "$output"
}

# Load shUnit2.
. shunit2