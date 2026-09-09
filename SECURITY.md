# Security / 安全说明

## English

The runtime app has no networking, telemetry or keystroke logging. Accessibility and input monitoring are sensitive permissions: install only builds whose source/release you trust. Ad-hoc signatures do not establish a verified publisher identity; SHA-256 checksums detect changed downloads, not whether the publisher is trustworthy.

Report security issues privately using the repository's **Security → Report a vulnerability** when the maintainer has enabled private vulnerability reporting. If unavailable, open an issue requesting a private contact without publishing exploit details or sensitive data. Maintainers should enable private reporting before public launch. There is currently no promised response SLA or maintained backport branch; fixes target the latest development/release line.

Never post signing keys, API keys, typed text or screenshots of secrets. CI secrets belong in GitHub Actions Secrets and are used only in the tag-triggered signing step. PR CI uses no signing credentials. Permissions are requested through macOS, not by editing TCC databases.

## 中文

程序运行时不联网、不上传遥测、不记录键入文字。辅助功能和输入监控属于敏感权限，请仅安装可信源码或发布来源。Ad-hoc 签名不提供已验证的发布者身份；SHA-256 检测下载变化，不证明发布者可信。

维护者启用私密漏洞报告后，请通过仓库 **Security → Report a vulnerability** 私下报告。如尚未启用，可创建仅请求私密联系渠道的 Issue，不公开利用细节或敏感数据。建议公开仓库前启用该功能。目前未承诺响应时限或旧版回补分支，修复面向最新开发/发布版本。

不要发布签名私钥、API Key、输入文本或含秘密的截图。CI 凭据存入 GitHub Actions Secrets，仅标签发布的签名步骤使用；PR CI 不使用签名凭据。权限通过 macOS 授权，不修改 TCC 数据库。
