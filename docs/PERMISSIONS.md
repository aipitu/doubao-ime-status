# 更新时的权限与签名

**中文** | [English](PERMISSIONS.en.md)

## 为什么测试包更新后可能需要重新授权

本项目发行的测试包使用 ad-hoc 签名，没有固定证书。macOS TCC 不仅看应用名称和 bundle ID，也会检查代码身份。[Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)说明 ad-hoc 的 designated requirement 与具体代码版本绑定。因此每次重编译可能让已有授权失效，即使系统设置仍显示开启。

固定 `local.doubao-caret` 和 `/Applications/DoubaoCaret.app` 是必要的稳定配置，但不能单独解决 ad-hoc 版本变化问题。不能用仅检查 bundle ID 的宽松签名 requirement 取代真实签名身份，也不应修改 TCC 数据库或关闭 SIP。

## 0.1.2 的简化操作

菜单或设置 → **权限设置与更新修复**：

1. 可以分别打开辅助功能、输入监控，并触发系统授权提示。
2. 「重新检测权限」重新建立监听，处理系统已授权但监听尚未恢复的情况，不重置授权。
3. 更新后旧授权失效时，点击「复制本应用的权限修复命令」。退出本应用后，在终端粘贴执行，再到系统设置允许两项权限。

固定安装路径下的命令如下（无需 `sudo`）：

```bash
/usr/bin/tccutil reset Accessibility local.doubao-caret
/usr/bin/tccutil reset ListenEvent local.doubao-caret
/usr/bin/open '/Applications/DoubaoCaret.app' --args --permissions
```

这些命令仅重置本应用的两个服务，不影响其他应用。它们清除旧授权，**不能自动授予权限**。macOS 要求用户在系统设置确认；部分版本仍可能需要重新添加条目或重启应用。Apple 的[重置受保护资源权限文档](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos)说明了 service + bundle ID 的重置范围。

## 长期保留更新授权

正式分发应使用同一个团队的稳定 Developer ID 签名，并完成 Apple 公证。在 bundle ID、签名识别条件和安装路径保持兼容时，系统通常能识别为同一应用的更新。公证解决分发检查；稳定代码身份才是权限延续的关键。已有 ad-hoc 版本首次迁移到新签名身份时，仍可能需要重新授权一次。

本地开发测试也可使用固定的本机代码签名证书（包括适当配置的自签名证书），但它不等于 Developer ID 或 Apple 公证，具体 TCC 行为需在目标 macOS 验证。私钥应留在用户本机 Keychain，不提交到项目。

本项目提供下载后在本机重新签名的脚本，不需要把证书或私钥发给开发端：

```bash
security find-identity -v -p codesigning
# 先退出应用并完成替换。每次使用同一个既有证书身份。
SIGN_IDENTITY='你的固定代码签名身份' bash scripts/sign-update-macos.sh /Applications/DoubaoCaret.app
```

如果从源码在 Mac 上构建，现有 `SIGN_IDENTITY='…' bash scripts/build-macos.sh` 也支持固定证书。没有可用签名身份时，继续使用测试包的修复入口即可；本次更新没有悄悄生成、信任或安装任何证书。
