# Dia 中文补丁助手

一个本地原生 macOS 工具：检测 Dia Browser 官方更新，安全备份并重新安装非官方简体中文补丁。

> 非官方项目，与 The Browser Company、Dia 或 Atlassian 没有隶属或授权关系。

## 功能

- 实际校验 Dia 的签名和汉化资源，分别显示资源校验与启动检查状态。
- 一键检查并修复；恢复中断的安装，资源完整时无需重复安装。
- 安装时实时显示进度，防止助手在安装过程中被正常退出。
- 使用本次安装前的同版本完整备份恢复官方 Dia。
- 可选后台自动检查：每 5 分钟检查一次，仅在 Dia 已退出时安装。
- 对未知签名、不兼容结构和跨 Build 恢复保持关闭失败。
- 安装失败时调用上游事务逻辑自动回滚。

## 系统要求

- macOS 14 或更高版本
- Apple Silicon
- Dia 安装在 `/Applications/Dia.app`

## 安装

从 [Releases](https://github.com/yyxwz/dia-zh-helper/releases) 下载 `DiaZhHelper-1.0.1.zip`，解压后将应用拖入“应用程序”。

首次打开后：

1. 保存 Dia 中未保存的内容，点击 **检查并修复**，等待备份、安装和签名完成；
2. 根据需要开启 **Dia 更新后自动重装**；
3. 如需回到官方签名，点击 **恢复官方版**。

自动模式不会强制退出正在使用的 Dia。检测到官方更新后，它会等待 Dia 退出，再创建同版本备份并安装兼容补丁。

“核心汉化已校验”表示签名和补丁资源通过检查，不表示所有界面都已翻译。后台安装后保持 Dia 关闭，并显示待启动验证；点击 **打开并验证 Dia** 可以补做启动检查。重签名后，macOS 可能要求重新授权访问原有钥匙串，请自行在系统窗口处理，密码不要填入助手或日志。

## 构建

需要 Xcode Command Line Tools：

```zsh
chmod +x build.zsh
./build.zsh
./Tests/run.zsh
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

后台任务检查实际签名与资源；只有同时满足“官方签名、结构兼容、Dia 未运行”时才执行安装。手动和后台任务共用进程锁，避免并发写入；确认已失效的旧安装锁会归档。自动安装失败后暂停同一版本的重试，可在助手里手动检查并修复。日志位于：

```text
~/Library/Logs/DiaZhHelper.log
```

## 已知限制

- Dia 自动更新会覆盖补丁；本工具用于更新后自动重装。
- 助手固定使用 `core` 模式，覆盖菜单和部分界面；部分设置与 AI 页面仍可能为英文，不套用旧 WebUI 规则。
- 启动检查确认页面渲染进程出现，不代表所有网站、登录或 AI 功能均已验证。
- 助手使用本机 ad-hoc 签名，未经过 Apple 公证。
- 补丁使用本机 ad-hoc 签名，Apple Team ID 绑定的推送通知、关联域名、钥匙串组和 WebAuthn 等能力可能不可用。
- 若新版 Dia 改变签名权限或包结构，工具会停止自动安装，等待兼容更新。

## 上游与许可证

- 补丁核心：[AYangZi/dia-zh-patch](https://github.com/AYangZi/dia-zh-patch)
- 本项目：MIT License
- 第三方说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
