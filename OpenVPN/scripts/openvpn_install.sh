#!/bin/bash
# OpenVPN Access Server Installation Script
# The script will automatically install OpenVPN Access Server based on your Linux distribution.
#
# Copyright 2025 OpenVPN Inc. All Rights Reserved.
#

set -eu

INSTALLATION_SCRIPT_VERSION="1.6"
ARCH=""
PLIST="openvpn-as"
DCO_NAME="openvpn-dco-dkms"
AS_VERSION=""
APT_ALLOW_DOWNGRADES=""
IF_HELD=false
YES_MODE=false
WITHOUT_DCO=false

abort() {
    echo "This $PRETTY_NAME $ARCH distribution is not officially supported. Aborted." >&2
    exit 1
}

repo_error() {
    echo
    echo "Unfortunately the package management program on your operating system is reporting a problem." >&2
    echo "Please refer to our online documentation or contact our support team for assistance." >&2
    exit 4
}

clones_warning() {
    echo "WARNING: This $PRETTY_NAME is a $1 clone and not officially supported," >&2
    echo "however in theory, it's compatible with $1 repositories which we do support." >&2
    echo "This should be compatible but there is no guarantee to function as expected." >&2
    echo
}

initialization() {
    if [ -f "/etc/os-release" ]; then
        . /etc/os-release
    else
        echo "Can not detect OS/distribution. Aborted." >&2
        exit 1
    fi

    case $(uname -m) in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)       abort ;;
    esac

    if [[ "$ARCH" == "arm64" ]]; then
        DISTRO_ARM64_LIST="ubuntu linuxmint pop tuxedo zorin"
        if echo $DISTRO_ARM64_LIST |grep -v -q $ID ; then
            abort
        fi
    fi
    echo "Detected Linux distribution: $PRETTY_NAME $ARCH"
    echo
}

install_packages() {
    initialization

    case $ID in
        ubuntu|debian)
            install_deb
            ;;
        rhel|centos|amzn)
            DCO_NAME="kmod-ovpn-dco"
            install_rpm
            ;;
        linuxmint|pop|tuxedo|zorin)
            clones_warning "Ubuntu"
            install_deb
            ;;
        rocky|almalinux|ol)
            DCO_NAME="kmod-ovpn-dco"
            clones_warning "RHEL"
            install_rpm
            ;;
        *)
            abort
            ;;
    esac
}

install_deb() {
    if [[ "$ID" == "linuxmint" ]]; then
        VERSION_CODENAME=$UBUNTU_CODENAME
    fi
    DISTRO_LIST="buster bullseye bookworm bionic focal jammy noble"
    if echo $DISTRO_LIST |grep -q $VERSION_CODENAME ; then
        confirmation_prompt

        apt update -y -qq || repo_error
        DEBIAN_FRONTEND=noninteractive apt -y -qq install ca-certificates wget net-tools gnupg || repo_error
        mkdir -p /etc/apt/keyrings
        wget https://packages.openvpn.net/as-repo-public.asc -qO /etc/apt/keyrings/as-repository.asc
        echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/as-repository.asc] http://packages.openvpn.net/as/debian $VERSION_CODENAME main" > /etc/apt/sources.list.d/openvpn-as-repo.list
        apt update -y -qq || repo_error
        check_version "deb"
        if $IF_HELD ; then
            apt-mark unhold $PLIST $DCO_NAME
        fi
        DEBIAN_FRONTEND=noninteractive apt -y install "${PLIST}${AS_VERSION}" "$APT_ALLOW_DOWNGRADES" || repo_error
    else
        abort
    fi

    # DCO installation
    if echo $VERSION_CODENAME |grep -qv "buster\|bionic" ; then
        if install_dco "deb" ; then
            apt update -y -qq || repo_error
            DEBIAN_FRONTEND=noninteractive apt -y install $DCO_NAME || repo_error
            enable_dco
        fi
    fi

    if $IF_HELD ; then
        apt-mark hold $PLIST $DCO_NAME
    fi
}

