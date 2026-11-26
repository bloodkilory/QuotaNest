# QuotaNest 1.10.1

- Mac 与 Windows 新增解析 Claude 新版接口 `limits` 中的 **Fable 周额度**：按其自身 `percent` 与重置时间展示，支持单独选择，保留“自动（默认）”按最低剩余计算。
- Mac 升级为 **Apple 原生全透明液态玻璃**（50% 透明度 tint），自绘高对比度单选圆环并增强图标及辅助文字在玻璃背景上的可读性。
- Mac 详情面板刷新按钮新增围绕符号圆心的原生连续旋转动画；修复弹窗打开后再次点击菜单栏胶囊不会收起的问题。
- Mac 关闭弹窗外层交互回弹、复用外层玻璃容器并在切换尺寸时采用原子定位缩放，消除切换页面与模型时的窗口弹动。
- Mac 优化 Antigravity 额度读取：抑制服务端同一重置周期内的轻微回弹抖动，胶囊百分比采用四舍五入与官方 `agy` 显示保持一致。
- Windows 同步至 1.10.1，包含 Fable 周额度支持。

本机 Mac 已完成全部单元测试、通用构建、严格签名及安装运行验证；Windows 端完成类型检查及 Rust 单元测试，最终安装包与 GUI 烟测由 GitHub Actions CI 在 Windows 环境执行（不替代真实 Windows 11 账号及多屏实机验证）。

macOS 13+（Intel / Apple Silicon），Windows 11 x64。Mac 为 ad-hoc 签名、未公证；Windows 未配置商业代码签名。

[中文说明](https://github.com/bloodkilory/QuotaNest/blob/v1.10.1/README.md) · [English documentation](https://github.com/bloodkilory/QuotaNest/blob/v1.10.1/README.en.md)
