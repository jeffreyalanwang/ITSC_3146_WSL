#!/bin/bash -e -o pipefail

temp_dir="/tmp"
if [[ -n "$RUNNER_TEMP" ]]; then
    temp_dir=$RUNNER_TEMP # use GitHub Actions' temp dir if available
fi
temp_dir="${temp_dir}/add_archive_file"
mkdir -p "$temp_dir"

# Ensure a function is provided the correct number of arguments.
#
# $1:       Expected number of arguments.
# $2:       Actual number of arguments.
#
param_count() {
    local expected; expected = $1;
    local actual; actual = $2;

    if [[ -z $1 ]] || [[ -z $1 ]] || [[ -n $3 ]]; then
        echo "Error: param_count requires exactly 2 arguments." >&2
    fi

    if [[ $expected -ne $actual ]]; then
        echo "Error: This function requires exactly $expected arguments, got $actual." >&2
        return 1
    fi
}

# Generate a sed expression to replace a path string's
# directory portion with a new directory.
#
# $1:       New directory.
#
# stdout:   An extended regex pattern (i.e. an argument to `sed -E`)
#           which replaces all text including the last path-separating '/'
#           with `$1`.
#
expr_replacing_dir_in_path() {
    param_count 1 $#
    local new_directory; new_directory="$1"

    # ensure new directory ends in a '/'
    local last_char
    last_char="${new_directory: -1}"
    if [[ last_char != '/' ]]; then
        new_directory="${new_directory}/"
    fi

    # match:
    # from beginning to the last '/' not preceded by a '\'
    local match_directory_pattern
    match_directory_pattern='^(.*[^\\])?\/' # extended regex

    # replace with:
    # escape all characters that would be special when present
    # in the second part of a sed expression ('&', '/', '\')
    # using a preceding backslash: '\'
    local directory_escaped_for_sed
    directory_escaped_for_sed="${new_directory//[&\/\\]/\\&}"

    local sed_expression
    sed_expression="s/$match_directory_pattern/$directory_escaped_for_sed/"
    echo "$sed_expression"
}

# Get a temporary directory, and unzip a gzipped file there.
#
# $1:       Path to a gzipped file.
#           Does not require a .gz suffix.
#
# stdout:   Path to the unzipped file.
#
unzip_to_temp() {
    param_count 1 $#
    local file_path; file_path="$1"

    #TODO replace with dirname to eliminate potential issues
    local sed_expression decompressed_path
    sed_expression="$(expr_replacing_dir_in_path $temp_dir)"
    decompressed_path="$(echo "$file_path" | sed -E "$sed_expression")"

    # Perform some checks
    if [[ "$file_path" == "$decompressed_path" ]]; then
        echo "Error: we are decompressing to the same path as we are reading from." >&2
        return 1
    elif [ -e "$decompressed_path" ]; then
        echo "Warning: file already exists at this path, replacing it."
    fi

    # Unzip to the temp location
    cat $file_path | gzip -d > $decompressed_path
    
    # Debug output: show size and location
    echo $decompressed_path
}

# Add a file to a tar archive.
#
# $1:       Path to the archive.
#           Must be an unzipped .tar archive.
#           Does not require .tar suffix.
# $2:       Path to the file to add.
# $3:       The path of the file, within the archive.
#           Includes file's name.
#           Should not include special character '|'.
#           Generally should not begin with '/', though tar autoremoves them.
#
# stdout:   Debug logs.
#
add_file_to_archive() {
    param_count 3 $#
    local archive_path; archive_path="$1"
    local file_path; file_path="$2"
    local file_dest_path; file_dest_path="$3"

    echo "Adding to tar archive ${archive_path}"
    echo "File source: ${file_path}"
    echo -n "File destination: " # printed by tar --append -v

    # Checks
    if [[ "$file_dest_path" =~ '|' ]]; then
        echo "Error: destination file path cannot contain special character '|'." >&2
        exit 1
    fi
    if [[ ${file_dest_path:0:1} == '/' ]]; then
        echo "Warning: destination file path begins in '/'. " \
             "Files in tar archives are generally not absolute paths."
    fi

    local sed_expression
    sed_expression="s|.*|${file_dest_path}|"
    sed_expression="${sed_expression}x" # for tar --transform,
                                        # x flag indicates we are using
                                        # extended regex (sed -E)

    # Note: tar --append does not remove an existing file with the same name.
    # However, in a tar archive where multiple file records share one path,
    # the file closest to the end of the tar archive stream (i.e. the one we append)
    # takes precedent over the earlier ones.
    tar --append -vf $tar_archive --transform "${sed_expression}" "$source_file" --show-transformed-names
    echo "Done"
}

# Rezip a file with gzip to a destination path.
#
# $1:       Path to an unzipped file.
# $2:       Path to rezip file to.
#           Does not require a .gz suffix.
#
# stdout:   Debug logs.
#
rezip_to_path() {
    param_count 2 $#
    local from_path; from_path="$1"
    local dest_path; dest_path="$2"

    # Perform some checks
    if [[ "$from_path" == "$dest_path" ]]; then
        echo "Error: we are compressing to the same path as we are reading from." >&2
        return 1
    elif [ -e "$dest_path" ]; then
        echo "Warning: file already exists at this path, replacing it."
    fi

    # Rezip
    cat "$from_path" | gzip --best > "$dest_path"
}

# Add files to a gzipped tar archive.
# 
# stdin:                    JSON object.
#                           Keys are filepaths on the current machine.
#                           Values are filepaths when inside the archive.
#
# archive_path:             Path to the archive to add files to.
# modified_archive_path:    Where to create the new archive, including filename.
#                           Must be different from `archive_path`.
#                           The file created here will be gzipped.
#
# stdout:                   Debug logs.
#
main() {
    param_count 2
    local files_json; files_json="$cmdline_stdin"
    local archive_path; archive_path="$1"
    local modified_archive_path; modified_archive_path="$2"

    # Unzip archive
    local unzipped_path
    unzipped_path="$( unzip_to_temp "$image_path" )"

    # Add the files
    local -a keys vals; local count
    readarray -t keys < <(echo "$files_json" | jq 'keys[]')
    readarray -t vals < <(echo "$files_json" | jq '.[]')
    count="${#keys[@]}"
    for i in {1..$count}; do
        local file; file="${keys[i]}"
        local path_in_archive; path_in_archive="${vals[i]}"
        add_file_to_archive "$unzipped_path" "$file" "$path_in_archive"
    done

    # Rezip archive
    rezip_to_path "$unzipped_path" "$modified_archive_path"
}

# Call a function within this script:
#
# $ ./add_archive_file.sh function_name arg_1 arg_2 ...
# > [...]
#
cmdline_stdin="$(cat -)"
$1 "${@:2@Q}" #TODO test that we can quote files with spaces in them