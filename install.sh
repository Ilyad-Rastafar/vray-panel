#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}
echo "arch: $(arch)"

os_version=""
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Please use CentOS 8 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 20 ]]; then
        echo -e "${red}please use Ubuntu 20 or higher version! ${plain}\n" && exit 1
    fi

elif [[ "${release}" == "fedora" ]]; then
    if [[ ${os_version} -lt 36 ]]; then
        echo -e "${red}please use Fedora 36 or higher version! ${plain}\n" && exit 1
    fi

elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 10 ]]; then
        echo -e "${red} Please use Debian 10 or higher ${plain}\n" && exit 1
    fi
else
    echo -e "${red}Failed to check the OS version, please contact the author!${plain}" && exit 1
fi

install_dependencies() {
    case "${release}" in
    centos)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    *)
        apt-get update && apt install -y -q wget curl tar tzdata
        ;;
    esac
}

#This function will be called when user installed vray-panel out of sercurity
config_after_install() {
    echo -e "${yellow}Install/update finished! For security it's recommended to modify panel settings ${plain}"
    read -p "Do you want to continue with the modification [y/n]? ": config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        read -p "Please set up your username:" config_account
        echo -e "${yellow}Your username will be:${config_account}${plain}"
        read -p "Please set up your password:" config_password
        echo -e "${yellow}Your password will be:${config_password}${plain}"
        read -p "Please set up the panel port:" config_port
        echo -e "${yellow}Your panel port is:${config_port}${plain}"
        echo -e "${yellow}Initializing, please wait...${plain}"
        /usr/local/vray-panel/vray-panel setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}Account name and password set successfully!${plain}"
        /usr/local/vray-panel/vray-panel setting -port ${config_port}
        echo -e "${yellow}Panel port set successfully!${plain}"
    else
        echo -e "${red}cancel...${plain}"
        if [[ ! -f "/etc/vray-panel/vray-panel.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            /usr/local/vray-panel/vray-panel setting -username ${usernameTemp} -password ${passwordTemp}
            echo -e "this is a fresh installation,will generate random login info for security concerns:"
            echo -e "###############################################"
            echo -e "${green}username:${usernameTemp}${plain}"
            echo -e "${green}password:${passwordTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red}if you forgot your login info,you can type vray-panel and then type 7 to check after installation${plain}"
        else
            echo -e "${red} this is your upgrade,will keep old settings,if you forgot your login info,you can type vray-panel and then type 7 to check${plain}"
        fi
    fi
    /usr/local/vray-panel/vray-panel migrate
}

install_vray-panel() {
    # checks if the installation backup dir exist. if existed then ask user if they want to restore it else continue installation.
    if [[ -e /usr/local/vray-panel-backup/ ]]; then
        read -p "Failed installation detected. Do you want to restore previously installed version? [y/n]? ": restore_confirm
        if [[ "${restore_confirm}" == "y" || "${restore_confirm}" == "Y" ]]; then
            systemctl stop vray-panel
            mv /usr/local/vray-panel-backup/vray-panel.db /etc/vray-panel/ -f
            mv /usr/local/vray-panel-backup/ /usr/local/vray-panel/ -f
            systemctl start vray-panel
            echo -e "${green}previous installed vray-panel restored successfully${plain}, it is up and running now..."
            exit 0
        else
            echo -e "Continuing installing vray-panel ..."
        fi
    fi

    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/IlyadKruger/vray-panel/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to fetch vray-panel version, it maybe due to Github API restrictions, please try it later${plain}"
            exit 1
        fi
        echo -e "Got vray-panel latest version: ${last_version}, beginning the installation..."
        wget -N --no-check-certificate -O /usr/local/vray-panel-linux-$(arch).tar.gz https://github.com/IlyadKruger/vray-panel/releases/download/${last_version}/vray-panel-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading vray-panel failed, please be sure that your server can access Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/IlyadKruger/vray-panel/releases/download/${last_version}/vray-panel-linux-$(arch).tar.gz"
        echo -e "Beginning to install vray-panel v$1"
        wget -N --no-check-certificate -O /usr/local/vray-panel-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}download vray-panel v$1 failed,please check the version exists${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/vray-panel/ ]]; then
        systemctl stop vray-panel
        mv /usr/local/vray-panel/ /usr/local/vray-panel-backup/ -f
        cp /etc/vray-panel/vray-panel.db /usr/local/vray-panel-backup/ -f
    fi

    tar zxvf vray-panel-linux-$(arch).tar.gz
    rm vray-panel-linux-$(arch).tar.gz -f
    cd vray-panel
    chmod +x vray-panel

    # Check the system's architecture and rename the file accordingly
    if [[ $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x vray-panel bin/xray-linux-$(arch)
    cp -f vray-panel.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/vray-panel https://raw.githubusercontent.com/IlyadKruger/vray-panel/main/vray-panel.sh
    chmod +x /usr/local/vray-panel/vray-panel.sh
    chmod +x /usr/bin/vray-panel
    config_after_install
    rm /usr/local/vray-panel-backup/ -rf
    #echo -e "If it is a new installation, the default web port is ${green}54321${plain}, The username and password are ${green}admin${plain} by default"
    #echo -e "Please make sure that this port is not occupied by other procedures,${yellow} And make sure that port 54321 has been released${plain}"
    #    echo -e "If you want to modify the 54321 to other ports and enter the vray-panel command to modify it, you must also ensure that the port you modify is also released"
    #echo -e ""
    #echo -e "If it is updated panel, access the panel in your previous way"
    #echo -e ""
    systemctl daemon-reload
    systemctl enable vray-panel
    systemctl start vray-panel
    echo -e "${green}vray-panel v${last_version}${plain} installation finished, it is up and running now..."
    echo -e ""
    echo "vray-panel Control Menu Usage"
    echo "------------------------------------------"
    echo "SUBCOMMANDS:"
    echo "vray-panel              - Admin Management Script"
    echo "vray-panel start        - Start"
    echo "vray-panel stop         - Stop"
    echo "vray-panel restart      - Restart"
    echo "vray-panel status       - Current Status"
    echo "vray-panel enable       - Enable Autostart on OS Startup"
    echo "vray-panel disable      - Disable Autostart on OS Startup"
    echo "vray-panel log          - Check Logs"
    echo "vray-panel update       - Update"
    echo "vray-panel install      - Install"
    echo "vray-panel uninstall    - Uninstall"
    echo "vray-panel help         - Control Menu Usage"
    echo "------------------------------------------"
}

echo -e "${green}Running...${plain}"
install_dependencies
install_vray-panel $1
