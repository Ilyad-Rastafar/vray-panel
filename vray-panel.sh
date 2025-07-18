#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

#Add some basic function here
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}
# check root
[[ $EUID -ne 0 ]] && LOGE "ERROR: You must be root to run this script! \n" && exit 1

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


os_version=""
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Please use CentOS 8 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" ==  "ubuntu" ]]; then
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
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [Default$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Restart the panel, Attention: Restarting the panel will also restart xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Press enter to return to the main menu: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/IlyadKruger/vray-panel/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "This function will forcefully reinstall the latest version, and the data will not be lost. Do you want to continue?" "n"
    if [[ $? != 0 ]]; then
        LOGE "Cancelled"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/IlyadKruger/vray-panel/main/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "Update is complete, Panel has automatically restarted "
        exit 0
    fi
}

custom_version() {
    echo "Enter the panel version (like 1.6.0):"
    read panel_version

    if [ -z "$panel_version" ]; then
        echo "Panel version cannot be empty. Exiting."
    exit 1
    fi

    download_link="https://raw.githubusercontent.com/IlyadKruger/vray-panel/master/install.sh"

    # Use the entered panel version in the download link
    install_command="bash <(curl -Ls $download_link) $panel_version"

    echo "Downloading and installing panel version $panel_version..."
    eval $install_command
}

# Function to handle the deletion of the script file
delete_script() {
    rm "$0"  # Remove the script file itself
    exit 1
}

uninstall() {
    confirm "Are you sure you want to uninstall the panel? xray will also uninstalled!" " n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop vray-panel
    systemctl disable vray-panel
    rm /etc/systemd/system/vray-panel.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/vray-panel/ -rf
    rm /usr/local/vray-panel/ -rf
    echo -e "\nUninstalled Successfully."
    echo ""
    echo -e "If you need to install this panel again, you can use below command:"
    echo -e "${green}bash <(curl -Ls https://raw.githubusercontent.com/IlyadKruger/vray-panel/master/install.sh)${plain}"
    echo ""
    # Trap the SIGTERM signal
    trap delete_script SIGTERM
    delete_script
}

reset_user() {
    confirm "Reset your username and password to admin?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/vray-panel/vray-panel setting -username admin -password admin
    echo -e "Username and password have been reset to ${green}admin${plain}，Please restart the panel now."
    confirm_restart
}

reset_config() {
    confirm "Are you sure you want to reset all panel settings，Account data will not be lost，Username and password will not change" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/vray-panel/vray-panel setting -reset
    echo -e "All panel settings have been reset to default，Please restart the panel now，and use the default ${green}54321${plain} Port to Access the web Panel"
    confirm_restart
}

check_config() {
    info=$(/usr/local/vray-panel/vray-panel setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "get current settings error,please check logs"
        show_menu
    fi
    LOGI "${info}"
}

set_port() {
    echo && echo -n -e "Enter port number[1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        LOGD "Cancelled"
        before_show_menu
    else
        /usr/local/vray-panel/vray-panel setting -port ${port}
        echo -e "The port is set，Please restart the panel now，and use the new port ${green}${port}${plain} to access web panel"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "Panel is running，No need to start again，If you need to restart, please select restart"
    else
        systemctl start vray-panel
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "vray-panel Started Successfully"
        else
            LOGE "panel Failed to start，Probably because it takes longer than two seconds to start，Please check the log information later"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "Panel stopped，No need to stop again!"
    else
        systemctl stop vray-panel
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "vray-panel and xray stopped successfully"
        else
            LOGE "Panel stop failed，Probably because the stop time exceeds two seconds，Please check the log information later"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart vray-panel
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "vray-panel and xray Restarted successfully"
    else
        LOGE "Panel restart failed，Probably because it takes longer than two seconds to start，Please check the log information later"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status vray-panel -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable vray-panel
    if [[ $? == 0 ]]; then
        LOGI "vray-panel Set to boot automatically on startup successfully"
    else
        LOGE "vray-panel Failed to set Autostart"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable vray-panel
    if [[ $? == 0 ]]; then
        LOGI "vray-panel Autostart Cancelled successfully"
    else
        LOGE "vray-panel Failed to cancel autostart"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u vray-panel.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_shell() {
    curl -L --insecure -z /usr/bin/vray-panel -o /usr/bin/vray-panel https://github.com/IlyadKruger/vray-panel/raw/main/vray-panel.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "Failed to download script，Please check whether the machine can connect Github"
        before_show_menu
    else
        chmod +x /usr/bin/vray-panel
        LOGI "Upgrade script succeeded，Please rerun the script" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/vray-panel.service ]]; then
        return 2
    fi
    temp=$(systemctl status vray-panel | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled vray-panel)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "Panel installed，Please do not reinstall"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "Please install the panel first"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "Panel state: ${green}Running${plain}"
        show_enable_status
        ;;
    1)
        echo -e "Panel state: ${yellow}Not Running${plain}"
        show_enable_status
        ;;
    2)
        echo -e "Panel state: ${red}Not Installed${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Start automatically: ${green}Yes${plain}"
    else
        echo -e "Start automatically: ${red}No${plain}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "xray state: ${green}Running${plain}"
    else
        echo -e "xray state: ${red}Not Running${plain}"
    fi
}

