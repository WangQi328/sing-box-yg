#!/bin/bash
# 设置证书自动更新
# 此脚本应在使用 acme-yg 申请证书后运行

red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
re="\033[0m"

red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }

CERT_DIR="/root/ygkkkca"
HOOK_SCRIPT="/root/cert-renew-hook.sh"

echo -e "${purple}=== Sing-box 证书自动更新设置 ===${re}"
echo

# 检查 acme.sh 是否安装
if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
    red "错误：未检测到 acme.sh，请先使用主菜单的选项 12 申请证书"
    exit 1
fi

# 检查证书目录
if [ ! -d "$CERT_DIR" ] || [ ! -f "$CERT_DIR/ca.log" ]; then
    red "错误：未找到证书文件，请先申请证书"
    exit 1
fi

# 读取域名
DOMAIN=$(cat "$CERT_DIR/ca.log" 2>/dev/null | tr -d '\n\r')
if [ -z "$DOMAIN" ]; then
    red "错误：无法读取域名信息"
    exit 1
fi

green "检测到已申请的域名：$DOMAIN"
echo

# 检查 acme.sh 中的证书
if [ ! -d "$HOME/.acme.sh/$DOMAIN" ]; then
    red "错误：acme.sh 中找不到域名 $DOMAIN 的证书"
    exit 1
fi

# 复制钩子脚本到系统目录
if [ ! -f "$HOOK_SCRIPT" ]; then
    yellow "正在下载证书更新钩子脚本..."
    curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/cert-renew-hook.sh -o "$HOOK_SCRIPT"
    chmod +x "$HOOK_SCRIPT"
    if [ $? -eq 0 ]; then
        green "钩子脚本下载成功"
    else
        red "钩子脚本下载失败，请检查网络"
        exit 1
    fi
else
    green "钩子脚本已存在"
fi

echo
yellow "正在设置证书自动更新..."

# 使用 acme.sh 的 --install-cert 命令设置更新钩子
$HOME/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
    --cert-file "$CERT_DIR/cert.crt" \
    --key-file "$CERT_DIR/private.key" \
    --fullchain-file "$CERT_DIR/cert.crt" \
    --reloadcmd "bash $HOOK_SCRIPT $DOMAIN"

if [ $? -eq 0 ]; then
    green "✓ 证书自动更新设置成功！"
    echo
    green "配置详情："
    echo "  域名: $DOMAIN"
    echo "  证书路径: $CERT_DIR/cert.crt"
    echo "  私钥路径: $CERT_DIR/private.key"
    echo "  更新钩子: $HOOK_SCRIPT"
    echo
    green "acme.sh 会每天自动检查证书，在距离过期 30 天时自动更新"
    green "证书更新后会自动复制到 $CERT_DIR 并重启 sing-box 服务"
    echo

    # 检查证书有效期
    if [ -f "$CERT_DIR/cert.crt" ]; then
        purple "当前证书有效期："
        openssl x509 -in "$CERT_DIR/cert.crt" -noout -dates
        echo
    fi

    # 检查 cron 任务
    if crontab -l 2>/dev/null | grep -q "acme.sh"; then
        green "✓ acme.sh 自动更新 cron 任务已设置"
        echo "当前 cron 任务："
        crontab -l 2>/dev/null | grep acme
    else
        yellow "⚠ 未检测到 acme.sh 的 cron 任务"
        yellow "请运行以下命令手动添加："
        echo "  $HOME/.acme.sh/acme.sh --install-cronjob"
    fi
else
    red "✗ 证书自动更新设置失败"
    exit 1
fi

echo
purple "提示：你可以手动测试证书更新："
echo "  bash $HOOK_SCRIPT $DOMAIN"
