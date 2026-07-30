#!/bin/bash
# 中文版由 localization/apply_zh_cn.py 基于 MHSanaei/3x-ui 自动生成。

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

xui_folder="${XUI_MAIN_FOLDER:=/usr/local/x-ui}"
xui_service="${XUI_SERVICE:=/etc/systemd/system}"

# Don't edit this config
b_source="${BASH_SOURCE[0]}"
while [ -h "$b_source" ]; do
    b_dir="$(cd -P "$(dirname "$b_source")" > /dev/null 2>&1 && pwd || pwd -P)"
    b_source="$(readlink "$b_source")"
    [[ $b_source != /* ]] && b_source="$b_dir/$b_source"
done
cur_dir="$(cd -P "$(dirname "$b_source")" > /dev/null 2>&1 && pwd || pwd -P)"
script_name=$(basename "$0")

# Check command exist function
_command_exists() {
    type "$1" &> /dev/null
}

# Fail, log and exit script function
_fail() {
    local msg=${1}
    echo -e "${red}${msg}${plain}"
    exit 2
}

# Records this run's outcome for the panel's web updater to poll, since it
# launches this script detached and has no other way to learn whether it
# finished. Written to a fixed path outside XUI_MAIN_FOLDER so it survives
# the update regardless of what happens to that folder. The EXIT trap below
# covers every exit path in this file, including the bare `exit 1`/`exit 2`
# calls that don't go through _fail.
xui_update_run_id="${XUI_UPDATE_RUN_ID:-0}"
[[ "${xui_update_run_id}" =~ ^[0-9]+$ ]] || xui_update_run_id="0"
xui_update_status_file="${XUI_UPDATE_STATUS_FILE:-/etc/x-ui/update-status.json}"

_write_update_status() {
    local state="$1"
    local exit_code="$2"
    local status_dir
    status_dir="$(dirname "${xui_update_status_file}")"
    mkdir -p "${status_dir}" > /dev/null 2>&1
    local tmp_file="${xui_update_status_file}.tmp.$$"
    printf '{"runId":"%s","state":"%s","exitCode":%s,"finishedAt":%s}\n' \
        "${xui_update_run_id}" "${state}" "${exit_code}" "$(date +%s)" > "${tmp_file}" 2> /dev/null
    mv -f "${tmp_file}" "${xui_update_status_file}" > /dev/null 2>&1
}

_report_update_exit() {
    local code=$?
    if [[ "${code}" -eq 0 ]]; then
        _write_update_status "success" "0"
    else
        _write_update_status "failed" "${code}"
    fi
}
trap _report_update_exit EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# check root
[[ $EUID -ne 0 ]] && _fail "FATAL ERROR: Please run this script with root privilege."

if _command_exists curl; then
    curl_bin=$(which curl)
else
    _fail "ERROR: Command 'curl' not found."
fi

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    _fail "Failed to check the system OS, please contact the author!"
fi
echo "操作系统发行版： $release"

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${red}不支持的 CPU 架构！${plain}" && rm -f "${cur_dir}/${script_name}" > /dev/null 2>&1 && exit 2 ;;
    esac
}

echo "架构： $(arch)"

# Simple helpers
is_ipv4() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0 || return 1
}
is_ipv6() {
    [[ "$1" =~ : ]] && return 0 || return 1
}
is_ip() {
    is_ipv4 "$1" || is_ipv6 "$1"
}
is_domain() {
    [[ "$1" =~ ^([A-Za-z0-9](-*[A-Za-z0-9])*\.)+(xn--[a-z0-9]{2,}|[A-Za-z]{2,})$ ]] && return 0 || return 1
}

# acme.sh's standalone server binds IPv4 by default; --listen-v6 makes it
# v6-only, which breaks HTTP-01 validation when the domain's A record points
# at this host's IPv4 (#4994). Only force IPv6 when the host has no global
# IPv4 address at all.
acme_listen_flag() {
    if ip -4 addr show scope global 2> /dev/null | grep -q "inet "; then
        echo ""
    else
        echo "--listen-v6"
    fi
}

# Port helpers
is_port_in_use() {
    local port="$1"
    if command -v ss > /dev/null 2>&1; then
        ss -ltn 2> /dev/null | awk -v p=":${port}$" '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v netstat > /dev/null 2>&1; then
        netstat -lnt 2> /dev/null | awk -v p=":${port} " '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v lsof > /dev/null 2>&1; then
        lsof -nP -iTCP:${port} -sTCP:LISTEN > /dev/null 2>&1 && return 0
    fi
    return 1
}

gen_random_string() {
    local length="$1"
    openssl rand -base64 $((length * 2)) \
        | tr -dc 'a-zA-Z0-9' \
        | head -c "$length"
}

xui_env_file_path() {
    case "${release}" in
        ubuntu | debian | armbian)
            echo "/etc/默认/x-ui"
            ;;
        arch | manjaro | parch | alpine)
            echo "/etc/conf.d/x-ui"
            ;;
        *)
            echo "/etc/sysconfig/x-ui"
            ;;
    esac
}

load_xui_env() {
    local env_file
    env_file="$(xui_env_file_path)"
    if [[ -r "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    fi
}

install_base() {
    echo -e "${green}正在更新 and install dependency packages...${plain}"
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update > /dev/null 2>&1 && apt-get install -y -q cron curl tar tzdata socat openssl > /dev/null 2>&1
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf makecache -y > /dev/null 2>&1 && dnf install -y -q cronie curl tar tzdata socat openssl > /dev/null 2>&1
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum makecache -y > /dev/null 2>&1 && yum install -y -q cronie curl tar tzdata socat openssl > /dev/null 2>&1
            else
                dnf makecache -y > /dev/null 2>&1 && dnf install -y -q cronie curl tar tzdata socat openssl > /dev/null 2>&1
            fi
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm cronie curl tar tzdata socat openssl > /dev/null 2>&1
            ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper refresh > /dev/null 2>&1 && zypper -q install -y cron curl tar timezone socat openssl > /dev/null 2>&1
            ;;
        alpine)
            apk update > /dev/null 2>&1 && apk add dcron curl tar tzdata socat openssl > /dev/null 2>&1
            ;;
        *)
            apt-get update > /dev/null 2>&1 && apt install -y -q cron curl tar tzdata socat openssl > /dev/null 2>&1
            ;;
    esac
}

install_acme() {
    echo -e "${green}正在安装 acme.sh for SSL 证书 management...${plain}"
    cd ~ || return 1
    curl -s https://get.acme.sh | sh > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${red}失败 to install acme.sh${plain}"
        return 1
    else
        echo -e "${green}acme.sh 已安装 成功${plain}"
    fi
    return 0
}

setup_ssl_certificate() {
    local domain="$1"
    local server_ip="$2"
    local existing_port="$3"
    local existing_webBasePath="$4"

    echo -e "${green}Setting up SSL 证书...${plain}"

    # Check if acme.sh is installed
    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            echo -e "${yellow}失败 to install acme.sh, skipping SSL setup${plain}"
            return 1
        fi
    fi

    # Create certificate directory
    local certPath="/root/cert/${domain}"
    mkdir -p "$certPath"

    # Issue certificate
    echo -e "${green}Issuing SSL 证书 for ${domain}...${plain}"
    echo -e "${yellow}注意： 端口 80 must be open and accessible from the internet${plain}"

    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force > /dev/null 2>&1
    ~/.acme.sh/acme.sh --issue -d ${domain} $(acme_listen_flag) --standalone --httpport 80 --force

    if [ $? -ne 0 ]; then
        echo -e "${yellow}失败 to issue 证书 for ${domain}${plain}"
        echo -e "${yellow}请 ensure 端口 80 is open and 重试 later with: x-ui${plain}"
        rm -rf ~/.acme.sh/${domain} 2> /dev/null
        rm -rf "$certPath" 2> /dev/null
        return 1
    fi

    # Install certificate
    ~/.acme.sh/acme.sh --installcert --force -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem \
        --reloadcmd "systemctl restart x-ui" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${yellow}失败 to install 证书${plain}"
        return 1
    fi

    # Enable auto-renew
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade > /dev/null 2>&1
    chmod 600 $certPath/privkey.pem 2> /dev/null
    chmod 644 $certPath/fullchain.pem 2> /dev/null

    # Set certificate for panel
    local webCertFile="/root/cert/${domain}/fullchain.pem"
    local webKeyFile="/root/cert/${domain}/privkey.pem"

    if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
        ${xui_folder}/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile" > /dev/null 2>&1
        echo -e "${green}SSL 证书 已安装 and configured 成功!${plain}"
        return 0
    else
        echo -e "${yellow}证书 files 未找到${plain}"
        return 1
    fi
}

# Issue Let's Encrypt IP certificate with shortlived profile (~6 days validity)
# Requires acme.sh and port 80 open for HTTP-01 challenge
setup_ip_certificate() {
    local ipv4="$1"
    local ipv6="$2" # optional

    echo -e "${green}Setting up Let's Encrypt IP 证书 (shortlived profile)...${plain}"
    echo -e "${yellow}注意： IP certificates are valid for ~6 days and will auto-renew.${plain}"
    echo -e "${yellow}默认 listener is 端口 80. If you choose another 端口, ensure external 端口 80 forwards to it.${plain}"

    # Check for acme.sh
    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            echo -e "${red}失败 to install acme.sh${plain}"
            return 1
        fi
    fi

    # Validate IP address
    if [[ -z "$ipv4" ]]; then
        echo -e "${red}必须提供 IPv4 地址${plain}"
        return 1
    fi

    if ! is_ipv4 "$ipv4"; then
        echo -e "${red}无效 IPv4 address: $ipv4${plain}"
        return 1
    fi

    # Create certificate directory
    local certDir="/root/cert/ip"
    mkdir -p "$certDir"

    # Build domain arguments
    local domain_args="-d ${ipv4}"
    if [[ -n "$ipv6" ]] && is_ipv6 "$ipv6"; then
        domain_args="${domain_args} -d ${ipv6}"
        echo -e "${green}同时包含 IPv6 地址： ${ipv6}${plain}"
    fi

    # Set reload command for auto-renewal (add || true so it doesn't fail if service stopped)
    local reloadCmd="systemctl restart x-ui 2>/dev/null || rc-service x-ui restart 2>/dev/null || true"

    # Choose port for HTTP-01 listener (default 80, prompt override)
    local WebPort=""
    read -rp "端口 to use for ACME HTTP-01 listener (默认 80): " WebPort
    WebPort="${WebPort:-80}"
    if ! [[ "${WebPort}" =~ ^[0-9]+$ ]] || ((WebPort < 1 || WebPort > 65535)); then
        echo -e "${red}无效 端口 provided. Falling back to 80.${plain}"
        WebPort=80
    fi
    echo -e "${green}Using 端口 ${WebPort} for standalone validation.${plain}"
    if [[ "${WebPort}" -ne 80 ]]; then
        echo -e "${yellow}Reminder: Let's Encrypt still connects on 端口 80; forward external 端口 80 to ${WebPort}.${plain}"
    fi

    # Ensure chosen port is available
    while true; do
        if is_port_in_use "${WebPort}"; then
            echo -e "${yellow}端口 ${WebPort} is currently in use.${plain}"

            local alt_port=""
            read -rp "输入 another 端口 for acme.sh standalone listener (留空 to abort): " alt_port
            alt_port="${alt_port// /}"
            if [[ -z "${alt_port}" ]]; then
                echo -e "${red}端口 ${WebPort} is busy; cannot proceed.${plain}"
                return 1
            fi
            if ! [[ "${alt_port}" =~ ^[0-9]+$ ]] || ((alt_port < 1 || alt_port > 65535)); then
                echo -e "${red}无效 端口 provided.${plain}"
                return 1
            fi
            WebPort="${alt_port}"
            continue
        else
            echo -e "${green}端口 ${WebPort} is free and ready for standalone validation.${plain}"
            break
        fi
    done

    # Issue certificate with shortlived profile
    echo -e "${green}Issuing IP 证书 for ${ipv4}...${plain}"
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force > /dev/null 2>&1

    ~/.acme.sh/acme.sh --issue \
        ${domain_args} \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport ${WebPort} \
        --force

    if [ $? -ne 0 ]; then
        echo -e "${red}失败 to issue IP 证书${plain}"
        echo -e "${yellow}请 ensure 端口 ${WebPort} is reachable (or forwarded from external 端口 80)${plain}"
        # Cleanup acme.sh data for both IPv4 and IPv6 if specified
        rm -rf ~/.acme.sh/${ipv4} 2> /dev/null
        [[ -n "$ipv6" ]] && rm -rf ~/.acme.sh/${ipv6} 2> /dev/null
        rm -rf ${certDir} 2> /dev/null
        return 1
    fi

    echo -e "${green}证书 issued 成功, installing...${plain}"

    # Install certificate
    # Note: acme.sh may report "Reload error" and exit non-zero if reloadcmd fails,
    # but the cert files are still installed. We check for files instead of exit code.
    ~/.acme.sh/acme.sh --installcert --force -d ${ipv4} \
        --key-file "${certDir}/privkey.pem" \
        --fullchain-file "${certDir}/fullchain.pem" \
        --reloadcmd "${reloadCmd}" 2>&1 || true

    # Verify certificate files exist (don't rely on exit code - reloadcmd failure causes non-zero)
    if [[ ! -f "${certDir}/fullchain.pem" || ! -f "${certDir}/privkey.pem" ]]; then
        echo -e "${red}证书 files 未找到 after 安装${plain}"
        # Cleanup acme.sh data for both IPv4 and IPv6 if specified
        rm -rf ~/.acme.sh/${ipv4} 2> /dev/null
        [[ -n "$ipv6" ]] && rm -rf ~/.acme.sh/${ipv6} 2> /dev/null
        rm -rf ${certDir} 2> /dev/null
        return 1
    fi

    echo -e "${green}证书 files 已安装 成功${plain}"

    # Enable auto-upgrade for acme.sh (ensures cron job runs)
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade > /dev/null 2>&1

    chmod 600 ${certDir}/privkey.pem 2> /dev/null
    chmod 644 ${certDir}/fullchain.pem 2> /dev/null

    # Configure panel to use the certificate
    echo -e "${green}Setting 证书 paths for the panel...${plain}"
    ${xui_folder}/x-ui cert -webCert "${certDir}/fullchain.pem" -webCertKey "${certDir}/privkey.pem"
    if [ $? -ne 0 ]; then
        echo -e "${yellow}警告： Could not set 证书 paths automatically.${plain}"
        echo -e "${yellow}You may need to set them manually in the panel settings.${plain}"
        echo -e "${yellow}Cert path: ${certDir}/fullchain.pem${plain}"
        echo -e "${yellow}Key path: ${certDir}/privkey.pem${plain}"
    else
        echo -e "${green}证书 paths set 成功!${plain}"
    fi

    echo -e "${green}IP 证书 已安装 and configured 成功!${plain}"
    echo -e "${green}证书 valid for ~6 days, auto-renews via acme.sh cron job.${plain}"
    echo -e "${yellow}Panel will automatically restart after each renewal.${plain}"
    return 0
}

# Comprehensive manual SSL certificate issuance via acme.sh
ssl_cert_issue() {
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep 'webBasePath:' | awk -F': ' '{print $2}' | tr -d '[:space:]' | sed 's#^/##')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep 'port:' | awk -F': ' '{print $2}' | tr -d '[:space:]')

    # check for acme.sh first
    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        echo "acme.sh could not be found. 正在安装 now..."
        cd ~ || return 1
        curl -s https://get.acme.sh | sh
        if [ $? -ne 0 ]; then
            echo -e "${red}失败 to install acme.sh${plain}"
            return 1
        else
            echo -e "${green}acme.sh 已安装 成功${plain}"
        fi
    fi

    # get the domain here, and we need to verify it
    local domain=""
    while true; do
        read -rp "请 enter your 域名 name: " 域名
        domain="${domain// /}" # Trim whitespace

        if [[ -z "$domain" ]]; then
            echo -e "${red}域名 name cannot be empty. 请 重试.${plain}"
            continue
        fi

        if ! is_domain "$domain"; then
            echo -e "${red}无效 域名 format: ${domain}. 请 enter a valid 域名 name.${plain}"
            continue
        fi

        break
    done
    echo -e "${green}Your 域名 is: ${domain}, checking it...${plain}"
    SSL_ISSUED_DOMAIN="${domain}"

    # detect existing certificate and reuse it if present
    local cert_exists=0
    if ~/.acme.sh/acme.sh --list 2> /dev/null | awk '{print $1}' | grep -Fxq "${domain}"; then
        cert_exists=1
        local certInfo=$(~/.acme.sh/acme.sh --list 2> /dev/null | grep -F "${domain}")
        echo -e "${yellow}Existing 证书 found for ${domain}, will reuse it.${plain}"
        [[ -n "${certInfo}" ]] && echo "$certInfo"
    else
        echo -e "${green}Your 域名 is ready for issuing certificates now...${plain}"
    fi

    # create a directory for the certificate
    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    # get the port number for the standalone server
    local WebPort=80
    read -rp "请 choose which 端口 to use (默认 is 80): " WebPort
    if [[ -z ${WebPort} ]]; then
        WebPort=80
    elif [[ ! ${WebPort} =~ ^[1-9][0-9]*$ || ${WebPort} -gt 65535 ]]; then
        echo -e "${yellow}Your input ${WebPort} is invalid, will use 默认 端口 80.${plain}"
        WebPort=80
    fi
    echo -e "${green}Will use 端口: ${WebPort} to issue certificates. 请 make sure this 端口 is open.${plain}"

    # Stop panel temporarily
    echo -e "${yellow}正在临时停止面板……${plain}"
    systemctl stop x-ui 2> /dev/null || rc-service x-ui stop 2> /dev/null

    if [[ ${cert_exists} -eq 0 ]]; then
        # issue the certificate
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force
        ~/.acme.sh/acme.sh --issue -d ${domain} $(acme_listen_flag) --standalone --httpport ${WebPort} --force
        if [ $? -ne 0 ]; then
            echo -e "${red}Issuing 证书 失败, please check logs.${plain}"
            rm -rf ~/.acme.sh/${domain}
            systemctl start x-ui 2> /dev/null || rc-service x-ui start 2> /dev/null
            return 1
        else
            echo -e "${green}Issuing 证书 succeeded, installing certificates...${plain}"
        fi
    else
        echo -e "${green}Using existing 证书, installing certificates...${plain}"
    fi

    # Setup reload command
    reloadCmd="systemctl restart x-ui || rc-service x-ui restart"
    echo -e "${green}默认 --reloadcmd for ACME is: ${yellow}systemctl restart x-ui || rc-service x-ui restart${plain}"
    echo -e "${green}This command will run on every 证书 issue and renew.${plain}"
    read -rp "是否修改 ACME 的 --reloadcmd？ (y/n): " setReloadcmd
    if [[ "$setReloadcmd" == "y" || "$setReloadcmd" == "Y" ]]; then
        echo -e "\n${green}\t1.${plain} Preset: systemctl reload nginx ; systemctl restart x-ui"
        echo -e "${green}\t2.${plain} 输入自定义命令"
        echo -e "${green}\t0.${plain} Keep 默认 reloadcmd"
        read -rp "请选择： " choice
        case "$choice" in
            1)
                echo -e "${green}Reloadcmd is: systemctl reload nginx ; systemctl restart x-ui${plain}"
                reloadCmd="systemctl reload nginx ; systemctl restart x-ui"
                ;;
            2)
                echo -e "${yellow}建议将 x-ui restart 放在命令末尾${plain}"
                read -rp "请 enter your custom reloadcmd: " reloadCmd
                echo -e "${green}Reloadcmd is: ${reloadCmd}${plain}"
                ;;
            *)
                echo -e "${green}Keeping 默认 reloadcmd${plain}"
                ;;
        esac
    fi

    # install the certificate
    local installOutput=""
    installOutput=$(~/.acme.sh/acme.sh --installcert --force -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem --reloadcmd "${reloadCmd}" 2>&1)
    local installRc=$?
    echo "${installOutput}"

    local installWroteFiles=0
    if echo "${installOutput}" | grep -q "正在安装 key to:" && echo "${installOutput}" | grep -q "正在安装 full chain to:"; then
        installWroteFiles=1
    fi

    if [[ -f "/root/cert/${domain}/privkey.pem" && -f "/root/cert/${domain}/fullchain.pem" && (${installRc} -eq 0 || ${installWroteFiles} -eq 1) ]]; then
        echo -e "${green}正在安装 证书 succeeded, enabling auto renew...${plain}"
    else
        echo -e "${red}正在安装 证书 失败, exiting.${plain}"
        if [[ ${cert_exists} -eq 0 ]]; then
            rm -rf ~/.acme.sh/${domain}
        fi
        systemctl start x-ui 2> /dev/null || rc-service x-ui start 2> /dev/null
        return 1
    fi

    # enable auto-renew
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        echo -e "${yellow}Auto renew setup had issues, 证书 details:${plain}"
        ls -lah /root/cert/${domain}/
        chmod 600 $certPath/privkey.pem
        chmod 644 $certPath/fullchain.pem
    else
        echo -e "${green}Auto renew succeeded, 证书 details:${plain}"
        ls -lah /root/cert/${domain}/
        chmod 600 $certPath/privkey.pem
        chmod 644 $certPath/fullchain.pem
    fi

    # Restart panel
    systemctl start x-ui 2> /dev/null || rc-service x-ui start 2> /dev/null

    # Prompt user to set panel paths after successful certificate installation
    read -rp "Would you like to set this 证书 for the panel? (y/n): " setPanel
    if [[ "$setPanel" == "y" || "$setPanel" == "Y" ]]; then
        local webCertFile="/root/cert/${domain}/fullchain.pem"
        local webKeyFile="/root/cert/${domain}/privkey.pem"

        if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
            ${xui_folder}/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
            echo -e "${green}证书 paths set for the panel${plain}"
            echo -e "${green}证书 File: $webCertFile${plain}"
            echo -e "${green}私钥文件： $webKeyFile${plain}"
            echo ""
            echo -e "${green}访问地址： https://${domain}:${existing_port}/${existing_webBasePath}${plain}"
            echo -e "${yellow}Panel will restart to apply SSL 证书...${plain}"
            systemctl restart x-ui 2> /dev/null || rc-service x-ui restart 2> /dev/null
        else
            echo -e "${red}错误： 证书 or private key file 未找到 for 域名: $domain.${plain}"
        fi
    else
        echo -e "${yellow}跳过面板路径设置。${plain}"
    fi

    return 0
}
# Unified interactive SSL setup (domain or IP)
# Sets global `SSL_HOST` to the chosen domain/IP
prompt_and_setup_ssl() {
    local panel_port="$1"
    local web_base_path="$2" # expected without leading slash
    local server_ip="$3"

    local ssl_choice=""

    echo -e "${yellow}Choose SSL 证书 setup method:${plain}"
    echo -e "${green}1.${plain} Let's Encrypt for 域名 (90-day validity, auto-renews)"
    echo -e "${green}2.${plain} 为 IP 地址申请 Let's Encrypt 证书（有效期 6 天，自动续期）"
    echo -e "${green}3.${plain} Custom SSL 证书 (Path to existing files)"
    echo -e "${green}4.${plain} 跳过 SSL（高级选项，仅限反向代理或 SSH 隧道后方）"
    echo -e "${blue}注意：${plain} Options 1 & 2 require 端口 80 open. Option 3 requires manual paths."
    echo -e "${blue}注意：${plain} Option 4 serves the panel over plain HTTP — only safe behind nginx/Caddy or an SSH tunnel."
    read -rp "请选择 (默认 2 for IP): " ssl_choice
    ssl_choice="${ssl_choice// /}" # Trim whitespace

    # Default to 2 (IP cert) if input is empty or invalid (not 1, 3 or 4)
    if [[ "$ssl_choice" != "1" && "$ssl_choice" != "3" && "$ssl_choice" != "4" ]]; then
        ssl_choice="2"
    fi

    case "$ssl_choice" in
        1)
            # User chose Let's Encrypt domain option
            echo -e "${green}Using Let's Encrypt for 域名 证书...${plain}"
            if ssl_cert_issue; then
                local cert_domain="${SSL_ISSUED_DOMAIN}"
                if [[ -z "${cert_domain}" ]]; then
                    cert_domain=$(~/.acme.sh/acme.sh --list 2> /dev/null | tail -1 | awk '{print $1}')
                fi

                if [[ -n "${cert_domain}" ]]; then
                    SSL_HOST="${cert_domain}"
                    echo -e "${green}✓ SSL 证书 configured 成功 with 域名: ${cert_domain}${plain}"
                else
                    echo -e "${yellow}SSL setup may have completed, but 域名 extraction 失败${plain}"
                    SSL_HOST="${server_ip}"
                fi
            else
                echo -e "${red}SSL 证书 setup 失败 for 域名 mode.${plain}"
                SSL_HOST="${server_ip}"
            fi
            ;;
        2)
            # User chose Let's Encrypt IP certificate option
            echo -e "${green}Using Let's Encrypt for IP 证书 (shortlived profile)...${plain}"

            # Confirm the auto-detected IP before issuing for it: with asymmetric
            # routing / multi-WAN the echo services can return a transit address.
            local ip_confirm=""
            read -rp "Is ${server_ip} the correct incoming public IPv4 address for this server? [默认 y]: " ip_confirm
            if [[ -n "$ip_confirm" && "$ip_confirm" != "y" && "$ip_confirm" != "Y" ]]; then
                server_ip=""
                while [[ -z "$server_ip" ]]; do
                    read -rp "请 enter your server's public IPv4 address: " server_ip
                    server_ip="${server_ip// /}"
                    if [[ ! "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        echo -e "${red}无效 IPv4 address. 请 重试.${plain}"
                        server_ip=""
                    fi
                done
            fi

            # Ask for optional IPv6
            local ipv6_addr=""
            read -rp "Do you have an IPv6 address to include? (留空 to skip): " ipv6_addr
            ipv6_addr="${ipv6_addr// /}" # Trim whitespace

            # Stop panel if running (port 80 needed)
            if [[ $release == "alpine" ]]; then
                rc-service x-ui stop > /dev/null 2>&1
            else
                systemctl stop x-ui > /dev/null 2>&1
            fi

            setup_ip_certificate "${server_ip}" "${ipv6_addr}"
            if [ $? -eq 0 ]; then
                SSL_HOST="${server_ip}"
                echo -e "${green}✓ Let's Encrypt IP 证书 configured 成功${plain}"
            else
                echo -e "${red}✗ IP 证书 setup 失败. 请 check 端口 80 is open.${plain}"
                SSL_HOST="${server_ip}"
            fi

            # Restart panel after SSL is configured (restart applies new cert settings)
            if [[ $release == "alpine" ]]; then
                rc-service x-ui restart > /dev/null 2>&1
            else
                systemctl restart x-ui > /dev/null 2>&1
            fi

            ;;
        3)
            # User chose Custom Paths (User Provided) option
            echo -e "${green}Using custom existing 证书...${plain}"
            local custom_cert=""
            local custom_key=""
            local custom_domain=""

            # 3.1 Request Domain to compose Panel URL later
            read -rp "请 enter 域名 name 证书 issued for: " custom_domain
            custom_domain="${custom_domain// /}" # Remove spaces

            # 3.2 Loop for Certificate Path
            while true; do
                read -rp "Input 证书 path (keywords: .crt / fullchain): " custom_cert
                # Strip quotes if present
                custom_cert=$(echo "$custom_cert" | tr -d '"' | tr -d "'")

                if [[ -f "$custom_cert" && -r "$custom_cert" && -s "$custom_cert" ]]; then
                    break
                elif [[ ! -f "$custom_cert" ]]; then
                    echo -e "${red}错误： File does not exist! Try again.${plain}"
                elif [[ ! -r "$custom_cert" ]]; then
                    echo -e "${red}错误： File exists but is not readable (check permissions)!${plain}"
                else
                    echo -e "${red}错误： File is empty!${plain}"
                fi
            done

            # 3.3 Loop for Private Key Path
            while true; do
                read -rp "Input private key path (keywords: .key / privatekey): " custom_key
                # Strip quotes if present
                custom_key=$(echo "$custom_key" | tr -d '"' | tr -d "'")

                if [[ -f "$custom_key" && -r "$custom_key" && -s "$custom_key" ]]; then
                    break
                elif [[ ! -f "$custom_key" ]]; then
                    echo -e "${red}错误： File does not exist! Try again.${plain}"
                elif [[ ! -r "$custom_key" ]]; then
                    echo -e "${red}错误： File exists but is not readable (check permissions)!${plain}"
                else
                    echo -e "${red}错误： File is empty!${plain}"
                fi
            done

            # 3.4 Apply Settings via x-ui binary
            ${xui_folder}/x-ui cert -webCert "$custom_cert" -webCertKey "$custom_key" > /dev/null 2>&1

            # Set SSL_HOST for composing Panel URL
            if [[ -n "$custom_domain" ]]; then
                SSL_HOST="$custom_domain"
            else
                SSL_HOST="${server_ip}"
            fi

            echo -e "${green}✓ Custom 证书 paths applied.${plain}"
            echo -e "${yellow}注意： You are responsible for renewing these files externally.${plain}"

            systemctl restart x-ui > /dev/null 2>&1 || rc-service x-ui restart > /dev/null 2>&1
            ;;
        4)
            echo ""
            echo -e "${red}⚠ Panel will be 已安装 WITHOUT SSL/TLS.${plain}"
            echo -e "${yellow}Login credentials and cookies will travel as plain HTTP.${plain}"
            echo -e "${yellow}Only safe when:${plain}"
            echo -e "${yellow}  • A reverse proxy (nginx, Caddy, Traefik) terminates TLS for you, or${plain}"
            echo -e "${yellow}  • You access the panel exclusively via SSH tunnel${plain}"
            echo ""

            SSL_SCHEME="http"
            SSL_HOST="${server_ip}"

            local bind_local=""
            read -rp "Bind the panel to 127.0.0.1 only? (recommended — forces SSH tunnel / reverse-proxy access) [y/N]: " bind_local
            if [[ "$bind_local" == "y" || "$bind_local" == "Y" ]]; then
                ${xui_folder}/x-ui setting -listenIP "127.0.0.1" > /dev/null 2>&1
                SSL_HOST="127.0.0.1"
                echo -e "${green}✓ Panel bound to 127.0.0.1 only. It is now unreachable from the public internet.${plain}"
                echo ""
                echo -e "${green}SSH 端口 Forwarding — open the panel from your local machine via:${plain}"
                echo -e "  标准 SSH 命令："
                echo -e "  ${yellow}ssh -L 2222:127.0.0.1:${panel_port} root@${server_ip}${plain}"
                echo -e "  If using an SSH key:"
                echo -e "  ${yellow}ssh -i <sshkeypath> -L 2222:127.0.0.1:${panel_port} root@${server_ip}${plain}"
                echo -e "  Then open in your browser:"
                echo -e "  ${yellow}http://localhost:2222/${web_base_path}${plain}"
                echo ""
                echo -e "${yellow}Alternative: point a reverse proxy (nginx/Caddy) at 127.0.0.1:${panel_port} and let it terminate TLS.${plain}"
            else
                echo -e "${yellow}Panel will listen on all interfaces over plain HTTP. Make sure something else is terminating TLS in front of it.${plain}"
            fi

            systemctl restart x-ui > /dev/null 2>&1 || rc-service x-ui restart > /dev/null 2>&1
            echo -e "${green}✓ SSL setup skipped.${plain}"
            ;;
        *)
            echo -e "${red}无效 option. Skipping SSL setup.${plain}"
            SSL_HOST="${server_ip}"
            ;;
    esac
}

config_after_update() {
    local panel_needs_restart=0

    echo -e "${yellow}x-ui settings:${plain}"
    ${xui_folder}/x-ui setting -show true
    ${xui_folder}/x-ui migrate

    # Properly detect empty cert by checking if cert: line exists and has content after it
    local existing_cert=$(${xui_folder}/x-ui setting -getCert true 2> /dev/null | grep 'cert:' | awk -F': ' '{print $2}' | tr -d '[:space:]')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}' | sed 's#^/##')

    # Get server IP
    local URL_lists=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        local response=$(curl -s -w "\n%{http_code}" --max-time 3 "${ip_address}" 2> /dev/null)
        local http_code=$(echo "$response" | tail -n1)
        local ip_result=$(echo "$response" | head -n-1 | tr -d '[:space:]"')
        if [[ "${http_code}" == "200" && "${ip_result}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            server_ip="${ip_result}"
            break
        fi
    done

    if [[ -z "$server_ip" ]]; then
        echo -e "${yellow}无法从任何服务自动检测服务器 IP。${plain}"
        while [[ -z "$server_ip" ]]; do
            read -rp "请 enter your server's public IPv4 address: " server_ip
            server_ip="${server_ip// /}"
            if [[ ! "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo -e "${red}无效 IPv4 address. 请 重试.${plain}"
                server_ip=""
            fi
        done
    fi

    # Handle missing/short webBasePath
    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        echo -e "${yellow}WebBasePath 缺失或过短，正在生成新路径……${plain}"
        local config_webBasePath=$(gen_random_string 18)
        ${xui_folder}/x-ui setting -webBasePath "${config_webBasePath}"
        existing_webBasePath="${config_webBasePath}"
        panel_needs_restart=1
        echo -e "${green}新的 WebBasePath： ${config_webBasePath}${plain}"
    fi

    # Check and prompt for SSL if missing
    if [[ -z "$existing_cert" ]]; then
        echo ""
        echo -e "${red}═══════════════════════════════════════════${plain}"
        echo -e "${red}      ⚠ NO SSL CERTIFICATE DETECTED ⚠     ${plain}"
        echo -e "${red}═══════════════════════════════════════════${plain}"
        echo -e "${yellow}For security, SSL 证书 is MANDATORY for all panels.${plain}"
        echo -e "${yellow}Let's Encrypt 现在同时支持域名和 IP 地址！${plain}"
        echo ""

        # Prompt and setup SSL (domain or IP)
        prompt_and_setup_ssl "${existing_port}" "${existing_webBasePath}" "${server_ip}"

        echo ""
        echo -e "${green}═══════════════════════════════════════════${plain}"
        echo -e "${green}     Panel Access Information              ${plain}"
        echo -e "${green}═══════════════════════════════════════════${plain}"
        echo -e "${green}访问地址： https://${SSL_HOST}:${existing_port}/${existing_webBasePath}${plain}"
        echo -e "${green}═══════════════════════════════════════════${plain}"
        echo -e "${yellow}⚠ SSL 证书: Enabled and configured${plain}"
    else
        echo -e "${green}SSL 证书 is already configured${plain}"
        # Show access URL with existing certificate
        local cert_domain=$(basename "$(dirname "$existing_cert")")
        echo ""
        echo -e "${green}═══════════════════════════════════════════${plain}"
        echo -e "${green}     Panel Access Information              ${plain}"
        echo -e "${green}═══════════════════════════════════════════${plain}"
        echo -e "${green}访问地址： https://${cert_domain}:${existing_port}/${existing_webBasePath}${plain}"
        echo -e "${green}═══════════════════════════════════════════${plain}"
    fi

    if [[ "$panel_needs_restart" -eq 1 ]]; then
        echo -e "${yellow}Restarting panel to apply the new web base path...${plain}"
        systemctl restart x-ui 2> /dev/null || rc-service x-ui restart 2> /dev/null
    fi
}

# setup_fail2ban auto-installs and configures fail2ban for the IP Limit feature
# by invoking the freshly downloaded x-ui CLI. IP Limit is load-bearing on
# fail2ban (without it the panel disables the limitIp field and zeroes existing
# limits), so updating an older install should make it work without a manual
# trip through the IP Limit menu. Non-fatal: a fail2ban failure must never abort
# the update. XUI_ENABLE_FAIL2BAN is honored (load_xui_env exports it from the
# persisted env file, so a deliberate opt-out survives updates).
setup_fail2ban() {
    if [[ -n "${XUI_ENABLE_FAIL2BAN+x}" && "${XUI_ENABLE_FAIL2BAN}" != "true" ]]; then
        echo -e "${yellow}XUI_ENABLE_FAIL2BAN=${XUI_ENABLE_FAIL2BAN}, skipping Fail2ban auto-setup.${plain}"
        return 0
    fi

    if [[ ! -x /usr/bin/x-ui ]]; then
        echo -e "${yellow}x-ui CLI 未找到; skipping Fail2ban auto-setup.${plain}"
        return 0
    fi

    echo -e "${green}正在为 IP 限制功能配置 Fail2ban……${plain}"
    if /usr/bin/x-ui setup-fail2ban; then
        echo -e "${green}Fail2ban setup 完成.${plain}"
    else
        echo -e "${yellow}Fail2ban setup did not finish; IP Limit stays 已禁用 until you run 'x-ui' and open the IP Limit menu. Continuing.${plain}"
    fi
    return 0
}

# Lands a systemd unit file at ${xui_service}/x-ui.service via a temp file +
# atomic mv, so a failed cp/curl or an interrupted mv never leaves a
# truncated unit file at the live path -- systemd would then fail to parse
# it on the next daemon-reload/start. Same pattern already used for
# /usr/bin/x-ui elsewhere in this script. source_is_url picks cp (from a
# file already extracted from the release tarball) vs curl (GitHub fallback).
_install_xui_service_unit() {
    local source="$1"
    local source_is_url="$2"
    local dest="${xui_service}/x-ui.service"
    local temp_file="${dest}.tmp.$$"

    rm -f "$temp_file"
    if [[ "$source_is_url" == "true" ]]; then
        ${curl_bin} -fLRo "$temp_file" "$source" > /dev/null 2>&1
    else
        cp -f "$source" "$temp_file" > /dev/null 2>&1
    fi
    if [[ $? -ne 0 ]]; then
        rm -f "$temp_file"
        return 1
    fi
    if [[ ! -s "$temp_file" ]]; then
        rm -f "$temp_file"
        return 1
    fi
    mv -f "$temp_file" "$dest"
    if [[ $? -ne 0 ]]; then
        rm -f "$temp_file"
        return 1
    fi
    return 0
}

update_x-ui() {
    cd ${xui_folder%/x-ui}/

    load_xui_env

    if [ -f "${xui_folder}/x-ui" ]; then
        current_xui_version=$(${xui_folder}/x-ui -v)
        echo -e "${green}当前 x-ui version: ${current_xui_version}${plain}"
    else
        _fail "ERROR: Current x-ui version: unknown"
    fi

    echo -e "${green}正在下载 new x-ui version...${plain}"

    # XUI_UPDATE_TAG lets the panel target a specific release tag (e.g. the
    # rolling dev-latest pre-release). Empty keeps the default latest-stable flow.
    if [[ -n "${XUI_UPDATE_TAG}" ]]; then
        tag_version="${XUI_UPDATE_TAG}"
        echo -e "${green}Using update tag: ${tag_version}${plain}"
    else
        tag_version=$(${curl_bin} -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2> /dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            _fail "ERROR: Failed to fetch x-ui version, it may be due to GitHub API restrictions, please try it later"
        fi
    fi
    echo -e "Got x-ui latest version: ${tag_version}, beginning the 安装..."
    ${curl_bin} -fLRo ${xui_folder}-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz 2> /dev/null
    if [[ $? -ne 0 ]]; then
        _fail "ERROR: Failed to download x-ui, please be sure that your server can access GitHub"
    fi
    if [[ ! -s ${xui_folder}-linux-$(arch).tar.gz ]]; then
        rm ${xui_folder}-linux-$(arch).tar.gz -f > /dev/null 2>&1
        _fail "ERROR: Downloaded x-ui release archive is empty, please be sure that your server can access GitHub"
    fi

    if [[ -e ${xui_folder}/ ]]; then
        echo -e "${green}Stopping x-ui...${plain}"
        if [[ $release == "alpine" ]]; then
            if [ -f "/etc/init.d/x-ui" ]; then
                rc-service x-ui stop > /dev/null 2>&1
                rc-update del x-ui > /dev/null 2>&1
                echo -e "${green}Removing old service unit version...${plain}"
                rm -f /etc/init.d/x-ui > /dev/null 2>&1
            else
                rm x-ui-linux-$(arch).tar.gz -f > /dev/null 2>&1
                _fail "ERROR: x-ui service unit not installed."
            fi
        else
            if [ -f "${xui_service}/x-ui.service" ]; then
                systemctl stop x-ui > /dev/null 2>&1
                systemctl disable x-ui > /dev/null 2>&1
                echo -e "${green}Removing old systemd unit version...${plain}"
                rm ${xui_service}/x-ui.service -f > /dev/null 2>&1
                systemctl daemon-reload > /dev/null 2>&1
            else
                rm x-ui-linux-$(arch).tar.gz -f > /dev/null 2>&1
                _fail "ERROR: x-ui systemd unit not installed."
            fi
        fi
        # Kill any leftover mtg (MTProto) sidecars. x-ui runs them outside its own
        # lifecycle, so on Linux a stale one can survive the stop and keep holding
        # an inbound port with an outdated secret, silently breaking new clients.
        # The new panel respawns a clean mtg per inbound on next start.
        pkill -f 'mtg-linux-[^ ]* run ' > /dev/null 2>&1 || true
        echo -e "${green}Removing old x-ui version...${plain}"
        rm ${xui_folder} -f > /dev/null 2>&1
        rm ${xui_folder}/x-ui.service -f > /dev/null 2>&1
        rm ${xui_folder}/x-ui.service.debian -f > /dev/null 2>&1
        rm ${xui_folder}/x-ui.service.arch -f > /dev/null 2>&1
        rm ${xui_folder}/x-ui.service.rhel -f > /dev/null 2>&1
        rm ${xui_folder}/x-ui -f > /dev/null 2>&1
        rm ${xui_folder}/x-ui.sh -f > /dev/null 2>&1
        echo -e "${green}Removing old mtg version...${plain}"
        rm ${xui_folder}/bin/mtg-linux-$(arch) -f > /dev/null 2>&1
        echo -e "${green}Removing old xray version...${plain}"
        rm ${xui_folder}/bin/xray-linux-$(arch) -f > /dev/null 2>&1
        echo -e "${green}Removing old README and LICENSE file...${plain}"
        rm ${xui_folder}/bin/README.md -f > /dev/null 2>&1
        rm ${xui_folder}/bin/LICENSE -f > /dev/null 2>&1
    else
        rm x-ui-linux-$(arch).tar.gz -f > /dev/null 2>&1
        _fail "ERROR: x-ui not installed."
    fi

    echo -e "${green}正在安装 new x-ui version...${plain}"
    tar zxvf x-ui-linux-$(arch).tar.gz > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        rm x-ui-linux-$(arch).tar.gz -f > /dev/null 2>&1
        _fail "ERROR: Failed to extract the x-ui release archive -- the previous installation has already been removed, so the panel will not start until this is fixed; try running the update again"
    fi
    rm x-ui-linux-$(arch).tar.gz -f > /dev/null 2>&1
    cd x-ui > /dev/null 2>&1
    if [[ $? -ne 0 || ! -s x-ui ]]; then
        _fail "ERROR: Extracted x-ui archive is missing the x-ui binary -- the previous installation has already been removed, so the panel will not start until this is fixed; try running the update again"
    fi
    chmod +x x-ui > /dev/null 2>&1

    # Check the system's architecture and rename the file accordingly.
    # The panel binary maps GOARCH=arm to "arm32" (internal/xray/process.go),
    # so the Xray binary must be named xray-linux-arm32; mtg keeps plain "arm".
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm32 > /dev/null 2>&1
        chmod +x bin/xray-linux-arm32 > /dev/null 2>&1
        if [[ -f bin/mtg-linux-$(arch) ]]; then
            mv bin/mtg-linux-$(arch) bin/mtg-linux-arm > /dev/null 2>&1
            chmod +x bin/mtg-linux-arm > /dev/null 2>&1
        fi
    fi

    chmod +x x-ui bin/xray-linux-$(arch) > /dev/null 2>&1
    if [[ -f bin/mtg-linux-arm ]]; then
        chmod +x bin/mtg-linux-arm > /dev/null 2>&1
    elif [[ -f bin/mtg-linux-$(arch) ]]; then
        chmod +x bin/mtg-linux-$(arch) > /dev/null 2>&1
    fi

    echo -e "${green}正在下载 and installing x-ui.sh script...${plain}"
    local xui_script_temp="/usr/bin/x-ui-temp.$$"
    rm -f "${xui_script_temp}"
    ${curl_bin} -fLRo "${xui_script_temp}" https://raw.githubusercontent.com/AiCodeNb/3x-ui/main/x-ui.sh > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        rm -f "${xui_script_temp}"
        _fail "ERROR: Failed to download x-ui.sh script, please be sure that your server can access GitHub"
    fi
    if [[ ! -s "${xui_script_temp}" ]]; then
        rm -f "${xui_script_temp}"
        _fail "ERROR: Downloaded x-ui.sh script is empty, please be sure that your server can access GitHub"
    fi
    mv -f "${xui_script_temp}" /usr/bin/x-ui
    if [[ $? -ne 0 ]]; then
        rm -f "${xui_script_temp}"
        _fail "ERROR: Failed to install x-ui.sh script"
    fi

    chmod +x ${xui_folder}/x-ui.sh > /dev/null 2>&1
    chmod +x /usr/bin/x-ui > /dev/null 2>&1
    mkdir -p /var/log/x-ui > /dev/null 2>&1

    echo -e "${green}Changing owner...${plain}"
    chown -R root:root ${xui_folder} > /dev/null 2>&1

    if [ -f "${xui_folder}/bin/config.json" ]; then
        echo -e "${green}Changing on config file permissions...${plain}"
        chmod 640 ${xui_folder}/bin/config.json > /dev/null 2>&1
    fi

    if [[ $release == "alpine" ]]; then
        echo -e "${green}正在下载 and installing startup unit x-ui.rc...${plain}"
        xui_rc_temp="/etc/init.d/x-ui.tmp.$$"
        rm -f "${xui_rc_temp}"
        ${curl_bin} -fLRo "${xui_rc_temp}" https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.rc > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            rm -f "${xui_rc_temp}"
            _fail "ERROR: Failed to download startup unit x-ui.rc, please be sure that your server can access GitHub"
        fi
        if [[ ! -s "${xui_rc_temp}" ]]; then
            rm -f "${xui_rc_temp}"
            _fail "ERROR: Downloaded startup unit x-ui.rc is empty, please be sure that your server can access GitHub"
        fi
        mv -f "${xui_rc_temp}" /etc/init.d/x-ui
        if [[ $? -ne 0 ]]; then
            rm -f "${xui_rc_temp}"
            _fail "ERROR: Failed to install startup unit x-ui.rc"
        fi
        chmod +x /etc/init.d/x-ui > /dev/null 2>&1
        chown root:root /etc/init.d/x-ui > /dev/null 2>&1
        rc-update add x-ui > /dev/null 2>&1
        rc-service x-ui start > /dev/null 2>&1
    else
        if [ -f "x-ui.service" ]; then
            echo -e "${green}正在安装 systemd unit...${plain}"
            if ! _install_xui_service_unit "x-ui.service" "false"; then
                echo -e "${red}失败 to copy x-ui.service${plain}"
                exit 1
            fi
        else
            service_installed=false
            case "${release}" in
                ubuntu | debian | armbian)
                    if [ -f "x-ui.service.debian" ]; then
                        echo -e "${green}正在安装 debian-like systemd unit...${plain}"
                        if _install_xui_service_unit "x-ui.service.debian" "false"; then
                            service_installed=true
                        fi
                    fi
                    ;;
                arch | manjaro | parch)
                    if [ -f "x-ui.service.arch" ]; then
                        echo -e "${green}正在安装 arch-like systemd unit...${plain}"
                        if _install_xui_service_unit "x-ui.service.arch" "false"; then
                            service_installed=true
                        fi
                    fi
                    ;;
                *)
                    if [ -f "x-ui.service.rhel" ]; then
                        echo -e "${green}正在安装 rhel-like systemd unit...${plain}"
                        if _install_xui_service_unit "x-ui.service.rhel" "false"; then
                            service_installed=true
                        fi
                    fi
                    ;;
            esac

            # If service file not found in tar.gz, download from GitHub
            if [ "$service_installed" = false ]; then
                echo -e "${yellow}Service files 未找到 in tar.gz, downloading from GitHub...${plain}"
                case "${release}" in
                    ubuntu | debian | armbian)
                        service_unit_url="https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.service.debian"
                        ;;
                    arch | manjaro | parch)
                        service_unit_url="https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.service.arch"
                        ;;
                    *)
                        service_unit_url="https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.service.rhel"
                        ;;
                esac

                if ! _install_xui_service_unit "$service_unit_url" "true"; then
                    echo -e "${red}失败 to install x-ui.service from GitHub${plain}"
                    exit 1
                fi
            fi
        fi
        chown root:root ${xui_service}/x-ui.service > /dev/null 2>&1
        chmod 644 ${xui_service}/x-ui.service > /dev/null 2>&1
        systemctl daemon-reload > /dev/null 2>&1
        systemctl enable x-ui > /dev/null 2>&1
        systemctl start x-ui > /dev/null 2>&1
    fi

    config_after_update

    # IP Limit relies on fail2ban; install + configure it now so the feature
    # works out of the box on update too (no-op when XUI_ENABLE_FAIL2BAN=false).
    # Never fatal.
    setup_fail2ban

    echo -e "${green}x-ui ${tag_version}${plain} updating finished, it 正在运行 now..."
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui 控制菜单用法（子命令）：${plain}              │
│                                                       │
│  ${blue}x-ui${plain}              - 管理脚本          │
│  ${blue}x-ui start${plain}        - 启动                            │
│  ${blue}x-ui stop${plain}         - 停止                             │
│  ${blue}x-ui restart${plain}      - 重启                          │
│  ${blue}x-ui status${plain}       - 当前状态                   │
│  ${blue}x-ui settings${plain}     - 当前设置                 │
│  ${blue}x-ui enable${plain}       - 启用开机自启   │
│  ${blue}x-ui disable${plain}      - 禁用开机自启  │
│  ${blue}x-ui log${plain}          - 查看日志                       │
│  ${blue}x-ui banlog${plain}       - 查看 Fail2ban 封禁日志          │
│  ${blue}x-ui update${plain}       - 更新                           │
│  ${blue}x-ui legacy${plain}       - 旧版本                   │
│  ${blue}x-ui install${plain}      - 安装                          │
│  ${blue}x-ui uninstall${plain}    - 卸载                        │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}运行中...${plain}"
install_base
update_x-ui $1
