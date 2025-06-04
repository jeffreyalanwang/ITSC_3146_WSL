#!/bin/bash

SCRIPT_DIR="$(dirname "$0")"
export SCRIPT="${SCRIPT_DIR}/get_ubuntu_images.sh"

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

test_get_wsl_image_links() {
    #TODO this requires source
}

test_check_file_sum() {
    bash -s -e -o pipefail <<- 'EOF'
		source $SCRIPT
		
        # Setup
        local filepath sha256sum
        filepath="/bin/dash"
        expected_sha256sum="$(sha256sum "$filepath" | awk '{print $1}')"

        # Execute

        # Check behavior
        assertTrue check_file_sum "$filepath" "$expected_sha256sum"
        assertFalse check_file_sum "$filepath" "${expected_sha256sum:1}" # cut off first char
		assertFalse check_file_sum "/bin/bash" "$expected_sha256sum" # different existing file
        cd $(dirname "$filepath")
        assertTrue check_file_sum "$(basename "filepath")" "$expected_sha256sum"
        
        # Check edge cases
        assertFalse "[[ -f /non_existent_file ]]"
		assertFalse check_file_sum "/non_existent_file" "$expected_sha256sum"
        assertFalse check_file_sum "$expected_sha256sum" "$filepath"
        assertFalse check_file_sum "$filepath"
        assertFalse check_file_sum "$expected_sha256sum"
	EOF
}

test_download_or_keep() {
    
    # Setup

    # ensure files we use do not exist yet
    rm -f "/tmp/myfile"
    rm -f "/tmp/myfile.1"
    rm -f "/tmp/myfile.1.1"

    # get an example online file
    local url
    url="cheat.sh/ls"
    # get the sha256 for our file
    local expected_sha256sum
    expected_sha256sum="$(curl "$url" | sha256sum - | awk '{print $1}')"

    # Execute
    local requested_path actual_path
    requested_path="/tmp/myfile"

    # Attempt 1: Download a file to a test dir
    # setup: none
    # execute
    actual_path="$($SCRIPT download_or_keep "$url" "$requested_path" "$expected_sha256sum")"
    # assert that we get the path we asked for
    assertEquals "$requested_path" "$actual_path"
    # assert that we downloaded the file's contents correctly
    actual_sha256sum="$(sha256sum "$actual_path")"
    assertEquals "$expected_sha256sum" "$actual_sha256sum"

    # Attempt 2: Download the file again (same file contents)
    # setup: none
    # execute
    actual_path="$($SCRIPT download_or_keep "$url" "$requested_path" "$expected_sha256sum")"
    # assert that we get the same path
    assertEquals "$requested_path" "$actual_path"
    # assert that we downloaded the file's contents correctly
    actual_sha256sum="$(sha256sum "$actual_path")"
    assertEquals "$expected_sha256sum" "$actual_sha256sum"

    # Attempt 3: Download the file to a destination which has a different file value
    # setup
    rm -r "${requested_path}"
    touch "${requested_path}"
    echo "contents" > "${requested_path}.1"
    # execute
    actual_path="$($SCRIPT download_or_keep "$url" "$requested_path" "$expected_sha256sum")"
    # assert that we get the expected path
    assertEquals "${requested_path}.1.1" "$actual_path"
    # assert that we downloaded the file's contents correctly
    actual_sha256sum="$(sha256sum "$actual_path")"
    assertEquals "$expected_sha256sum" "$actual_sha256sum"
}

test_download_wsl_images() {

    # Setup

    # ensure files we use do not exist yet
    rm -f -r /tmp/get_ubuntu_images/
    rm -f -r /var/run/get_ubuntu_images/

    # Execute
    local output

    # Attempt 1: make sure GitHub Actions temp variable not set
    # setup
    RUNNER_TEMP=""
    # execute
    output=$($SCRIPT download_wsl_images || echo "failed")
    # assert it worked
    assertNotSame "failed" "$output"
    # assert we downloaded to the correct temp dir
    assertTrue "[[ -d /tmp/get_ubuntu_images ]]"
    assertEquals 2 "$(ls /tmp/get_ubuntu_images | wc -l)"

    # Attempt 2: set GitHub Actions temp variable
    # setup
    RUNNER_TEMP="/var/run"
    # execute
    output=$($SCRIPT download_wsl_images || echo "failed")
    # assert it worked
    assertNotSame "failed" "$output"
    # assert we downloaded to the correct temp dir
    assertTrue "[[ -d /var/run/get_ubuntu_images ]]"
    assertEquals 2 "$(ls /var/run/get_ubuntu_images | wc -l)"
}

test_check_images() {
    #TODO this requires source
}

test_main() {

    # Setup

    # ensure files we use do not exist yet
    rm -f -r "/tmp/get_ubuntu_images/"

    # Execute

    # Attempt 1
    # setup: none
    # execute
    declare -A paths="( $($SCRIPT main) )"
    # assert array contains 2 keys
    assertEquals 2 "${#paths[@]}"
    # assert we downloaded WSL images
    assertContains "${paths[amd64]}" ".wsl"
    assertContains "${paths[arm64]}" ".wsl"
    # assert the right keys match the right files
    assertContains "${paths[amd64]}" "amd64"
    assertContains "${paths[arm64]}" "arm64"
    # assert we downloaded Ubuntu images
    assertNotNull "$(tar -tzf "${paths[amd64]}" | grep "^etc/cloud/cloud.cfg.d/")"
    assertNotNull "$(tar -tzf "${paths[arm64]}" | grep "^etc/cloud/cloud.cfg.d/")"

}

# #TODO once you get here, change everything above to use source,
# #TODO and what's below should test by calling the script at cmdline
# test_cmdline() {
#     # test that we can quote files with spaces in them
#     archive_path="/tmp/directory with space/archive without extension"
#     modified_archive_path="/tmp/directory with space/new archive"
#      | $SCRIPT main "$archive_path" "$modified_archive_path"
#     # check dest checksum
# }

# Load shUnit2.
. shunit2