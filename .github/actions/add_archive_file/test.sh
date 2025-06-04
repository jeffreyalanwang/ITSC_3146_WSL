#!/bin/bash

SCRIPT_DIR="$(dirname "$0")"
SCRIPT="${SCRIPT_DIR}/add_archive_file.sh"

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

test_unzip_to_temp() {

    # Setup

    # ensure files we use do not exist yet
    rm -f /tmp/hello.txt
    rm -f "/tmp/directory 01927834/hell o.txt"
    rm -f /tmp/hi.txt
    rm -f -r /tmp/add_archive_file/
    rm -f -r /var/run/add_archive_file/

    # create an example gzipped file
    local filepath
    filepath="/tmp/hello.txt"
    # unzipped contents first
    echo "file contents" > $filepath
    # get its md5
    local expected_md5
    expected_md5=$(md5sum "$filepath" | awk '{print $1}')
    # now gzip it
    cat "$filepath" | gzip --best > "/tmp/hello.gz"
    rm "$filepath"
    mv "/tmp/hello.gz" "$filepath"

    # Execute
    local unzipped_path actual_md5 output warning_str

    # Attempt 1: make sure GitHub Actions temp variable not set
    # setup
    RUNNER_TEMP=""
    # execute
    unzipped_path="$($SCRIPT unzip_to_temp "$filepath")"
    # assert we made the same file, but in the tmp directory
    assertSame "/tmp/add_archive_file/hello.txt" "$unzipped_path"
    # assert md5 equal to expected_md5
    actual_md5="$(cat "$unzipped_path" | md5sum - | awk '{print $1}')"
    assertSame "$expected_md5" "$actual_md5"

    # Attempt 2: try a path with spaces #TODO do this with a direct call (source the script)
    # setup
    RUNNER_TEMP=""
    mkdir -p "/tmp/directory 01927834"
    cp "/tmp/hello.txt" "/tmp/directory 01927834/hell o.txt"
    # execute
    unzipped_path="$($SCRIPT unzip_to_temp "/tmp/directory 01927834/hell o.txt")"
    # assert we made the same file, but in the tmp directory
    assertSame "/tmp/add_archive_file/hell o.txt" "$unzipped_path"
    # assert md5 equal to expected_md5
    actual_md5="$(cat "$unzipped_path" | md5sum - | awk '{print $1}')"
    assertSame "$expected_md5" "$actual_md5"

    # Attempt 3: set GitHub Actions temp variable
    # setup
    RUNNER_TEMP="/var/run"
    # execute
    unzipped_path="$($SCRIPT unzip_to_temp "$filepath")"
    # assert we made the same file, but in the tmp directory
    assertSame "/var/run/add_archive_file/hello.txt" "$unzipped_path"
    # assert md5 equal to expected_md5
    actual_md5="$(cat "$unzipped_path" | md5sum - | awk '{print $1}')"
    assertSame "$expected_md5" "$actual_md5"  

    # Attempt 4: ensure errors when origin file is in the destination temp dir
    # setup
    RUNNER_TEMP=""
    cp -f "/tmp/hello.txt" "/tmp/add_archive_file/hello.txt"
    # execute
    output="$($SCRIPT unzip_to_temp "/tmp/add_archive_file/hello.txt" || echo "failed")"
    # assert that we failed
    assertSame "failed" "$output"

    # Attempt 5: ensure warning when some other file in the destination temp location
    # setup
    RUNNER_TEMP=""
    cp -f "/tmp/hello.txt" "/tmp/hi.txt"
    cp -f "/tmp/hello.txt" "/tmp/add_archive_file/hi.txt"
    # execute
    warning_str="$($SCRIPT unzip_to_temp "/tmp/hi.txt" | grep "Warning")"
    # assert that we got a warning
    assertNotNull "$warning_str"
}

test_add_file_to_archive() {

    # Setup

    # ensure files we use do not exist yet
    rm -f "/tmp/hello.tar"
    rm -f "/tmp/hello.tarbutgzipped"
    rm -f "/tmp/file.txt"
    rm -f -r "/tmp/extracted/"

    # create an example empty tar archive
    local tarpath
    tarpath="/tmp/hello.tar"
    tar -cf "$tarpath" -T /dev/null
    assertEquals 0 "$(tar -tvf "$tarpath" | wc -l)"
    
    # create an example file
    local filepath
    filepath="/tmp/file.txt"
    echo "hi" > $filepath
    # get its md5
    local expected_file_md5
    expected_file_md5=$(md5sum "$filepath" | awk '{print $1}')

    # Execute
    local output warning_str

    # Attempt 1: add file
    # setup
    mkdir -p "/tmp/extracted"
    # execute
    $SCRIPT add_file_to_archive "$tarpath" "$filepath" "my/path/in/archive"
    # assert file now in the archive
    assertEquals 1 "$(tar -tvf "$tarpath" | wc -l)"
    # assert correct path of file
    tar -xf "$tarpath" -C "/tmp/extracted"
    assertTrue [[ -f "/tmp/extracted/my/path/in/archive" ]]
    # assert we didn't add an empty file somehow
    actual_md5="$(cat "/tmp/extracted/my/path/in/archive" | md5sum - | awk '{print $1}')"
    assertSame "$expected_file_md5" "$actual_md5"

    # Attempt 2: ensure error when pipe in file dest path
    # setup: none
    # execute
    output="$($SCRIPT add_file_to_archive "$tarpath" "$filepath" "my/path/in/archive|" || echo "failed")"
    # assert that we failed
    assertSame "failed" "$output"

    # Attempt 3: ensure error when archive is gzipped
    # setup
    cat "$tarpath" | gzip > "/tmp/hello.tarbutgzipped"
    # execute
    output="$($SCRIPT add_file_to_archive "/tmp/hello.tarbutgzipped" "$filepath" "my/path/in/archive" || echo "failed")"
    # assert that we failed
    assertSame "failed" "$output"

    # Attempt 4: ensure warning when / starts file dest path
    # setup: none
    # execute
    warning_str="$($SCRIPT add_file_to_archive "$tarpath" "$filepath" "/my/path/in/archive" | grep "Warning")"
    # assert that we got a warning
    assertNotNull "$warning_str"
}

