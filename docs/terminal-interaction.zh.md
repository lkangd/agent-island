# 终端交互指南

本文档说明 AgentIsland 中的终端交互机制以及如何配置支持的后端。

## 概述

AgentIsland 的终端交互功能包括：

- 向 Agent 终端发送聊天输入
- 发送中断按键（`Esc`）
- 发送终止命令（根据 Agent 类型使用 `/exit` 或 `/quit`）
- 跳转到 Agent 终端会话

终端后端通过应用设置选择（`Terminal`：`tmux` 或 `cmux`）。

## 支持的后端

- `tmux`
- `cmux`

## 通用要求

- Agent 会话必须具有有效的终端上下文（TTY/会话映射）
- 后端可执行文件/Socket 必须可访问
- 后端访问权限必须允许 AgentIsland 操作

## tmux 配置

确保 `tmux` 已安装且在 PATH 中可用：

```bash
which tmux && tmux -V
```

## cmux 配置

### 1) CLI 设置

运行官方符号链接命令：

```bash
sudo ln -sf "/Applications/cmux.app/Contents/Resources/bin/cmux" /usr/local/bin/cmux
```

官方指南（CLI 设置部分）：

- https://cmux.com/docs/getting-started#CLI%20setup

验证：

```bash
which cmux && cmux --version
```

### 2) Socket 路径

AgentIsland 使用 cmux Socket API。确保 Socket 可访问：

- 默认路径：`/tmp/cmux.sock`
- 或通过 `CMUX_SOCKET_PATH` 环境变量指定自定义路径

验证：

```bash
ls "$CMUX_SOCKET_PATH"  # 或 ls /tmp/cmux.sock
```

### 3) 访问模式

cmux 访问模式必须允许 AgentIsland 连接（避免拒绝外部客户端访问）。

官方参考：

- https://cmux.com/docs/api#Access%20modes

如果看到以下提示：

`Access denied — only processes started inside cmux can connect`

请相应调整访问模式。

### 4) API 探测

测试 cmux API 连通性：

```bash
printf '{"id":"probe","method":"system.identify","params":{}}\n' | nc -U "$CMUX_SOCKET_PATH"
```

如果探测成功，AgentIsland 通常可以正常进行 cmux 目标解析和消息/按键传递。

## 故障排查清单

1. 确认 AgentIsland 中选择的后端与你的环境匹配。
2. 确认可执行文件/Socket 可用。
3. 确认访问模式允许 AgentIsland 连接。
4. 手动探测 API（`system.identify`）。
5. 检查应用日志：

```bash
log stream --level debug --predicate 'subsystem == "com.agentisland"'
```

如需 cmux 专属诊断信息，可按 category `CmuxRPC` 进行过滤。
