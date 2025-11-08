# 证书自动更新失败问题修复说明

## 问题分析

### 原始问题
使用 acme-yg 脚本申请的 Let's Encrypt 证书在过期后无法自动更新，导致 sing-box 服务中断。

### 根本原因

1. **证书存储位置不匹配**
   - acme.sh 默认存储证书在：`~/.acme.sh/<domain>/`
   - sing-box 期望证书位置：`/root/ygkkkca/cert.crt`

2. **缺少更新钩子（Hook）**
   - acme.sh 虽然会自动更新证书，但没有配置 `--install-cert` 钩子
   - 更新后的证书不会自动复制到 sing-box 使用的目录

3. **缺少服务重载**
   - 即使证书更新了，sing-box 服务也不会自动重载新证书
   - 需要手动重启服务才能生效

## 解决方案

### 新增文件

1. **cert-renew-hook.sh** - 证书更新钩子脚本
   - 自动将更新后的证书复制到 `/root/ygkkkca/`
   - 自动重启 sing-box 服务
   - 记录详细日志到 `/var/log/cert-renew.log`

2. **setup-cert-auto-renew.sh** - 证书自动更新配置脚本
   - 检查现有证书状态
   - 使用 `acme.sh --install-cert` 设置更新钩子
   - 验证配置是否成功

### 修改文件

**sb.sh** - 主脚本修改
- 在证书申请成功后自动设置更新钩子（第 321-341 行）
- 添加菜单选项 13：设置证书自动更新（修复证书过期问题）

### 工作流程

```
证书过期前 30 天
    ↓
acme.sh 自动检查并更新证书
    ↓
触发 --reloadcmd 钩子
    ↓
cert-renew-hook.sh 执行：
  1. 备份旧证书
  2. 复制新证书到 /root/ygkkkca/
  3. 重启 sing-box 服务
    ↓
证书更新完成，服务正常运行
```

## 使用方法

### 方法一：新安装时自动配置（推荐）

使用脚本新申请证书时，会自动设置证书自动更新，无需额外操作。

### 方法二：已有证书手动配置

如果之前已经申请过证书但没有配置自动更新：

```bash
# 方式1：通过主菜单
bash sb.sh
# 选择 13. 设置证书自动更新（修复证书过期问题）

# 方式2：直接运行设置脚本
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/setup-cert-auto-renew.sh)
```

## 验证配置

### 检查 acme.sh 配置

```bash
# 查看已安装的证书
~/.acme.sh/acme.sh --list

# 查看 cron 任务
crontab -l | grep acme

# 查看证书详细信息
~/.acme.sh/acme.sh --info -d your-domain.com
```

### 检查证书有效期

```bash
openssl x509 -in /root/ygkkkca/cert.crt -noout -dates
```

### 测试更新钩子

```bash
# 手动触发证书更新钩子（不会真正更新证书）
bash /root/cert-renew-hook.sh your-domain.com

# 查看更新日志
tail -f /var/log/cert-renew.log
```

### 强制更新证书（测试）

```bash
# 注意：这会强制更新证书，即使未到期
~/.acme.sh/acme.sh --renew -d your-domain.com --force
```

## 常见问题

### Q1: acme.sh 的 cron 任务什么时候运行？
A: 默认每天凌晨随机时间检查，会在证书过期前 30 天自动更新。

### Q2: 如何查看更新日志？
A: 查看两个日志文件：
- acme.sh 日志：`~/.acme.sh/acme.sh.log`
- 更新钩子日志：`/var/log/cert-renew.log`

### Q3: 证书更新后 sing-box 没有重启？
A: 检查：
1. `/root/cert-renew-hook.sh` 是否可执行：`chmod +x /root/cert-renew-hook.sh`
2. sing-box 服务状态：`systemctl status sing-box`
3. 更新钩子日志：`tail /var/log/cert-renew.log`

### Q4: 如何禁用自动更新？
A: 不建议禁用，但如果必须：
```bash
# 停用 acme.sh cron 任务
~/.acme.sh/acme.sh --uninstall-cronjob
```

### Q5: 更换域名后需要重新配置吗？
A: 是的，申请新域名证书后，需要重新运行配置脚本：
```bash
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/setup-cert-auto-renew.sh)
```

## 技术细节

### acme.sh --install-cert 参数说明

```bash
~/.acme.sh/acme.sh --install-cert -d your-domain.com \
    --cert-file /root/ygkkkca/cert.crt \              # 证书文件位置
    --key-file /root/ygkkkca/private.key \            # 私钥文件位置
    --fullchain-file /root/ygkkkca/cert.crt \         # 完整证书链位置
    --reloadcmd "bash /root/cert-renew-hook.sh your-domain.com"  # 更新后执行的命令
```

### 证书更新检测机制

- acme.sh 使用 cron 任务每天检查证书
- 默认在证书过期前 30 天开始尝试更新
- 更新成功后执行 `--reloadcmd` 指定的命令
- Let's Encrypt 证书有效期为 90 天

## 维护建议

1. **定期检查证书状态**（每月一次）
   ```bash
   openssl x509 -in /root/ygkkkca/cert.crt -noout -dates
   ```

2. **监控更新日志**
   ```bash
   tail -f /var/log/cert-renew.log
   ```

3. **确保 cron 服务运行**
   ```bash
   systemctl status cron  # Debian/Ubuntu
   systemctl status crond # CentOS/RHEL
   ```

4. **备份证书**（建议每月）
   ```bash
   cp /root/ygkkkca/cert.crt /root/backup/cert_$(date +%Y%m%d).crt
   cp /root/ygkkkca/private.key /root/backup/private_$(date +%Y%m%d).key
   ```

## 更新记录

- 2025-01-XX：初始版本，修复证书自动更新问题