test_rezip_to_path() {

    # Setup

    # ensure files we use do not exist yet
    rm -f "/tmp/greetings.txt"
    rm -f -r "/tmp/rezipped_file"

    # create an example unzipped file
    local filepath
    filepath="/tmp/greetings.txt"
    echo "file contents" > $filepath

    # see what happens when we zip it ourselves
    local zipped_md5
    zipped_md5="$(cat "$filepath" | gzip --best | md5sum - | awk '{print $1}')"

    # Execute
    local dest_path output actual_md5

    # Attempt 1: unzip to an arbitrary directory
    # setup
    dest_path="/tmp/rezipped_file"
    # execute
    $SCRIPT rezip_to_path "$filepath" "$dest_path"
    # get md5sum and assert equal to zipped_md5
    actual_md5="$(cat "$dest_path" | md5sum - | awk '{print $1}')"
    assertSame "$zipped_md5" "$actual_md5"

    # Attempt 2: ensure error when filepath and dest_path are the same
    # setup: none
    # execute
    output="$($SCRIPT rezip_to_path "$filepath" "$filepath" || echo "failed")"
    # assert that we failed
    assertSame "failed" "$unzipped_path"

    # Attempt 3: ensure error when some other file at dest_path
    # setup
    rm -f "$dest_path"
    touch "$dest_path"
    # execute
    output="$($SCRIPT rezip_to_path "$filepath" "$dest_path" || echo "failed")"
    # assert that we failed
    assertSame "failed" "$unzipped_path"
}

test_main() {

    # Setup

    # ensure files we use do not exist yet
    rm -f "/tmp/gzippedtar"
    rm -f "/tmp/file 1"
    rm -f "/tmp/file 2"
    rm -f "/tmp/new_test_archive"
    rm -f -r "/tmp/add_archive_file/"
    rm -f -r "/tmp/unzip_to_dir"

    # create stdin value
    local files_json_value
    files_json_value='
        {
            "/tmp/file 1": "dest/file",
            "/tmp/file 2": "dest1"
        }
    '

    # create an example gzipped tar archive
    local tarpath
    tarpath="/tmp/gzippedtar"
    tar -c --to-stdout -T /dev/null | gzip > "$tarpath"
    assertEquals 0 "$(tar -tvzf "$tarpath" | wc -l)"
    
    # create example files
    echo "hi" > "/tmp/file 1"
    echo "hello" > "/tmp/file 2"
    # get their md5s
    local expected_file_1_md5 expected_file_2_md5
    expected_file_1_md5=$(md5sum "/tmp/file 1" | awk '{print $1}')
    expected_file_2_md5=$(md5sum "/tmp/file 2" | awk '{print $1}')

    # Execute
    local dest_path unzip_dir files_count actual_file_1_md5 actual_file_2_md5 output

    # Attempt 1: unzip to an arbitrary directory
    # setup
    dest_path="/tmp/new_test_archive"
    unzip_dir="/tmp/unzip_to_dir"
    # execute
    echo "$files_json_value" | $SCRIPT main "$tarpath" "$dest_path"
    # assert is gzipped and has 2 files
    files_count="$(tar -tz -f "$dest_path" | wc -l)"
    assertEquals 2 "$files_count"
    # assert md5 sums
    tar -xz -f "$dest_path" -C "$unzip_dir"
    actual_file_1_md5="$(cat "${unzip_dir}/dest/file" | md5sum - | awk '{print $1}')"
    actual_file_2_md5="$(cat "${unzip_dir}/dest1" | md5sum - | awk '{print $1}')"
    assertSame "$expected_file_1_md5" "$actual_file_1_md5"
    assertSame "$expected_file_2_md5" "$actual_file_2_md5"

    # Attempt 2: ensure error when filepath and dest_path are the same
    # setup: none
    # execute
    output="$( { echo "$files_json_value" | $SCRIPT main "$tarpath" "$tarpath" ; } || echo "failed")"
    # assert that we failed
    assertSame "failed" "$unzipped_path"

    # Attempt 3: ensure error when some other file at dest_path
    # setup
    rm -f "$dest_path"
    touch "$dest_path"
    # execute
    output="$( { echo "$files_json_value" | $SCRIPT main "$tarpath" "$dest_path" ; } || echo "failed")"
    # assert that we failed
    assertSame "failed" "$unzipped_path"

    # Attempt 4: ensure error when no stdin
    # setup: none
    # execute
    output="$($SCRIPT main "$tarpath" "$dest_path" || echo "failed")"
    # assert that we failed
    assertSame "failed" "$unzipped_path"
}

# #TODO once you get here, change everything above to use source,
# #TODO and what's below should test by calling the script at cmdline
# test_cmdline() {
#     # test piping
#      | $SCRIPT main "$archive_path" "$modified_archive_path"
#     # check dest checksum

#     # test that we can quote files with spaces in them
#     archive_path="/tmp/directory with space/archive without extension"
#     modified_archive_path="/tmp/directory with space/new archive"
#      | $SCRIPT main "$archive_path" "$modified_archive_path"
#     # check dest checksum
# }

# Load shUnit2.
. shunit2