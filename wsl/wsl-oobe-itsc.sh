#!/bin/bash
set -euo pipefail
# Based on standard Ubuntu WSL image: /usr/lib/wsl/wsl-setup
# Taken from Ubuntu WSL 24.04.2 image
PREPARED_USER_NAME="itsc"

# command_not_found_handle is a noop function that prevents printing error messages if WSL interop is disabled.
function command_not_found_handle() {
	:
}

# get_first_interactive_uid returns first interactive non system user uid with uid >=1000.
function get_first_interactive_uid() {
	getent passwd | egrep -v '/nologin|/false|/sync' | sort -t: -k3,3n | awk -F: '$3 >= 1000 { print $3; exit }'
}

# create_regular_user prompts user for a username and assign default WSL permissions.
# First argument is the prefilled username.
function create_regular_user() {
	local default_username="${1}"

	local valid_username_regex='^[a-z_][a-z0-9_-]*$'
	local DEFAULT_GROUPS='adm,cdrom,sudo,dip,plugdev'

	# Filter the prefilled username to remove invalid characters.
	default_username=$(echo "${default_username}" | sed 's/[^a-z0-9_-]//g')
	# It should start with a character or _.
	default_username=$(echo "${default_username}" | sed 's/^[^a-z_]//')

	# Ensure a valid username
	while true; do
		# Prefill the prompt with the Windows username.
		read -e -p "Create a default Unix user account: " -i "${default_username}" username

		# Validate the username.
		if [[ ! "${username}" =~ ${valid_username_regex} ]]; then
			echo "Invalid username. A valid username must start with a lowercase letter or underscore, and can contain lowercase letters, digits, underscores, and dashes."
			continue
		fi

		# Create the user and change its default groups.
		if ! /usr/sbin/adduser --quiet --gecos '' "${username}"; then
			echo "Failed to create user '${username}'. Please choose a different name."
			continue
		fi

		if ! /usr/sbin/usermod "${username}" -aG "${DEFAULT_GROUPS}"; then
			echo "Failed to add '${username}' to default groups. Attempting cleanup."
			/usr/sbin/deluser --quiet "${username}"
			continue
		fi

		break
	done
}

# set_user_as_default sets the given username as the default user in the wsl.conf configuration.
# It will only set it if there is no existing default under the [user] section.
function set_user_as_default() {
	local username="${1}"

	local wsl_conf="/etc/wsl.conf"
	touch "${wsl_conf}"

	# Append [user] section with default if they don't exist.
	if ! grep -q "^\[user\]" "${wsl_conf}"; then
		echo -e "\n[user]\ndefault=${username}" >> "${wsl_conf}"
		return
	fi

	# If default is missing from the user section, append it to it.
	if ! sed -n '/^\[user\]/,/^\[/{/^\s*default\s*=/p}' "${wsl_conf}" | grep -q .; then
		sed -i '/^\[user\]/a\default='"${username}" "${wsl_conf}"
	fi
}

# install_ubuntu_font copies the Ubuntu font into Windows filesystem and register it for the current Windows user.
function install_ubuntu_font() {
	local local_app_data=$(powershell.exe -NoProfile -Command '$Env:LocalAppData') 2>/dev/null || true
	local_app_data="${local_app_data%%[[:cntrl:]]}"

	if [ -z "${local_app_data}" ]; then
		return
	fi

	local_app_data=$(wslpath -au "${local_app_data}") 2>/dev/null || true
	local fonts_dir="${local_app_data}/Microsoft/Windows/Fonts"
	local font="UbuntuMono[wght].ttf"
	mkdir -p "${fonts_dir}" 2>/dev/null
	if [ -f "${fonts_dir}/${font}" ]; then
		return
	fi

	cp "/usr/share/fonts/truetype/ubuntu/${font}" "${fonts_dir}" 2>/dev/null || true

	# Register the font for the current user.
	local dst=$(wslpath -aw "${fonts_dir}/${font}") 2>/dev/null || true
	powershell.exe -NoProfile -Command '& {
							$null = New-Item -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion" -Name "Fonts" 2>$null;
							$null = New-ItemProperty -Name "Ubuntu Mono (TrueType)" -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -PropertyType string -Value "'"${dst}"'" 2>$null;
	}' || true
}

# ensure_wslconfig_settings sets mirrored networking for the global .wslconfig file in Windows.
function ensure_wslconfig_settings() {
	local local_windows_home=$(powershell.exe -NoProfile -Command '$Env:UserProfile') 2>/dev/null || true
	local_windows_home="${local_windows_home%%[[:cntrl:]]}"

	if [ -z "${local_windows_home}" ]; then
		return
	fi

	local_windows_home=$(wslpath -au "${local_windows_home}") 2>/dev/null || true
	local wslconfig_path="${local_windows_home}/.wslconfig"

	if ! [ -f "$wslconfig_path" ] || ! ( grep -Fq '[wsl2]' "$wslconfig_path"; ); then
	  # add the [wsl2] header if not present
		echo '[wsl2]' >> "$wslconfig_path"
	fi

	if grep -Fq 'networkingMode' "$wslconfig_path"; then
	  # if networkingMode is already set to something, replace that line
		sed -i -E 's/networkingMode.*$/networkingMode=mirrored/' "$wslconfig_path"
	else
		# place right after the [wsl2] header
		gawk -i inplace '/[wsl2]/ { print; print "networkingMode=mirrored"; next }1' "$wslconfig_path"
	fi
}

clear
echo "Provisioning the new WSL instance $(wslpath -am / | cut -d '/' -f 4)"
echo "This might take a while..."

ensure_wslconfig_settings
install_ubuntu_font

# Wait for cloud-init to finish if systemd and its service is enabled.
if status=$(LANG=C systemctl is-system-running 2>/dev/null) || [ "${status}" != "offline" ] && systemctl is-enabled --quiet cloud-init.service 2>/dev/null
then
	cloud-init status --wait > /dev/null 2>&1 || true
else
	exit 1
fi

# Check if there is a pre-provisioned users (pre-baked on the rootfs or created by cloud-init).
user_id=$(get_first_interactive_uid)

if [ -z "${user_id}" ] ; then
	# We must create a user.
	echo "WARNING: No existing default user."
	create_regular_user "${PREPARED_USER_NAME}"

	user_id=$(get_first_interactive_uid)
	if [ -z "${user_id}" ] ; then
		echo 'Failed to create a regular user account.'
		exit 1
	fi
else
	# We are using a pre-existing user.
	username=$(id -un "${user_id}")
	if [[ "${username}" != "${PREPARED_USER_NAME}" ]]; then
		echo "WARNING: Expected default user ${PREPARED_USER_NAME}, but was instead existing user ${username}. Using ${username}."
	fi
	sudo passwd "${username}"
fi

# Set the newly created user as the WSL default.
set_user_as_default "${username}"

echo
echo "Shutting down in 2 seconds; close this terminal, then reopen from Start Menu or with 'wsl -d ITSC-3146.'"
echo
echo
{ sleep 2 && wsl.exe --shutdown; } & disown