install_rpm() {
    RELEASE=$(echo $VERSION_ID |sed 's/\.[0-9]*//')
    DIST=$ID

    yum list updates 1>/dev/null || repo_error

    if [[ "$RELEASE" == "7" ]]; then
        if [[ "$ID" == "rhel" ]]; then
            confirmation_prompt
            subscription-manager repos --enable rhel-7-server-optional-rpms --enable rhel-server-rhscl-7-rpms || repo_error
        elif [[ "$ID" == "centos" ]]; then
            confirmation_prompt
            yum -y -q install centos-release-scl-rh || repo_error
        fi
        DIST="centos"
    elif [[ "$RELEASE" == "8" || "$RELEASE" == "9" ]]; then
        confirmation_prompt
        DIST="rhel"
    elif [[ "$ID" == "amzn" && "$RELEASE" == "2" ]]; then
        confirmation_prompt
    else
        abort
    fi

    yum -y -q remove openvpn-as-yum || repo_error
    yum -y -q install "https://packages.openvpn.net/as-repo-${DIST}${RELEASE}.rpm" || repo_error
    check_version "rpm"
    if $IF_HELD ; then
        yum versionlock delete $PLIST $DCO_NAME
    fi
    yum -y install "${PLIST}${AS_VERSION}" || repo_error

    # DCO installation
    if [[ "$RELEASE" == "8" || "$RELEASE" == "9" ]]; then
        if install_dco "rpm" ; then
            if [[ "$ID" == "rocky" || "$ID" == "almalinux" ]]; then
                if [[ "$RELEASE" == "8" ]]; then
                    yum config-manager --set-enabled powertools || repo_error
                elif [[ "$RELEASE" == "9" ]]; then
                    yum config-manager --set-enabled crb || repo_error
                fi
                yum -y -q install epel-release || repo_error
            elif [[ "$ID" == "rhel" ]]; then
                yum -y -q install https://dl.fedoraproject.org/pub/epel/epel-release-latest-"$RELEASE".noarch.rpm || repo_error
            fi
            yum -y install $DCO_NAME || repo_error
            enable_dco
        fi
    fi

    if $IF_HELD ; then
        yum versionlock add $PLIST $DCO_NAME
    fi
}

enable_dco() {
    if systemctl is-active --quiet openvpnas; then
        sacli_enable_dco
        systemctl restart openvpnas || exit 13
    else
        systemctl start openvpnas || exit 13
        sacli_enable_dco
        systemctl stop openvpnas || exit 13
    fi
}

sacli_enable_dco() {
    /usr/local/openvpn_as/scripts/sacli --key "vpn.server.daemon.ovpndco" --value "true" configput || exit 12
}

install_dco() {
    if $WITHOUT_DCO; then
        return 103
    fi
    echo
    echo
    echo "Access Server 2.12 and newer supports OpenVPN Data Channel Offload (DCO)."
    echo "You can benefit from performance improvements when you enable DCO for your VPN server and clients."
    echo
    echo "Your running kernel version is '$(uname -r)'"
    echo
    echo "DCO needs Linux kernel headers to be installed."
    echo "If the Linux kernel headers are not present, they will be installed automatically."
    echo
    if ! $YES_MODE; then
        read -p "Would you like to install OpenVPN Data Channel Offload? (Y/n): " resp
        if [[ "$resp" == "N" || "$resp" == "n" ]]; then
            return 102
        fi
    fi
    if check_install_headers "$1" ; then
        echo
        echo "Linux kernel headers are installed. Proceeding with DCO installation."
        echo
        echo "Keep in mind that if newer kernel versions are available,"
        echo "there is a possibility that DCO installation could fail."
        return 0
    else
        echo
        echo "WARNING: The actual kernel headers could not be located and installed." >&2
        echo "For further guidance, please refer to our online documentation or contact our support team." >&2
        echo "https://openvpn.net/as-docs/openvpn-dco.html" >&2
        echo
        echo "DCO can not be installed. Skipped." >&2
    fi
    return 101
}

check_install_headers() {
    if [[ "$1" == "rpm" ]]; then
        if rpm -q kernel-headers-$(uname -r) ; then
            return 0
        else
            if yum -y -q install kernel-headers-$(uname -r) kernel-devel-$(uname -r) ; then
                return 0
            fi
        fi
    elif [[ "$1" == "deb" ]]; then
        if dpkg -l |grep linux-headers-$(uname -r) ; then
            return 0
        else
            apt update -y -qq || repo_error
            if apt -y -qq install linux-headers-$(uname -r) ; then
                return 0
            fi
        fi
    fi
    return 100
}

