# GitHub 发布指南

**中文** | [English](RELEASING.en.md) · [返回 README](../README.md)

## 首次上传

在 GitHub 创建一个空仓库，把本项目源码推送过去。仓库名可自定，Actions 使用 `github.repository`，不用修改工作流中的 owner。README 使用仓库相对链接。

如果当前目录还不是 Git 仓库：

```bash
git init -b main
git add .
git commit -m "Initial release of DoubaoCaret"
git remote add origin git@github.com:YOUR_ACCOUNT/YOUR_REPOSITORY.git
git push -u origin main
```

替换命令里的账号和仓库名。若已有 Git 仓库/remote，只需正常提交和推送。检查提交内容没有证书、私钥、`.toolchain/`、`build/` 或 `dist/`；这些已在 `.gitignore` 中。`BUILD-REPORT.md` 是本地验证记录，也不作为公开文档提交。

在仓库 Settings → Actions → General 允许 GitHub Actions 和使用的官方 actions。组织策略必须允许发布任务获得 `contents: write`。无需 PAT，也无需把个人 GitHub Token 放到 Secrets；发布使用自动提供的 `GITHUB_TOKEN`。

## 默认发布：无证书测试包

**没有苹果签名证书时，直接使用此流程即可。** 不需要注册付费开发者账号，也不需要创建自签名证书。不要添加苹果签名 Secrets；`MACOS_SIGNING_MODE` 保持未设置（或设为 `adhoc`）。若之前设成了 `developer-id-notarized`，请删除该变量或改回 `adhoc`。

ad-hoc 签名不代表 Apple 已验证开发者身份，也不包含公证。用户首次打开下载包时可能需要在系统设置 → 隐私与安全性中选择“仍要打开”；更新后辅助功能/输入监控权限可能需要重新授权，参见 [权限指南](PERMISSIONS.md)。保持安装路径 `/Applications/DoubaoCaret.app` 和 Bundle ID 不变，但这不能保证 ad-hoc 更新保留授权。以后取得 Developer ID 证书时，再启用下方可选流程。

1. 修改 `Resources/Info.plist`：`CFBundleShortVersionString` 为版本（如 `0.1.2`），`CFBundleVersion` 为递增正整数。
2. 在 `CHANGELOG.md` 添加对应 `[0.1.2]` 段，中英文均写入；不要把实际修改仅放在 Unreleased。
3. 提交推送，等 **macOS CI** 通过。
4. 对该提交打标签并推送：

```bash
git tag -a v0.1.2 -m "DoubaoCaret 0.1.2"
git push origin v0.1.2
```

不配置任何自定义 Secret 即可发布。`MACOS_SIGNING_MODE` 默认 `adhoc`。GitHub 的 macOS runner 编译两个架构，不下载或分发仓库本地交叉编译 SDK。

预发布可使用 `v0.1.2-rc.1`，应用版本和 changelog 仍为 `0.1.2`；工作流会设置 GitHub prerelease 标志。只接受 `vX.Y.Z` 及预发布后缀，版本不匹配会在构建前失败。

## 自动执行的步骤

`release.yml`：校验版本 → 纯逻辑测试 → macOS 通用构建 → 签名/图标/ZIP/篡改测试 → 可选正式签名和公证 → 最终验证 → AppKit 启动 smoke test → 生成发布文件 → 独立发布任务再次校验 SHA-256 → 创建 Release。

Release 包含：

- `DoubaoCaret-v0.1.2-macos-universal.zip`
- `SHA256SUMS`：ZIP 和构建元数据的 SHA-256
- `build-metadata.json`：版本、源码提交、架构、最低系统、签名模式及 ZIP 哈希

页面说明从对应 changelog 生成，包含中英文安装方式、签名状态和已知限制。默认 ad-hoc 发布会明确注明未经 Apple 公证。

## 可选：Developer ID 签名与公证

在 Settings → Secrets and variables → Actions 添加 Repository variable：

| Variable | Value |
|---|---|
| `MACOS_SIGNING_MODE` | `developer-id-notarized` |

添加以下 Repository secrets：

| Secret | 内容 |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | 含私钥的 Developer ID Application `.p12` 文件，Base64 编码 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的非空密码 |
| `MACOS_SIGN_IDENTITY` | 完整身份名称，如 `Developer ID Application: Example Name (TEAMID)` |
| `APPLE_NOTARY_KEY_P8_BASE64` | 用于 notarytool 的 App Store Connect 团队 API `.p8` 私钥，Base64 编码 |
| `APPLE_NOTARY_KEY_ID` | 该 API Key 的 Key ID |
| `APPLE_NOTARY_ISSUER_ID` | 对应团队 API Key 的 Issuer ID |

本流程使用团队 API Key；未实现个人 API Key/Apple ID 密码分支。证书需有效并具有私钥；API Key 需具备 Apple 公证所需权限。准备方式参考 [Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

在本机将文件转换为 Base64，直接写入 GitHub Secret；不要提交编码结果到仓库或粘贴到 Issue。Base64 不是加密。启用此模式后，任何缺失 Secret、签名或公证失败都会阻止发布，不会静默降级为测试包。

临时 Keychain 和凭据文件在步骤结束时清理；私钥只在签名步骤环境中提供。PR CI 不读取这些 Secrets。Developer ID + Hardened Runtime 签名后，工作流提交公证、等待 Accepted、staple/validate、执行 Gatekeeper assessment，再重新打包。

## 重跑与排错

- **构建失败**：修复后发新提交和新版本标签；不要让既有发布标签指向另一份代码。
- **发布前临时失败**：可在 Actions 重跑失败任务。已有同名 Release 时会拒绝替换资产；不会使用 `--clobber`。若首次创建失败遗留草稿，应先检查并处理草稿，再重试。
- **权限 403**：检查组织/仓库 Actions 策略；只有 publish job 请求 `contents: write`。
- **版本不匹配**：修正 plist/changelog 后新建正确标签；不要只改 ZIP 文件名。
- **公证拒绝**：日志中会给出状态和 submission ID，使用 Apple 工具查看详情。
- **用户更新丢权限**：见 [权限指南](PERMISSIONS.md)。稳定签名通常改善升级识别，但不自动授予权限。

本地可验证发布文件准备（替换真实仓库及提交）：

```bash
python3 scripts/validate-version.py v0.1.2
python3 scripts/prepare-release.py --tag v0.1.2 \
  --repository YOUR_ACCOUNT/YOUR_REPOSITORY --commit "$(git rev-parse HEAD)" --signing adhoc
```

输出在 `dist/release/v0.1.2/`，不会调用 GitHub 或公开任何内容。只有标签触发的 publish job 会创建公开 Release。自动测试不能代替真实豆包、编辑器 caret、全屏和 CPU 验收。
