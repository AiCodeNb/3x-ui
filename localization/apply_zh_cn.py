#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


SCRIPT_FILES = ("install.sh", "update.sh", "x-ui.sh")

EXACT_REPLACEMENTS = {
    "3X-UI Panel Management Script": "3X-UI 面板管理脚本",
    "x-ui control menu usages (subcommands):": "x-ui 控制菜单用法（子命令）：",
    "Admin Management Script": "管理脚本",
    "Exit Script": "退出脚本",
    "Install": "安装",
    "Update": "更新",
    "Update to Dev Channel (latest commit)": "更新到开发通道（最新提交）",
    "Update Menu": "更新菜单",
    "Legacy Version": "旧版本",
    "Legacy version": "旧版本",
    "Uninstall": "卸载",
    "Reset Username & Password": "重置用户名与密码",
    "Reset Web Base Path": "重置 Web 基础路径",
    "Reset Settings": "重置设置",
    "Change Port": "修改端口",
    "View Current Settings": "查看当前设置",
    "Start": "启动",
    "Stop": "停止",
    "Restart": "重启",
    "Restart Xray": "重启 Xray",
    "Check Status": "检查状态",
    "Current Status": "当前状态",
    "Current Settings": "当前设置",
    "Logs Management": "日志管理",
    "Check logs": "查看日志",
    "Check Fail2ban ban logs": "查看 Fail2ban 封禁日志",
    "Enable Autostart": "启用开机自启",
    "Disable Autostart": "禁用开机自启",
    "Enable Autostart on OS Startup": "启用开机自启",
    "Disable Autostart on OS Startup": "禁用开机自启",
    "SSL Certificate Management": "SSL 证书管理",
    "Cloudflare SSL Certificate": "Cloudflare SSL 证书",
    "IP Limit Management": "IP 限制管理",
    "Firewall Management": "防火墙管理",
    "SSH Port Forwarding Management": "SSH 端口转发管理",
    "PostgreSQL Management": "PostgreSQL 管理",
    "Enable BBR": "启用 BBR",
    "Disable BBR": "禁用 BBR",
    "Update Geo Files": "更新 Geo 文件",
    "Update all geo files": "更新全部 Geo 文件",
    "Speedtest by Ookla": "Ookla 网络测速",
    "Back to Main Menu": "返回主菜单",
    "Choose an option:": "请选择：",
    "Choose an option": "请选择",
    "Please enter your selection": "请输入选项",
    "Please enter the correct number": "请输入正确的编号",
    "Press enter to return to the main menu:": "按回车键返回主菜单：",
    "Invalid option. Please select a valid number.": "选项无效，请输入有效编号。",
    "Panel state:": "面板状态：",
    "Start automatically:": "开机自启：",
    "xray state:": "Xray 状态：",
    "Running": "运行中",
    "Not Running": "未运行",
    "Not Installed": "未安装",
    "Managed by Docker": "由 Docker 管理",
    "Yes": "是",
    "No": "否",
    "Debug Log": "调试日志",
    "Clear All logs": "清空全部日志",
    "All Logs cleared.": "全部日志已清空。",
    "Install Firewall": "安装防火墙",
    "Port List [numbered]": "端口规则列表（带编号）",
    "Open Ports": "开放端口",
    "Delete Ports from List": "从列表删除端口",
    "Enable Firewall": "启用防火墙",
    "Disable Firewall": "禁用防火墙",
    "Firewall Status": "防火墙状态",
    "Current UFW rules:": "当前 UFW 规则：",
    "Opened the specified ports:": "已开放指定端口：",
    "Rule numbers": "规则编号",
    "Ports": "端口",
    "Install Fail2ban and configure IP Limit": "安装 Fail2ban 并配置 IP 限制",
    "Uninstall Fail2ban and IP Limit": "卸载 Fail2ban 和 IP 限制",
    "Show Fail2ban status": "查看 Fail2ban 状态",
    "Show Fail2ban logs": "查看 Fail2ban 日志",
    "Enable IP Limit": "启用 IP 限制",
    "Disable IP Limit": "禁用 IP 限制",
    "Install PostgreSQL locally and create a dedicated user/db (recommended)": "本机安装 PostgreSQL 并创建专用用户/数据库（推荐）",
    "Install PostgreSQL (server + client + xui db)": "安装 PostgreSQL（服务端、客户端和 xui 数据库）",
    "Install/Upgrade client tools (pg_dump/pg_restore)": "安装/升级客户端工具（pg_dump/pg_restore）",
    "Input file": "输入文件",
    "Output file (leave empty to auto-name next to input)": "输出文件（留空则在输入文件旁自动命名）",
    "Convert .db <-> .dump (SQLite)": "转换 .db 与 .dump（SQLite）",
    "Upgrade pg_dump/pg_restore tools": "升级 pg_dump/pg_restore 工具",
    "Update to Dev channel (latest)": "更新到开发通道（最新）",
    "Please set the login username": "请设置登录用户名",
    "Please set the login password": "请设置登录密码",
    "default is a random username": "默认随机生成用户名",
    "default is a random password": "默认随机生成密码",
    "Operation canceled.": "操作已取消。",
    "Two factor authentication has been disabled.": "双重身份验证已禁用。",
    "All panel settings have been reset to default.": "面板设置已全部恢复默认值。",
    "Access URL:": "访问地址：",
    "Database:": "数据库：",
    "Warning:": "警告：",
    "ERROR:": "错误：",
    "Error:": "错误：",
    "Success": "成功",
    "Failed": "失败",
    "Installation": "安装",
    "installation": "安装",
    "Downloading": "正在下载",
    "download": "下载",
    "Downloaded": "已下载",
    "Installing": "正在安装",
    "installed": "已安装",
    "Updating": "正在更新",
    "updated": "已更新",
    "Configuration": "配置",
    "configuration": "配置",
    "Certificate": "证书",
    "certificate": "证书",
    "Username": "用户名",
    "username": "用户名",
    "Password": "密码",
    "password": "密码",
    "Port": "端口",
    "port": "端口",
    "Domain": "域名",
    "domain": "域名",
    "Please": "请",
    "Enter": "输入",
    "Select": "选择",
    "Invalid": "无效",
    "enabled": "已启用",
    "disabled": "已禁用",
    "successfully": "成功",
    "Successfully": "成功",
    "failed": "失败",
    "Warning": "警告",
    "Error": "错误",
    "Current": "当前",
    "Status": "状态",
    "Settings": "设置",
    "Management": "管理",
    "Continue?": "是否继续？",
    "Do you want to continue?": "是否继续？",
    "Are you sure": "确定",
    "leave empty": "留空",
    "default": "默认",
    "Default": "默认",
    "not found": "未找到",
    "not installed": "未安装",
    "is not installed": "尚未安装",
    "is already installed": "已经安装",
    "is running": "正在运行",
    "is not running": "未运行",
    "try again": "重试",
    "Exiting.": "正在退出。",
    "Exiting": "正在退出",
    "Completed": "已完成",
    "complete": "完成",
    "Cancel": "取消",
    "Cancelled": "已取消",
    "Fatal error:": "致命错误：",
    "Please run this script with root privilege": "请以 root 权限运行此脚本",
    "Failed to check the system OS, please contact the author!": "无法识别操作系统，请联系作者！",
    "The OS release is:": "操作系统发行版：",
    "Unsupported CPU architecture!": "不支持的 CPU 架构！",
    "Unsupported distro for automatic PostgreSQL install:": "不支持自动安装 PostgreSQL 的发行版：",
    "Arch:": "架构：",
    "Note:": "注意：",
    "IPv4 address is required": "必须提供 IPv4 地址",
    "Including IPv6 address:": "同时包含 IPv6 地址：",
    "Private Key File:": "私钥文件：",
    "Private Key Path:": "私钥路径：",
    "Certificate Path:": "证书路径：",
    "Covers:": "覆盖域名：",
    "Stopping panel temporarily...": "正在临时停止面板……",
    "Would you like to modify --reloadcmd for ACME?": "是否修改 ACME 的 --reloadcmd？",
    "Input your own command": "输入自定义命令",
    "It's recommended to put x-ui restart at the end": "建议将 x-ui restart 放在命令末尾",
    "Skipping panel path setting.": "跳过面板证书路径设置。",
    "Let's Encrypt for IP Address (6-day validity, auto-renews)": "为 IP 地址申请 Let's Encrypt 证书（有效期 6 天，自动续期）",
    "Skip SSL (advanced — behind reverse proxy / SSH tunnel only)": "跳过 SSL（高级选项，仅限反向代理或 SSH 隧道后方）",
    "Could not auto-detect server IP from any provider.": "无法从任何服务自动检测服务器 IP。",
    "Database Selection": "选择数据库",
    "PostgreSQL (recommended for high client counts / many nodes)": "PostgreSQL（大量客户端或多节点时推荐）",
    "Use an existing PostgreSQL server (enter DSN)": "使用现有 PostgreSQL 服务器（输入 DSN）",
    "Retry local install": "重试本机安装",
    "Abort install": "中止安装",
    "Fall back to SQLite": "改用 SQLite",
    "SSL is strongly recommended. Skip only if a reverse proxy": "强烈建议使用 SSL。仅当反向代理",
    "or SSH tunnel handles TLS for you.": "或 SSH 隧道已处理 TLS 时才可跳过。",
    "Let's Encrypt now supports both domains and IP addresses!": "Let's Encrypt 现在同时支持域名和 IP 地址！",
    "IMPORTANT: Save these credentials securely!": "重要：请安全保存这些凭据！",
    "PostgreSQL backup & restore is built into the panel:": "面板已内置 PostgreSQL 备份与恢复：",
    "PostgreSQL Credentials": "PostgreSQL 凭据",
    "DB Name:": "数据库名：",
    "Host:": "主机：",
    "Env file:": "环境文件：",
    "Connect from this server:": "从本服务器连接：",
    "WebBasePath is missing or too short. Generating a new one...": "WebBasePath 缺失或过短，正在生成新路径……",
    "New WebBasePath:": "新的 WebBasePath：",
    "Generated new random login credentials:": "已生成新的随机登录凭据：",
    "Setting up Fail2ban for the IP Limit feature...": "正在为 IP 限制功能配置 Fail2ban……",
    "Beginning to install x-ui": "开始安装 x-ui",
    "Found x-ui.service in extracted files, installing...": "在解压文件中找到 x-ui.service，正在安装……",
    "Setting up systemd unit...": "正在配置 systemd 服务……",
    "If you need to install this panel again, you can use below command:": "如需重新安装面板，可使用以下命令：",
    "Resetting Web Base Path": "正在重置 Web 基础路径",
    "Web base path has been reset to:": "Web 基础路径已重置为：",
    "get current settings error, please check logs": "获取当前设置失败，请检查日志",
    "In Docker the panel runs as the container's main process.": "在 Docker 中，面板作为容器主进程运行。",
    "To stop it, stop the container from the host:": "如需停止，请在宿主机停止容器：",
    "Could not find the running panel process to signal.": "找不到正在运行的面板进程。",
    "Autostart is controlled by the Docker restart policy": "开机自启由 Docker 重启策略控制",
    "There is no service to enable inside the container.": "容器内没有需要启用的系统服务。",
    "Firewall is already active": "防火墙已处于启用状态",
    "Activating firewall...": "正在启用防火墙……",
    "Do you want to delete rules by:": "请选择删除规则的方式：",
    "Selected rules have been deleted.": "所选规则已删除。",
    "Deleted the specified ports:": "已删除指定端口：",
    "Revoke & Remove": "吊销并删除",
    "Force Renew": "强制续期",
    "Show Existing Domains": "显示现有域名",
    "Set Cert paths for the panel": "设置面板证书路径",
    "Get SSL for IP Address (6-day cert, auto-renews)": "为 IP 地址申请 SSL（6 天证书，自动续期）",
    "Existing domains:": "现有域名：",
    "Existing domains and their paths:": "现有域名及路径：",
    "Available domains:": "可用域名：",
    "Do you want to proceed?": "是否继续？",
    "Server IP detected:": "检测到服务器 IP：",
    "Skipping panel path setting.": "跳过面板路径设置。",
    "Instructions for Use": "使用说明",
    "Do you confirm the information and wish to proceed?": "确认以上信息并继续吗？",
    "Input your key here:": "请在此输入密钥：",
    "Input your email here:": "请在此输入邮箱：",
    "Input your token here:": "请在此输入令牌：",
    "Change Ban Duration": "修改封禁时长",
    "Unban Everyone": "解除全部封禁",
    "Ban Logs": "封禁日志",
    "Ban an IP Address": "封禁 IP 地址",
    "Unban an IP Address": "解除 IP 地址封禁",
    "Real-Time Logs": "实时日志",
    "Only remove IP Limit configurations": "仅删除 IP 限制配置",
    "Checking ban logs...": "正在检查封禁日志……",
    "Ban log file is empty": "封禁日志为空",
    "Unable to get jail status": "无法获取 jail 状态",
    "Panel is secure with SSL.": "面板已使用 SSL 保护。",
    "Standard SSH command:": "标准 SSH 命令：",
    "If using SSH key:": "如使用 SSH 密钥：",
    "After connecting, access the panel at:": "连接后通过以下地址访问面板：",
    "Set listen IP": "设置监听 IP",
    "Clear listen IP": "清除监听 IP",
    "Set a custom IP": "设置自定义 IP",
    "Listen IP has been cleared.": "监听 IP 已清除。",
    "PostgreSQL stop signal sent.": "已发送 PostgreSQL 停止信号。",
    "PostgreSQL set to start automatically on boot.": "PostgreSQL 已设为开机自启。",
    "This panel was using PostgreSQL.": "此面板正在使用 PostgreSQL。",
    "PostgreSQL has been purged.": "PostgreSQL 已彻底删除。",
    "Convert between a SQLite": "在 SQLite",
    "and a portable": "与便携式",
    "direction auto-detected": "自动识别转换方向",
}