check_version() {
    echo
    AVAILABLE_VERSION=""
    INSTALLED_VERSION=""
    if [[ "$1" == "rpm" ]]; then
        if [[ -n "$AS_VERSION" ]]; then
            AVAILABLE_VERSION=$(yum -y --showduplicates list available ${PLIST} |grep -F ${AS_VERSION} |tail -1 |awk -F' ' '{print $2}')
            if [[ -z "$AVAILABLE_VERSION" ]]; then
                as_version_not_found
            fi
            AS_VERSION="-${AVAILABLE_VERSION}"
        fi
        if rpm -q --quiet $PLIST ; then
            INSTALLED_VERSION=$(rpm -q --qf "%{VERSION}" $PLIST)
        fi
        if yum versionlock list 2>/dev/null |grep $PLIST |grep -q -v "yum\|bundled"; then
            IF_HELD=true
            held_message
        fi
    elif [[ "$1" == "deb" ]]; then
        if [[ -n "$AS_VERSION" ]]; then
            AVAILABLE_VERSION=$(apt-cache madison ${PLIST} |grep -F ${AS_VERSION} |head -1 |awk -F' ' '{print $3}')
            if [[ -z "$AVAILABLE_VERSION" ]]; then
                as_version_not_found
            fi
            AS_VERSION="=${AVAILABLE_VERSION}"
        fi
        if dpkg -s $PLIST 2>/dev/null |grep Status |grep -q "ok installed" ; then
            INSTALLED_VERSION=$(dpkg-query -W -f='${Version}\n' $PLIST)
        fi
        if apt-mark showhold |grep -q $PLIST ; then
            IF_HELD=true
            held_message
        fi
    else
        echo "Package type '$1' is not supported." >&2
        exit 200
    fi
    if [[ -n "$AS_VERSION" ]]; then
        if [[ -n "$INSTALLED_VERSION" ]]; then
            if echo "$AVAILABLE_VERSION" |grep -q "$INSTALLED_VERSION" ; then
                echo "The OpenVPN Access Server '$INSTALLED_VERSION' package is already installed."
                echo "Nothing to do."
                exit 0
            fi
            if echo -e "$INSTALLED_VERSION\n$AVAILABLE_VERSION" | sort --version-sort -C ; then
                upgrade_message "$INSTALLED_VERSION" "$AVAILABLE_VERSION"
            else
                downgrade_message "$INSTALLED_VERSION" "$AVAILABLE_VERSION"
            fi
        fi
    else
        if [[ -n "$INSTALLED_VERSION" ]]; then
            upgrade_message "$INSTALLED_VERSION"
        fi
    fi
}

