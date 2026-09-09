# Contributing / 参与贡献

## English

Please describe the problem and reproduction before changing detection heuristics. For bugs include the app/Doubao/macOS versions, target application, display mode, permissions and copied caret diagnostics. Do not include keystrokes, private text, certificates or tokens.

Use the [development guide](docs/DEVELOPMENT.en.md) to build and test. Run state/geometry tests for detection changes; run artifact and release tests for packaging/workflow changes. State which checks ran and which require a Mac. Avoid presenting mouse fallback as successful caret support or compilation as complete runtime validation.

Keep changes focused, update Chinese and English documentation together, preserve upstream license notices, and explain user-visible behavior and verification in the PR. Never infer English solely from absent candidates, scan whole AX trees at high frequency, or weaken signing identity to work around permissions. No certificate/private key or SDK should be committed.

## 中文

修改检测策略前，请说明问题和复现步骤。Bug 请提供工具、豆包、macOS 和目标应用版本，显示模式、权限以及复制的 caret 诊断。不要上传输入内容、私密文本、证书或 Token。

按[开发指南](docs/DEVELOPMENT.md)构建和测试。检测改动运行状态/坐标测试；打包和工作流改动运行产物与发布工具测试。明确哪些检查已执行、哪些需要 Mac，不把 mouse fallback 当作 caret 成功，也不把编译通过当作完整运行验收。

保持改动聚焦，同步中英文文档，保留许可证；PR 描述用户可见变化及验证。不能从缺失候选窗推断英文，不能高频扫描完整 AX 树，也不能为绕过授权削弱签名身份。不提交证书私钥或 SDK。
