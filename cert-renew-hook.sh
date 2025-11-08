#!/bin/bash
# 证书更新钩子脚本
# 当 acme.sh 自动更新证书后，此脚本会：
# 1. 复制新证书到 sing-box 使用的目录
# 2. 重启 sing-box 服务以加载新证书

CERT_DIR="/root/ygkkkca"
DOMAIN="$1"  # acme.sh 会传递域名作为参数

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/cert-renew.log
}

log "证书更新钩子启动，域名: $DOMAIN"

# 检查证书目录是否存在
if [ ! -d "$CERT_DIR" ]; then
    mkdir -p "$CERT_DIR"
    log "创建证书目录: $CERT_DIR"
fi

# 从 acme.sh 目录复制证书到 sing-box 目录
if [ -n "$DOMAIN" ]; then
    ACME_CERT_DIR="$HOME/.acme.sh/$DOMAIN"

    if [ -f "$ACME_CERT_DIR/fullchain.cer" ] && [ -f "$ACME_CERT_DIR/$DOMAIN.key" ]; then
        # 备份旧证书
        if [ -f "$CERT_DIR/cert.crt" ]; then
            cp "$CERT_DIR/cert.crt" "$CERT_DIR/cert.crt.bak.$(date +%Y%m%d)"
            cp "$CERT_DIR/private.key" "$CERT_DIR/private.key.bak.$(date +%Y%m%d)"
            log "已备份旧证书"
        fi

        # 复制新证书
        cp "$ACME_CERT_DIR/fullchain.cer" "$CERT_DIR/cert.crt"
        cp "$ACME_CERT_DIR/$DOMAIN.key" "$CERT_DIR/private.key"
        chmod 644 "$CERT_DIR/cert.crt"
        chmod 600 "$CERT_DIR/private.key"
        log "证书复制成功: $DOMAIN"

        # 保存域名信息
        echo "$DOMAIN" > "$CERT_DIR/ca.log"

        # 重启 sing-box 服务
        if systemctl is-active --quiet sing-box; then
            systemctl reload sing-box 2>/dev/null || systemctl restart sing-box
            if [ $? -eq 0 ]; then
                log "sing-box 服务已重启，新证书已生效"
            else
                log "ERROR: sing-box 服务重启失败"
                exit 1
            fi
        else
            log "WARNING: sing-box 服务未运行，跳过重启"
        fi

        # 记录证书有效期
        CERT_DATES=$(openssl x509 -in "$CERT_DIR/cert.crt" -noout -dates 2>/dev/null)
        log "证书有效期: $CERT_DATES"

    else
        log "ERROR: 找不到 acme.sh 证书文件: $ACME_CERT_DIR"
        exit 1
    fi
else
    log "ERROR: 未提供域名参数"
    exit 1
fi

log "证书更新完成"
exit 0