upgrade_message() {
    echo "The OpenVPN Access Server '$1' package is currently installed."
    if [[ $# -eq 1 ]]; then
        echo "Upon proceeding, the script will check for a newer version available for"
        echo "the operating system and upgrade the existing installation."
    elif [[ $# -eq 2 ]]; then
        echo "Upon proceeding, the script will upgrade OpenVPN Access Server to '$2' version."
    else
        echo "Too many arguments passed. Aborted." >&2
        exit 201
    fi
    echo
}

downgrade_message() {
    echo "WARNING:"
    echo "The OpenVPN Access Server version '$2' to install is older than currently installed '$1'."
    echo "This is a downgrade and may cause issues."
    echo
    if ! $YES_MODE; then
        read -p "Do you still want to proceed with the downgrade? (Y/n): " downgrade_resp
        if [[ "$downgrade_resp" == "N" || "$downgrade_resp" == "n" ]]; then
            echo "Downgrade aborted." >&2
            exit 0
        fi
    fi
    APT_ALLOW_DOWNGRADES="--allow-downgrades"
}

held_message() {
    echo "WARNING:"
    echo "The current installation is pinned to that version so normal upgrade actions don't inadvertently upgrade it."
    echo "However, if you proceed this will be temporarily ignored and upgraded anyway."
    echo
}

as_version_not_found() {
    echo "Unfortunately the specified Access Server '$AS_VERSION' version could not be found for this operating system." >&2
    echo "Please refer to our online documentation or contact our support team for assistance." >&2
    echo "https://openvpn.net/as-docs/release-notes.html" >&2
    exit 6
}

confirmation_prompt() {
    if ! $YES_MODE; then
        echo "If you're ready to install OpenVPN Access Server, you can continue below."
        echo
        read -p "Do you want to proceed with the installation? (Y/n): " response

        if [[ "$response" == "N" || "$response" == "n" ]]; then
            echo "Installation aborted." >&2
            exit 0
        fi
    fi
}

sudo_message() {
    echo "Run the script either as root, or using sudo to perform the installation."
    echo
    echo "    sudo bash install.sh --yes"
    echo "or"
    echo "    sudo bash -c 'bash <(curl -fsS https://packages.openvpn.net/as/install.sh) --yes'"
    echo
}

user_root_check() {
    user="$(id -un 2>/dev/null || true)"

    if [ "$user" != "root" ]; then
        echo "This installer needs to run as root." >&2
        sudo_message
        echo "Aborted." >&2
        exit 5
    fi
}

usage() {
    echo "Usage: install.sh [-y|--yes] [--without-dco] [--as-version VERSION] [-h|--help] [-v|--version]"
    echo
    echo "OpenVPN Access Server installation script."
    echo "Version: $INSTALLATION_SCRIPT_VERSION"
    echo
    echo "-y, --yes"
    echo "    Automatic yes to prompts. Assume 'yes' as answer to all prompts and run non-interactively."
    echo "    If an undesirable situation occurs then installation will abort."
    echo
    echo "--without-dco"
    echo "    Disables Data Channel Offload (DCO) installation."
    echo
    echo "--as-version VERSION"
    echo "    Specify the version of OpenVPN Access Server to install."
    echo
    echo "-h, --help"
    echo "    Shows a short usage summary."
    echo
    echo "-v, --version"
    echo "    Shows this script version."
    echo

    sudo_message
    exit 0
}

# getopt exit code is captured here to print 'usage' additionally to 'invalid/unrecognized option' error
set +e
options=$(getopt -n install.sh -o yvh --long yes,without-dco,as-version:,version,help -- "$@")
exit_code=$?
set -e
if [ $exit_code -ne 0 ] ; then
    [ $exit_code -eq 1 ] && usage || exit $exit_code
fi

eval set -- "$options"
while :; do
    case "$1" in
        -y|--yes) YES_MODE=true; shift ;;
        --without-dco) WITHOUT_DCO=true; shift ;;
        --as-version) AS_VERSION="$2"; shift 2 ;;
        -v|--version) echo "$INSTALLATION_SCRIPT_VERSION"; exit 0 ;;
        -h|--help) usage ;;
        --) shift; break ;;
        *) echo "Unknown option passed: $1"; usage ;;
    esac
done

echo
echo
echo "Welcome to the OpenVPN Access Server Installation Script!"
echo "Version: $INSTALLATION_SCRIPT_VERSION"
echo
echo
echo "WARNING: Please verify if there are any available security"
echo "and kernel updates for your operating system. We recommend"
echo "installing and applying these updates before proceeding."
echo

user_root_check
install_packages

# 'sacli status' check for additional verification
# if openvpn-as service is up and running after installation.
#
# Do not check openvpn-as service status if 'ovpn init' is skipped.
echo
if [ "${OVPN_INIT_MANUAL:-false}" = true ] ; then
    echo "Installation successful!"
    exit 0
fi
echo -n "Checking status (can take up to 1 minute): ."
exit_counter=12
while [ $exit_counter -gt 0 ] ; do
    if ! /usr/local/openvpn_as/scripts/sacli status 2>&1 |grep -q -i "error:" ; then
        echo "OK"
        echo "Installation successful!"
        exit 0
    fi
    sleep 5
    echo -n "."
    exit_counter=$((exit_counter - 1))
done

echo
echo "Installation successful but 'openvpn-as' service failed to start."
echo "Please run 'sudo sacli status' for more details or contact our support team for assistance."
