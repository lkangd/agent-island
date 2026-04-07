# Agent 扩展指南

这份文档面向后续开发者，目标是说明如何给 AgentIsland 接入一个新的 hook-capable agent，同时避免让 UI 再去理解一套新的原始协议。

相关文档：

- [文档索引](./README.zh.md)
- [内部 Hook 协议](./internal-hook-protocol.zh.md)
- [多 Agent 架构草案](./multi-agent-architecture.zh.md)

## 核心原则

新增智能体必须沿用同一套分层模型：

1. 官方 Hook 协议
2. 智能体专属适配器
3. AgentIsland 内部 Hook 协议
4. 共享的 Swift 运行时和 UI

不要让新增智能体直接把原始官方事件名带进 UI，除非确实没有合理的内部映射方式。

## 哪些东西必须稳定

UI 和状态机应继续依赖内部协议，尤其是：

- `internal_event`
- `permission_mode`
- `extra`

新增智能体的第一目标不是“让 UI 识别新事件名”，而是“把官方协议映射进这三个稳定入口”。

如果一时拿不准某个字段该不该进入稳定协议，优先放进 `extra`，等确认它具备跨智能体的通用价值后再考虑升级成稳定字段。

## 接入清单

### 1. 添加 Rust 适配器

在下面目录新增一个适配器：

```text
bridge-rs/src/adapter/
```

建议职责：

- 解析官方 payload
- 判断哪些事件应该发出
- 计算共享 `status`
- 计算 `internal_event`
- 计算 `permission_mode`
- 组装 `extra`
- 生成官方权限响应 JSON

然后在下面位置注册：

- `bridge-rs/src/adapter/mod.rs`
- `bridge-rs/src/protocol.rs`

### 2. 把官方事件映射到内部事件

新增智能体应尽量映射到现有稳定内部事件：

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

如果该智能体存在审批流，也应显式产出 `permission_mode`。

### 3. 定义审批行为

你需要明确三件事：

- 哪个官方事件触发审批
- 审批模式是 `native_app` 还是 `terminal`
- 如何把 allow / deny 转成该智能体官方要求的响应 JSON

注意：响应格式仍然必须是智能体专属的。共享的是内部协议，不是官方回包格式。

### 4. 添加安装和修复逻辑

更新：

```text
AgentIsland/Services/Hooks/AgentHookPlugin.swift
```

需要处理：

- 新插件的注册
- 官方 hook 事件配置
- install / repair / uninstall
- capability 元数据

### 5. 接入 Swift runtime

必要时更新智能体枚举和能力定义，但 Swift 业务逻辑仍应优先围绕内部协议。

重点文件：

- `AgentIsland/Models/AgentPlatform.swift`
- `AgentIsland/Services/Hooks/AgentPermissionAdapter.swift`
- `AgentIsland/Services/Hooks/HookSocketServer.swift`
- `AgentIsland/Models/SessionEvent.swift`

### 6. 正确使用 `extra`

`extra` 是智能体专属信息的透传位。

适合放进 `extra` 的内容：

- 官方事件元数据
- matcher 名称
- 命令文本
- 升权提示
- 智能体专属调试字段

不应该放进 `extra` 的内容：

- 规范化后的业务语义
- 统一审批状态
- 已经属于稳定字段的核心信息

### 7. 添加测试

至少补两类测试：

#### 事件映射测试

在 `bridge-rs` 中验证：

- 原始官方事件名被保留
- `internal_event` 正确
- `permission_mode` 正确
- 关键 `extra` 字段存在

#### 权限响应测试

验证：

- allow 回包格式
- deny 回包格式
- 如果该智能体允许“无回包”路径，也要覆盖

### 8. 更新文档

接入新增智能体后，至少同步更新：

- `README.md`
- `README.zh.md`
- `docs/internal-hook-protocol.md`

建议至少写清楚：

- 官方 hook 入口
- 审批入口
- 内部事件映射
- 当前验证状态

## 推荐顺序

1. 新增 Rust adapter
2. 补 dispatch 测试
3. 补 permission response 测试
4. 添加 installer 支持
5. 接通 Swift runtime
6. 验证构建
7. 更新文档

## 当前参考实现

可以直接参考这三个智能体：

- Claude
  - 官方审批入口：`PermissionRequest`
- Codex
  - 官方审批入口：`PreToolUse`
- Gemini
  - 官方审批入口：`BeforeTool`

这三者最终都映射到同一个内部审批事件：

- `permission_requested`

后续新增智能体时，只要官方语义允许，优先复用这条内部路径，而不是重新发明一套 UI 事件。
