# QuotaNest 1.10.0

- Mac 新增 **DeepSeek Harness 官方登录钱包**：复用本机已有登录，充值余额和赠送余额分开展示，支持人民币／美元；胶囊显示充值余额，与 CC Switch 的 DeepSeek API 余额保持独立。
- 移除 Kimi Code、MiniMax Code、Qoder、CodeBuddy 的实验适配；保留 Codex、Claude、Antigravity、ZCode，ZCode 不再标记实验性。ZCode 付费 Coding Plan 的真实账号验证仍未完成。
- 改进原生玻璃胶囊与弹窗的点击、焦点、定位和设置往返；从系统重新打开应用会自动展示详情，已显示时不会反向关闭。保留失焦及 Escape 关闭。
- 保留旧更新器要求的 Qoder 兼容占位资源，不包含 Qoder 适配代码。
- Windows 同步至 1.10.0，仍支持 Codex、Claude 和 CC Switch DeepSeek API 余额；本次未新增 Harness 官方登录或 Mac 玻璃界面功能。

本机 Mac 已通过真实 Harness 登录查询余额，并在安装后的界面点击刷新完成目视核验。未调用模型、购买或领取额度，未修改官方登录。解析、来源切换和双语界面使用测试数据验证。Windows 的构建、安装和界面检查由 CI 执行，不代替真实 Windows 11 账号及多屏验证。

macOS 13+（Intel / Apple Silicon），Windows 11 x64。Mac 为 ad-hoc 签名、未公证；Windows 未配置商业代码签名。

[中文说明](https://github.com/bloodkilory/QuotaNest/blob/v1.10.0/README.md) · [English documentation](https://github.com/bloodkilory/QuotaNest/blob/v1.10.0/README.en.md)
