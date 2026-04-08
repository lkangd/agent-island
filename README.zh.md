<div align="center">
  <img src="AgentIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h1 align="center">AgentIsland</h1>
  <p align="center">
    面向 Claude、Codex 和 Gemini 会话的 macOS 菜单栏助手。
    <br>
    将权限审批、会话可见性和工具时间线统一到一个入口。
  </p>
  <p align="center">
    <a href="https://github.com/javen-yan/agent-island/releases/latest" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/github/v/release/javen-yan/agent-island?style=rounded&color=white&labelColor=000000&label=release" alt="最新版本">
    </a>
    <a href="#" target="_blank" rel="noopener noreferrer">
      <img alt="下载次数" src="https://img.shields.io/github/downloads/javen-yan/agent-island/total?style=rounded&color=white&labelColor=000000">
    </a>
  </p>
</div>

[英文文档](./README.md)

更多文档入口见：[文档索引](./docs/README.zh.md)

## 项目简介

AgentIsland 是一个面向终端 AI 智能体的 macOS 菜单栏应用，用来把会话里的关键信息收敛到统一入口，尽量减少“在终端、编辑器、审批弹窗之间来回跳”的成本。

它当前主要解决三类问题：

- 权限审批
- 工具执行状态
- 会话列表
- 会话历史
- 运行态透视

当前重点支持：

- Claude
- Codex
- Gemini

三者都按各自官方 hooks 协议接入，但在进入 UI 之前会先映射到 AgentIsland 的内部稳定协议。

## 当前能力

- 菜单栏入口和展开式面板
- 多会话展示
- 工具执行时间线
- 权限审批闭环
- 会话历史查看
- Hook 安装、修复、重新分发
- 内部协议层：`internal_event`、`permission_mode`、`extra`

## 当前支持矩阵

| Agent | 官方 hook 入口 | 当前审批入口 | 内部审批事件 | 状态 |
| --- | --- | --- | --- | --- |
| Claude | Claude Code hooks | `PermissionRequest` | `permission_requested` | 已验证 |
| Codex | Codex hooks | `PreToolUse` (`Bash`) | `permission_requested` | 已验证 |
| Gemini | Gemini hooks | `BeforeTool` | `permission_requested` | 已接入，建议继续扩大验证 |

## 架构概览

AgentIsland 当前采用三层模型：

1. 官方协议层
   Claude / Codex / Gemini 各自按官方 hooks 协议触发事件。

2. 内部协议层
   Rust bridge 会把官方事件映射成统一 `HookPayload`，其中稳定字段是：
   - `internal_event`
   - `permission_mode`
   - `extra`

3. UI / 状态层
   Swift 运行时和 UI 优先消费内部协议，不直接依赖三家官方事件名。

核心原则：

- 官方差异留在适配器层
- UI 交互逻辑尽量固定
- 智能体特有细节通过 `extra` 透传

## 文档导航

- [文档索引](./docs/README.zh.md)
- [内部 Hook 协议（英文）](./docs/internal-hook-protocol.md)
- [内部 Hook 协议（中文）](./docs/internal-hook-protocol.zh.md)
- [多 Agent 架构草案（英文）](./docs/multi-agent-architecture.md)
- [多 Agent 架构草案（中文）](./docs/multi-agent-architecture.zh.md)
- [Agent 扩展指南（英文）](./docs/agent-extension-guide.md)
- [Agent 扩展指南（中文）](./docs/agent-extension-guide.zh.md)
- [终端交互指南（英文）](./docs/terminal-interaction.md)
- [终端交互指南（中文）](./docs/terminal-interaction.zh.md)

## 快速开始

### 依赖

- macOS 15.6+
- Claude Code CLI
- 可选：Codex CLI、Gemini CLI

### 本地构建

```bash
./scripts/build.sh
```

默认会构建 app 和 Rust bridge，并完成打包。

### CI 产物

`main` 与 `v*` 标签会触发自动构建流程：

- 编译 Rust bridge
- 构建 `Agent Island.app`
- 将 `agent-island-bridge` 打入 App Bundle
- 打包 dmg / zip
- 标签发布时自动创建 Release

修复或首次安装时，应用会优先使用应用包内的 bridge，再分发到：

```bash
~/.agent-island/hooks/agent-island-bridge
```

本地如需跳过签名：

```bash
AGENT_ISLAND_NO_SIGN=1 ./scripts/build.sh
```

## 调试与排查

查看日志：

```bash
log stream --level debug --predicate 'subsystem == "com.agentisland"'
```

只看 hooks：

```bash
log stream --level debug --predicate 'subsystem == "com.agentisland" AND category == "Hooks"'
```

常见排查点：

- Codex 返回 `invalid pre-tool-use JSON output`
  - 检查 `hookSpecificOutput.permissionDecision`
  - 确认 bridge 为最新版本

- UI 状态与官方事件不一致
  - 先看 `internal_event`
  - 再看 `permission_mode`
  - 最后再回看原始 `event` 和 `extra`

- 审批卡死
  - 检查 `HookSocketServer` pending permission 是否泄漏

- 新接入 agent 后 UI 没反应
  - 先检查 bridge 载荷是否包含 `internal_event`
  - 再对照 [内部 Hook 协议](./docs/internal-hook-protocol.zh.md) 和 [Agent 扩展指南（中文）](./docs/agent-extension-guide.zh.md)

## 安全

- 权限决策通过本地 socket 回传
- 不依赖云端审批同步
- README 不默认记录会话正文

当前统计项：

- `App Launched`
- `Session Started`

## 目录

- `AgentIsland/`: macOS App 主体
- `bridge-rs/`: Rust bridge runtime
- `docs/`: 架构、协议、扩展文档
- `scripts/`: 构建与发布脚本

## 致谢

本项目基于 [farouqaldori/claude-island](https://github.com/farouqaldori/claude-island) 演化而来，保留并扩展了其桥接与通知思路。

## License

Apache 2.0
