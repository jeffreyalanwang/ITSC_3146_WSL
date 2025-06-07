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
    bash -s -e -o pipefail <<- 'EOF'
		source $SCRIPT
        
        # Setup

        assertNull "$populated_links"
        assertNull "$amd64url"
        assertNull "$amd64sha256"
        assertNull "$arm64url"
        assertNull "$arm64sha256"

        # Execute

        get_wsl_image_links

        # Assert outputs

        assertTrue "[[ $populated_links == 'true' ]]"
        assertContains "$amd64url" 'https://'
        assertContains "$arm64url" 'https://'
        assertEquals 64 "$(wc -m "$amd64sha256")"
        assertEquals 64 "$(wc -m "$arm64sha256")"
	EOF
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

    echo "- Case 1: Download a file to a test dir"
    # setup: none
    # execute
    actual_path="$($SCRIPT download_or_keep "$url" "$requested_path" "$expected_sha256sum")"
    # assert that we get the path we asked for
    assertEquals "$requested_path" "$actual_path"
    # assert that we downloaded the file's contents correctly
    actual_sha256sum="$(sha256sum "$actual_path")"
    assertEquals "$expected_sha256sum" "$actual_sha256sum"

    echo "- Case 2: Download the file again (same file contents)"
    # setup: none
    # execute
    actual_path="$($SCRIPT download_or_keep "$url" "$requested_path" "$expected_sha256sum")"
    # assert that we get the same path
    assertEquals "$requested_path" "$actual_path"
    # assert that we downloaded the file's contents correctly
    actual_sha256sum="$(sha256sum "$actual_path")"
    assertEquals "$expected_sha256sum" "$actual_sha256sum"

    echo "- Case 3: Download the file to a destination which has a different file value"
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

    echo "- Case 1: make sure GitHub Actions temp variable not set"
    # setup
    RUNNER_TEMP=""
    # execute
    output=$($SCRIPT download_wsl_images || echo "failed")
    # assert it worked
    assertNotSame "failed" "$output"
    # assert we downloaded to the correct temp dir
    assertTrue "[[ -d /tmp/get_ubuntu_images ]]"
    assertEquals 2 "$(ls /tmp/get_ubuntu_images | wc -l)"

    echo "- Case 2: set GitHub Actions temp variable"
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
    bash -s -e -o pipefail <<- 'EOF'
		source $SCRIPT
		
        # Setup
        amd64img="/bin/dash"
        arm64img="/bin/bash"

        # Execute
        local output # not necessary in a subshell, but for consistency

        echo "- Case 1: populated_links == ''"
        # setup
        populated_links=''
        populated_files='true'
        amd64sha256="$(sha256sum "$amd64img" | awk '{print $1}')"
        arm64sha256="$(sha256sum "$arm64img" | awk '{print $1}')"
        # execute
        output=$(check_images || echo "failed")
        # assert error
        assertNotNull "$output"

        echo "- Case 2: populated_links == 'false'"
        populated_links='false'
        populated_files='true'
        amd64sha256="$(sha256sum "$amd64img" | awk '{print $1}')"
        arm64sha256="$(sha256sum "$arm64img" | awk '{print $1}')"
        # execute
        output=$(check_images || echo "failed")
        # assert error
        assertNotNull "$output"

        echo "- Case 3: wrong hash for amd64img"
        populated_links='true'
        populated_files='true'
        amd64sha256="some extra text, plus $(sha256sum "$amd64img" | awk '{print $1}')"
        arm64sha256="$(sha256sum "$arm64img" | awk '{print $1}')"
        # execute
        output=$(check_images || echo "failed")
        # assert error
        assertNotNull "$output"

        echo "- Case 4: wrong hash for arm64img"
        populated_links='true'
        populated_files='true'
        amd64sha256="$(sha256sum "$amd64img" | awk '{print $1}')"
        arm64sha256="$(sha256sum "$arm64img" | awk '{print $1}') plus some extra text"
        # execute
        output=$(check_images || echo "failed")
        # assert error
        assertNotNull "$output"

        echo "- Case 5: Success state"
        populated_links='true'
        populated_files='true'
        amd64sha256="$(sha256sum "$amd64img" | awk '{print $1}')"
        arm64sha256="$(sha256sum "$arm64img" | awk '{print $1}')"
        # execute
        output=$(check_images || echo "failed")
        # assert no error
        assertNull "$output"
	EOF

}

test_main() {

    # Setup

    # ensure files we use do not exist yet
    rm -f -r "/tmp/get_ubuntu_images/"

    # Execute

    echo "- Case 1"
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

test_cmdline() {
    # test that we can quote files with spaces in them
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