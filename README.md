# Dia 中文补丁助手

一个本地原生 macOS 工具：检测 Dia Browser 官方更新，安全备份并重新安装非官方简体中文补丁。

> 非官方项目，与 The Browser Company、Dia 或 Atlassian 没有隶属或授权关系。

## 功能

- 显示 Dia 版本、签名、补丁状态和覆盖级别。
- 一键安装 / 重新安装中文补丁。
- 使用本次安装前的同版本完整备份恢复官方 Dia。
- 可选后台自动检查：每 5 分钟检查一次，仅在 Dia 已退出时安装。
- 对未知签名、不兼容结构和跨 Build 恢复保持关闭失败。
- 安装失败时调用上游事务逻辑自动回滚。

## 系统要求

- macOS 14 或更高版本
- Apple Silicon
- Dia 安装在 `/Applications/Dia.app`

## 安装

从 [Releases](https://github.com/yyxwz/dia-zh-helper/releases) 下载 `Dia中文补丁助手-1.0.0.zip`，解压后将应用拖入“应用程序”。

首次打开后：

1. 点击 **安装 / 重新安装**；
2. 根据需要开启 **Dia 更新后自动重装**；
3. 如需回到官方签名，点击 **恢复官方版**。

自动模式不会强制退出正在使用的 Dia。检测到官方更新后，它会等待 Dia 退出，再创建同版本备份并安装兼容补丁。

## 构建

需要 Xcode Command Line Tools：

```zsh
chmod +x build.zsh
./build.zsh
```

构建脚本会：

1. 下载 `dia-zh-patch v0.1.0-rc.2`；
2. 校验固定 SHA-256；
3. 应用 Dia 1.56+ 的 APS entitlement 兼容修复；
4. 编译原生 AppKit 应用并生成 ad-hoc 签名的 `.app` 与 ZIP。

产物位于 `outputs/`。

## 自动检查机制

开启开关后，应用创建用户级 LaunchAgent：

```text
~/Library/LaunchAgents/io.github.yyxwz.dia-zh-helper.auto.plist
```

后台任务只读检查状态；只有同时满足“官方签名、结构兼容、Dia 未运行”时才执行安装。日志位于：

```text
~/Library/Logs/DiaZhHelper.log
```

## 已知限制

- Dia 自动更新会覆盖补丁；本工具用于更新后自动重装。
- 未经上游验证的新 Build 默认只进入安全的 `core` 模式，不强制套用旧 WebUI 规则。
- 补丁使用本机 ad-hoc 签名，Apple Team ID 绑定的推送通知、关联域名、钥匙串组和 WebAuthn 等能力可能不可用。
- 若新版 Dia 改变签名权限或包结构，工具会停止自动安装，等待兼容更新。

## 上游与许可证

- 补丁核心：[AYangZi/dia-zh-patch](https://github.com/AYangZi/dia-zh-patch)
- 本项目：MIT License
- 第三方说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