SELF_HOSTED_URLS = {
    "https://raw.githubusercontent.com/MHSanaei/3x-ui/main/install.sh":
        "https://raw.githubusercontent.com/AiCodeNb/3x-ui/main/install.sh",
    "https://raw.githubusercontent.com/MHSanaei/3x-ui/main/update.sh":
        "https://raw.githubusercontent.com/AiCodeNb/3x-ui/main/update.sh",
    "https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh":
        "https://raw.githubusercontent.com/AiCodeNb/3x-ui/main/x-ui.sh",
    "https://github.com/MHSanaei/3x-ui/raw/main/x-ui.sh":
        "https://raw.githubusercontent.com/AiCodeNb/3x-ui/main/x-ui.sh",
}

UI_CALL = re.compile(
    r"\b(?:echo|read\s+-[^\n]*p|LOG[DEIW]|confirm|prompt_[a-zA-Z0-9_]+)\b"
)
PROTECTED_VALUE = re.compile(
    r"https?://[^\s\"']+|\$\{[^}\r\n]*\}|\$\([^)\r\n]*\)|\$[A-Za-z_][A-Za-z0-9_]*"
)
GENERATED_MARKER = "# 中文版由 localization/apply_zh_cn.py 基于 MHSanaei/3x-ui 自动生成。"


