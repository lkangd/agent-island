# 内部 Hook 协议

AgentIsland 采用两层 Hook 模型：

1. 各家官方 Hook 协议
2. AgentIsland 内部 Hook 协议

Claude、Codex、Gemini 以及未来新增的 agent，都应该把官方行为留在各自的适配器里。UI 和会话逻辑优先消费内部协议，而不是直接依赖官方事件名。

相关文档：

- [文档索引](./README.zh.md)
- [多 Agent 架构草案](./multi-agent-architecture.zh.md)
- [Agent 扩展指南（中文）](./agent-extension-guide.zh.md)

## 目标

- 保持 UI 和会话状态逻辑稳定
- 允许每个 agent 继续遵循自己的官方 Hook 协议
- 让新增 agent 的集成方式可预测
- 通过 `extra` 保留 agent 特有细节，而不污染核心契约

## 稳定字段

Rust bridge 会向 Swift runtime 输出这些稳定字段，封装在 `HookPayload` 里：

- `session_id`
- `cwd`
- `agent_type`
- `transcript_path`
- `event`
  原始官方 Hook 事件，仅用于诊断和兼容回退。
- `internal_event`
  AgentIsland 规范化后的事件，是业务主字段。
- `status`
  用于会话阶段判断的共享运行时状态。
- `permission_mode`
  规范化后的审批模式。
- `pid`
- `tty`
- `tool`
- `tool_input`
- `tool_use_id`
- `notification_type`
- `message`
- `extra`
  agent 特有信息的透传字段，用作非核心信息的扩展位。

## 内部事件

`internal_event` 当前使用这些值：

- `notification`
- `idle_prompt`
- `pre_compact`
- `session_started`
- `session_ended`
- `stopped`
- `subagent_stopped`
- `tool_will_run`
- `tool_did_run`
- `user_prompt_submitted`
- `permission_requested`
- `unknown`

UI 和状态逻辑应优先使用 `internal_event`，而不是原始 `event`。

## 审批模式

`permission_mode` 当前使用：

- `native_app`
- `terminal`

如果某个 agent 没有显式提供审批模式，Swift 侧仍可能退回到旧的基于 `status` 的兼容逻辑。新增集成只要涉及审批，就应该显式产出 `permission_mode`。

## 官方 Agent 映射

下面是当前各家官方事件到内部事件的映射方式。

### Claude

官方 Hook 协议：

- `SessionStart`
- `SessionEnd`
- `PreToolUse`
- `PostToolUse`
- `PermissionRequest`
- `Notification`
- `Stop`
- `SubagentStop`
- `PreCompact`
- `UserPromptSubmit`

内部映射重点：

- `PermissionRequest` -> `permission_requested`
- `PreToolUse` -> `tool_will_run`
- `PostToolUse` -> `tool_did_run`
- `Notification(idle_prompt)` -> `idle_prompt`

审批模式：

- `PermissionRequest` -> `native_app`

### Codex

官方 Hook 协议：

- `SessionStart`
- `PreToolUse`
- `PostToolUse`
- `UserPromptSubmit`
- `Stop`

当前依赖的官方行为：

- 审批由 `PreToolUse` 驱动
- 当前稳定匹配器是 `Bash`

内部映射重点：

- `PreToolUse` -> `tool_will_run`
- 触发审批的 `PreToolUse` -> `permission_requested`
- `PostToolUse` -> `tool_did_run`

审批模式：

- 触发审批的 `PreToolUse` -> `native_app`

### Gemini

AgentIsland 当前处理的官方 Hook 协议：

- `BeforeTool`
- `AfterTool`
- `SessionStart`
- `SessionEnd`
- `Notification`

内部映射重点：

- `BeforeTool` -> `tool_will_run`
- 触发审批的 `BeforeTool` -> `permission_requested`
- `AfterTool` -> `tool_did_run`
- `Notification(idle_prompt)` -> `idle_prompt`

审批模式：

- 触发审批的 `BeforeTool` -> `native_app`

## `extra` 使用约定

`extra` 用来承载不应该进入稳定核心契约的 agent 特有信息。

适合放进 `extra` 的内容：

- 官方事件元数据
- 匹配器名称
- 命令文本
- 升权标记
- agent 特有的调试上下文

不适合放进 `extra` 的内容：

- 会话标识
- 统一后的审批状态
- 规范化后的业务事件名
- 已经存在于稳定字段中的核心信息

当前示例：

- `officialEvent`
- `officialPermissionEvent`
- `toolMatcher`
- `commandText`
- `escalationRequested`

## 适配器职责

每个 agent 适配器都负责：

1. 解析官方载荷
2. 判断事件是否需要发出
3. 计算共享 `status`
4. 计算 `internal_event`
5. 计算 `permission_mode`
6. 填充 `extra`
7. 生成符合官方要求的权限响应 JSON

只有适配器层应该详细了解各家官方事件名。

## Swift 侧职责

Swift runtime 负责：

- 解码 bridge 载荷
- 优先使用 `internalEvent` 和 `permissionMode`
- 仅在兼容场景下回退到原始 `event`
- 保持 UI 逻辑不直接依赖各家官方事件名

关键文件：

- `AgentIsland/Services/Hooks/HookSocketServer.swift`
- `AgentIsland/Models/SessionEvent.swift`
- `AgentIsland/Services/State/SessionStore.swift`

## 新增 Agent

当你要接入一个新的 hook-capable agent 时：

1. 在 `bridge-rs/src/adapter/` 下新增官方适配器
2. 把官方事件处理细节留在适配器内部
3. 将官方事件映射到 `internal_event`
4. 只要涉及审批，就显式产出 `permission_mode`
5. 将非核心细节放进 `extra`
6. 在 `AgentHookPlugin.swift` 中补安装和修复逻辑
7. 为事件映射补 dispatch 测试
8. 为官方权限响应 JSON 补测试

不要让 UI 直接理解新 agent 的原始官方事件名，除非确实没有合理的内部映射方式。

具体接入顺序和实现清单请继续参考 [Agent 扩展指南（中文）](./agent-extension-guide.zh.md)。
