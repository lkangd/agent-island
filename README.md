<div align="center">
  <img src="AgentIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">AgentIsland</h3>
  <p align="center">
    A macOS menu bar app that brings Dynamic Island-style notifications to Claude Code and other agent CLI sessions.
    <br />
    <br />
    <a href="https://github.com/javen-yan/agent-island/releases/latest" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/github/v/release/javen-yan/agent-island?style=rounded&color=white&labelColor=000000&label=release" alt="Release Version" />
    </a>
    <a href="#" target="_blank" rel="noopener noreferrer">
      <img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/javen-yan/agent-island/total?style=rounded&color=white&labelColor=000000">
    </a>
  </p>
</div>

## Features

- **Notch UI** — Animated overlay that expands from the MacBook notch
- **Live Session Monitoring** — Track multiple Claude, Codex, and Gemini sessions in real-time
- **Permission Approvals** — Approve or deny tool executions directly from the notch
- **Chat History** — View full conversation history with markdown rendering
- **Auto-Setup** — Hooks install automatically on first launch

## Requirements

- macOS 15.6+
- Claude Code CLI
- Optional: Codex CLI, Gemini CLI

## Install

Download the latest release or build from source:

```bash
./scripts/build.sh
```

## GitHub Actions 自动构建

项目已添加 `main` 分支和 `v*` 标签推送的自动构建流程：  
- 工作流文件：`.github/workflows/ci-build.yml`
- 会自动：
  - 编译 Rust bridge（二进制）
  - 构建 `Agent Island.app`
  - 把 `agent-island-bridge` 自动打进 `Contents/Resources/agent-island-bridge`
  - 打包成 `AgentIsland-<版本>.dmg` 与 `AgentIsland-<版本>-unsigned.zip`
  - 上传到 Actions Artifact（`agentisland-macos-artifacts`）
- 当推送 `v*` 标签时，会自动创建 GitHub Release 并附带上述产物

本地构建如需跳过签名（适配 CI），可设置：
```bash
AGENT_ISLAND_NO_SIGN=1 ./scripts/build.sh
```

### Bridge 运行时分发规则（固定）

默认流程只有一个来源：
- 打包时把 `agent-island-bridge` 放入 `Agent Island.app/Contents/Resources/agent-island-bridge`。
- App 启动/Repair 时，优先从 bundle Resources 读取该二进制；
- 再复制到 `~/.agent-island/hooks/agent-island-bridge` 供 Claude/Codex/Gemini 使用。

因此用户不需要手动放置 bridge 文件，`Repair`/首次安装会自动完成分发。

## 图标重设计（AppIcon）

项目当前可替换图标仅为 App 图标（`AppIcon.appiconset`），系统内其他 UI 图标使用的是 SF Symbols。

一键替换流程（推荐）：
1. 准备一张正方形 PNG（建议 2048x2048 或更高，透明背景）。
2. 执行：
```bash
./scripts/update-app-icon.sh /path/to/new/icon-1024.png
```
3. 直接提交 `AgentIsland/Assets.xcassets/AppIcon.appiconset` 下的图片变更。

如果你还想把状态栏/按钮里的 SF Symbols 换成统一自定义图标，我可以再帮你加一套 `Images.xcassets` 并做批量替换。

### 已做「图标统一入口」改造（持续替换中）

我已新增统一入口 `Image(agentIcon:)`，现在 UI 会优先加载自定义资产，缺失时自动回退 SF Symbols。  
实现位置：
- [AgentIsland/Utilities/AgentIcon.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Utilities/AgentIcon.swift)

当前图标映射名示例：
- `agenticon-terminal`, `agenticon-gear`, `agenticon-trash`, `agenticon-terminal`, `agenticon-chat`, `agenticon-bubble-fill`, ...

后续只需按命名约定补齐 `AgentIsland/Assets.xcassets` 下的自定义图片集即可完成整站视觉统一。

## How It Works

Agent Island installs hooks for supported agents and communicates session state via a Unix socket. The active bridge runtime is the Rust binary `agent-island-bridge`, with source-based routing such as `agent-island-bridge --source codex`.

The legacy Python bridge source is still kept in-repo as reference material under [`reference/bridge`](reference/bridge) while the runtime stays unified on the Rust entrypoint.

Internally, agent integrations are now modeled as hook plugins with declared capabilities, so future hook-enabled agents can be added without rebuilding the core monitoring pipeline.
The settings menu now surfaces detected agent plugins and their installation/capability status.
The current multi-agent architecture draft is documented in [`docs/multi-agent-architecture.md`](docs/multi-agent-architecture.md).
The in-repo Rust bridge lives at [`bridge-rs`](bridge-rs) and is the single source-routed bridge runtime.

When Claude needs permission to run a tool, the notch expands with approve/deny buttons—no need to switch to the terminal.

## Analytics

Agent Island uses Mixpanel to collect anonymous usage data:

- **App Launched** — App version, build number, macOS version
- **Session Started** — When a new supported agent session is detected

No personal data or conversation content is collected.

## License

Apache 2.0