def quote_count(line: str) -> int:
    return len(re.findall(r'(?<!\\)"', line))


def translate_ui_text(text: str) -> tuple[str, int]:
    protected: list[str] = []

    def protect(match: re.Match[str]) -> str:
        protected.append(match.group(0))
        return f"\x00XUI_PROTECTED_{len(protected) - 1}\x00"

    text = PROTECTED_VALUE.sub(protect, text)
    replacements = 0
    for source, target in sorted(
        EXACT_REPLACEMENTS.items(), key=lambda item: len(item[0]), reverse=True
    ):
        if source.isalpha():
            pattern = re.compile(
                rf"(?<![A-Za-z0-9_]){re.escape(source)}(?![A-Za-z0-9_])"
            )
            text, occurrences = pattern.subn(target, text)
        else:
            occurrences = text.count(source)
            if occurrences:
                text = text.replace(source, target)
        replacements += occurrences
    for index, value in enumerate(protected):
        text = text.replace(f"\x00XUI_PROTECTED_{index}\x00", value)
    return text, replacements


def transform_script(text: str) -> tuple[str, int]:
    for source, target in SELF_HOSTED_URLS.items():
        text = text.replace(source, target)

    lines = text.splitlines()
    translated: list[str] = []
    in_multiline_echo = False
    replacements = 0

    for line in lines:
        is_ui_line = in_multiline_echo or bool(UI_CALL.search(line))
        if is_ui_line:
            line, count = translate_ui_text(line)
            replacements += count

        if not in_multiline_echo and re.match(
            r'^\s*echo(?:\s+-[A-Za-z]+)*\s+"[^"]*$', line
        ):
            in_multiline_echo = True
        elif in_multiline_echo and quote_count(line) % 2 == 1:
            in_multiline_echo = False

        translated.append(line)

    if translated and translated[0].startswith("#!"):
        if len(translated) < 2 or translated[1] != GENERATED_MARKER:
            translated.insert(1, GENERATED_MARKER)

    return "\n".join(translated) + "\n", replacements


def apply(source_dir: Path, output_dir: Path) -> dict[str, int]:
    report: dict[str, int] = {}
    for filename in SCRIPT_FILES:
        source = source_dir / filename
        if not source.is_file():
            raise FileNotFoundError(f"缺少上游脚本：{source}")
        output, count = transform_script(source.read_text(encoding="utf-8"))
        (output_dir / filename).write_text(output, encoding="utf-8", newline="\n")
        report[filename] = count
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="生成 3x-ui 简体中文脚本")
    parser.add_argument("--source-dir", type=Path, default=Path("."))
    parser.add_argument("--output-dir", type=Path, default=Path("."))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    report = apply(args.source_dir, args.output_dir)
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        args.report.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)


if __name__ == "__main__":
    main()