install_acme() {
    cd ~
    LOGI "install acme..."
    curl https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "install acme failed"
        return 1
    else
        LOGI "install acme succeed"
    fi
    return 0
}

ssl_cert_issue_main() {
    echo -e "${green}\t1.${plain} Get SSL"
    echo -e "${green}\t2.${plain} Revoke"
    echo -e "${green}\t3.${plain} Force Renew"
    read -p "Choose an option: " choice
    case "$choice" in
        1) ssl_cert_issue ;;
        2) 
            local domain=""
            read -p "Please enter your domain name to revoke the certificate: " domain
            ~/.acme.sh/acme.sh --revoke -d ${domain}
            LOGI "Certificate revoked"
            ;;
        3)
            local domain=""
            read -p "Please enter your domain name to forcefully renew an SSL certificate: " domain
            ~/.acme.sh/acme.sh --renew -d ${domain} --force ;;
        *) echo "Invalid choice" ;;
    esac
}

ssl_cert_issue() {
    # check for acme.sh first
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "acme.sh could not be found. we will install it"
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "install acme failed, please check logs"
            exit 1
        fi
    fi
    # install socat second
    case "${release}" in
        ubuntu|debian)
            apt update && apt install socat -y ;;
        centos)
            yum -y update && yum -y install socat ;;
        fedora)
            dnf -y update && dnf -y install socat ;;
        *)
            echo -e "${red}Unsupported operating system. Please check the script and install the necessary packages manually.${plain}\n"
            exit 1 ;;
    esac
    if [ $? -ne 0 ]; then
        LOGE "install socat failed, please check logs"
        exit 1
    else
        LOGI "install socat succeed..."
    fi

    # get the domain here,and we need verify it
    local domain=""
    read -p "Please enter your domain name:" domain
    LOGD "your domain is:${domain},check it..."
    # here we need to judge whether there exists cert already
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')

    if [ ${currentCert} == ${domain} ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "system already has certs here,can not issue again,current certs details:"
        LOGI "$certInfo"
        exit 1
    else
        LOGI "your domain is ready for issuing cert now..."
    fi

    # create a directory for install cert
    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    # get needed port here
    local WebPort=80
    read -p "please choose which port do you use,default will be 80 port:" WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "your input ${WebPort} is invalid,will use default port"
    fi
    LOGI "will use port:${WebPort} to issue certs,please make sure this port is open..."
    # NOTE:This should be handled by user
    # open the port and kill the occupied progress
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --standalone --httpport ${WebPort}
    if [ $? -ne 0 ]; then
        LOGE "issue certs failed,please check logs"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGE "issue certs succeed,installing certs..."
    fi
    # install cert
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem

    if [ $? -ne 0 ]; then
        LOGE "install certs failed,exit"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "install certs succeed,enable auto renew..."
    fi

    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "auto renew failed, certs details:"
        ls -lah cert/*
        chmod 755 $certPath/*
        exit 1
    else
        LOGI "auto renew succeed, certs details:"
        ls -lah cert/*
        chmod 755 $certPath/*
    fi
}

ssl_cert_issue_CF() {
    echo -E ""
    LOGD "******Instructions for use******"
    LOGI "This Acme script requires the following data:"
    LOGI "1.Cloudflare Registered e-mail"
    LOGI "2.Cloudflare Global API Key"
    LOGI "3.The domain name that has been resolved dns to the current server by Cloudflare"
    LOGI "4.The script applies for a certificate. The default installation path is /root/cert "
    confirm "Confirmed?[y/n]" "y"
    if [ $? -eq 0 ]; then
        # check for acme.sh first
        if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
            echo "acme.sh could not be found. we will install it"
            install_acme
            if [ $? -ne 0 ]; then
                LOGE "install acme failed, please check logs"
                exit 1
            fi
        fi
        CF_Domain=""
        CF_GlobalKey=""
        CF_AccountEmail=""
        certPath=/root/cert
        if [ ! -d "$certPath" ]; then
            mkdir $certPath
        else
            rm -rf $certPath
            mkdir $certPath
        fi
        LOGD "Please set a domain name:"
        read -p "Input your domain here:" CF_Domain
        LOGD "Your domain name is set to:${CF_Domain}"
        LOGD "Please set the API key:"
        read -p "Input your key here:" CF_GlobalKey
        LOGD "Your API key is:${CF_GlobalKey}"
        LOGD "Please set up registered email:"
        read -p "Input your email here:" CF_AccountEmail
        LOGD "Your registered email address is:${CF_AccountEmail}"
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "Default CA, Lets'Encrypt fail, script exiting..."
            exit 1
        fi
        export CF_Key="${CF_GlobalKey}"
        export CF_Email=${CF_AccountEmail}
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log
        if [ $? -ne 0 ]; then
            LOGE "Certificate issuance failed, script exiting..."
            exit 1
        else
            LOGI "Certificate issued Successfully, Installing..."
        fi
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} --ca-file /root/cert/ca.cer \
        --cert-file /root/cert/${CF_Domain}.cer --key-file /root/cert/${CF_Domain}.key \
        --fullchain-file /root/cert/fullchain.cer
        if [ $? -ne 0 ]; then
            LOGE "Certificate installation failed, script exiting..."
            exit 1
        else
            LOGI "Certificate installed Successfully,Turning on automatic updates..."
        fi
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "Auto update setup Failed, script exiting..."
            ls -lah cert
            chmod 755 $certPath
            exit 1
        else
            LOGI "The certificate is installed and auto-renewal is turned on, Specific information is as follows"
            ls -lah cert
            chmod 755 $certPath
        fi
    else
        show_menu
    fi
}

firewall_menu() {
    echo -e "${green}\t1.${plain} Install Firewall & open ports"
    echo -e "${green}\t2.${plain} Allowed List"
    echo -e "${green}\t3.${plain} Delete Ports from List"
    echo -e "${green}\t4.${plain} Disable Firewall"
    echo -e "${green}\t0.${plain} Back to Main Menu"
    read -p "Choose an option: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        open_ports
        ;;
    2)
        sudo ufw status
        ;;
    3)
        delete_ports
        ;;
    4)
        sudo ufw disable
        ;;
    *) echo "Invalid choice" ;;
    esac
}

open_ports() {
    if ! command -v ufw &>/dev/null; then
        echo "ufw firewall is not installed. Installing now..."
        apt-get update
        apt-get install -y ufw
    else
        echo "ufw firewall is already installed"
    fi

    # Check if the firewall is inactive
    if ufw status | grep -q "Status: active"; then
        echo "firewall is already active"
    else
        # Open the necessary ports
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw allow 54321/tcp

        # Enable the firewall
        ufw --force enable
    fi

    # Prompt the user to enter a list of ports
    read -p "Enter the ports you want to open (e.g. 80,443,2053 or range 400-500): " ports

    # Check if the input is valid
    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "Error: Invalid input. Please enter a comma-separated list of ports or a range of ports (e.g. 80,443,2053 or 400-500)." >&2
        exit 1
    fi

    # Open the specified ports using ufw
    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            # Split the range into start and end ports
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            # Loop through the range and open each port
            for ((i = start_port; i <= end_port; i++)); do
                ufw allow $i
            done
        else
            ufw allow "$port"
        fi
    done

    # Confirm that the ports are open
    ufw status | grep $ports
}

delete_ports() {
    # Prompt the user to enter the ports they want to delete
    read -p "Enter the ports you want to delete (e.g. 80,443,2053 or range 400-500): " ports

    # Check if the input is valid
    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "Error: Invalid input. Please enter a comma-separated list of ports or a range of ports (e.g. 80,443,2053 or 400-500)." >&2
        exit 1
    fi

    # Delete the specified ports using ufw
    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            # Split the range into start and end ports
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            # Loop through the range and delete each port
            for ((i = start_port; i <= end_port; i++)); do
                ufw delete allow $i
            done
        else
            ufw delete allow "$port"
        fi
    done

    # Confirm that the ports are deleted
    echo "Deleted the specified ports:"
    ufw status | grep $ports
}

bbr_menu() {
    echo -e "${green}\t1.${plain} Enable BBR"
    echo -e "${green}\t2.${plain} Disable BBR"
    echo -e "${green}\t0.${plain} Back to Main Menu"
    read -p "Choose an option: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        enable_bbr
        ;;
    2)
        disable_bbr
        ;;
    *) echo "Invalid choice" ;;
    esac
}

disable_bbr() {

    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${yellow}BBR is not currently enabled.${plain}"
        exit 0
    fi

    # Replace BBR with CUBIC configurations
    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf

    # Apply changes
    sysctl -p

    # Verify that BBR is replaced with CUBIC
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "cubic" ]]; then
        echo -e "${green}BBR has been replaced with CUBIC successfully.${plain}"
    else
        echo -e "${red}Failed to replace BBR with CUBIC. Please check your system configuration.${plain}"
    fi
}

enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR is already enabled!${plain}"
        exit 0
    fi

    # Check the OS and install necessary packages
    case "${release}" in
    ubuntu | debian)
        apt-get update && apt-get install -yqq --no-install-recommends ca-certificates
        ;;
    centos | almalinux | rocky)
        yum -y update && yum -y install ca-certificates
        ;;
    fedora)
        dnf -y update && dnf -y install ca-certificates
        ;;
    *)
        echo -e "${red}Unsupported operating system. Please check the script and install the necessary packages manually.${plain}\n"
        exit 1
        ;;
    esac

    # Enable BBR
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf

    # Apply changes
    sysctl -p

    # Verify that BBR is enabled
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${green}BBR has been enabled successfully.${plain}"
    else
        echo -e "${red}Failed to enable BBR. Please check your system configuration.${plain}"
    fi
}

update_geo() {
    cd /usr/local/vray-panel/bin
    echo -e "${green}\t1.${plain} Update Geofiles [Recommended choice] "
    echo -e "${green}\t2.${plain} Download from optional jsDelivr CDN "
    echo -e "${green}\t0.${plain} Back To Main Menu "
    read -p "Select: " select

    case "$select" in
        0)
            show_menu
            ;;

        1)
            curl -L --insecure "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" && echo -e "${green}Success${plain}\n" || echo -e "${red}Failure${plain}\n"
            curl -L --insecure "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" && echo -e "${green}Success${plain}\n" || echo -e "${red}Failure${plain}\n"
            curl -L --insecure "https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat" -O /tmp/wget && mv /tmp/wget geoip_IR.dat && echo -e "${green}Success${plain}\n" || echo -e "${red}Failure${plain}\n"
            curl -L --insecure "https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat" -O /tmp/wget && mv /tmp/wget geosite_IR.dat && echo -e "${green}Success${plain}\n" || echo -e "${red}Failure${plain}\n"
            echo -e "${green}Files are updated.${plain}"
            confirm_restart
            ;;

        2)
            curl -L --insecure -N "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat" && echo -e "${green}Success${plain}\n" || echo -e "${red}Failure${plain}\n"
            curl -L --insecure -N "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat" && echo -e "${green}Success${plain}\n" || echo -e "${red}Failure${plain}\n"
            curl -L --insecure "https://cdn.jsdelivr.net/gh/chocolate4u/Iran-v2ray-rules@release/geoip.dat" -O /tmp/wget && mv /tmp/wget geoip_IR.dat && echo -e "${green}Success${plain}\n" || echo -e "${red}Failure${plain}\n"
            curl -L --insecure "https://cdn.jsdelivr.net/gh/chocolate4u/Iran-v2ray-rules@release/geosite.dat" -O /tmp/wget && mv /tmp/wget geosite_IR.dat && echo -e "${green}Success${plain}\n" || echo -e "${red}Failure${plain}\n"
            echo -e "${green}Files are updated.${plain}"
            confirm_restart
            ;;

        *)
            LOGE "Please enter a correct number [0-2]\n"
            update_geo
            ;;
    esac
}

run_speedtest() {
    # Check if Speedtest is already installed
    if ! command -v speedtest &>/dev/null; then
        # If not installed, install it
        local pkg_manager=""
        local speedtest_install_script=""

        if command -v dnf &>/dev/null; then
            pkg_manager="dnf"
            speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
        elif command -v yum &>/dev/null; then
            pkg_manager="yum"
            speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
        elif command -v apt-get &>/dev/null; then
            pkg_manager="apt-get"
            speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
        elif command -v apt &>/dev/null; then
            pkg_manager="apt"
            speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
        fi

        if [[ -z $pkg_manager ]]; then
            echo "Error: Package manager not found. You may need to install Speedtest manually."
            return 1
        else
            curl -s $speedtest_install_script | bash
            $pkg_manager install -y speedtest
        fi
    fi

    # Run Speedtest
    speedtest
}

show_usage() {
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

show_menu() {
    echo -e "
  ${green}vray-panel Admin Management Script ${plain}
————————————————
  ${green}0.${plain} Exit 
————————————————
  ${green}1.${plain} Install
  ${green}2.${plain} Update
  ${green}3.${plain} Custom Version
  ${green}4.${plain} Uninstall
————————————————
  ${green}5.${plain} Reset Username and Password
  ${green}6.${plain} Reset Panel Settings
  ${green}7.${plain} Set Panel Port
  ${green}8.${plain} View Panel Settings
————————————————
  ${green}9.${plain} Start
  ${green}10.${plain} Stop
  ${green}11.${plain} Restart
  ${green}12.${plain} Check State
  ${green}13.${plain} Check Logs
————————————————
  ${green}14.${plain} Enable Autostart
  ${green}15.${plain} Disable Autostart
————————————————
  ${green}16.${plain} SSL Certificate Management
  ${green}17.${plain} Cloudflare SSL Certificate
  ${green}18.${plain} Firewall Management
————————————————
  ${green}19.${plain} Enable or Disable BBR
  ${green}20.${plain} Update Geo Files
  ${green}21.${plain} Speedtest by Ookla
 "
    show_status
    echo && read -p "Please enter your selection [0-21]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && custom_version
        ;;
    4)
        check_install && uninstall
        ;;
    5)
        check_install && reset_user
        ;;
    6)
        check_install && reset_config
        ;;
    7)
        check_install && set_port
        ;;
    8)
        check_install && check_config
        ;;
    9)
        check_install && start
        ;;
    10)
        check_install && stop
        ;;
    11)
        check_install && restart
        ;;
    12)
        check_install && status
        ;;
    13)
        check_install && show_log
        ;;
    14)
        check_install && enable
        ;;
    15)
        check_install && disable
        ;;
    16)
        ssl_cert_issue_main
        ;;
    17)
        ssl_cert_issue_CF
        ;;
    18)
        firewall_menu
        ;;
    19)
        bbr_menu
        ;;
    20)
        update_geo
        ;;
    21)
        run_speedtest
        ;;
    *)
        LOGE "Please enter the correct number [0-21]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "log")
        check_install 0 && show_log 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
