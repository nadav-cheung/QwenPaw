# B CLI 命令参考

> **源码依据**: `src/qwenpaw/cli/main.py` — Click 懒加载命令组，所有子命令按需导入以减少启动延迟。

## 全局选项

| 选项 | 说明 |
|------|------|
| `--host HOST` | API 服务器监听地址 |
| `--port PORT` | API 服务器监听端口 |
| `--version` | 显示 QwenPaw 版本号 |
| `-h, --help` | 显示帮助信息 |

## 命令列表

### 初始化与启动

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw init` | `cli/init_cmd.py` | 初始化工作目录，交互式配置 API Key 和默认模型 |
| `qwenpaw init --defaults` | — | 使用默认配置快速初始化 |
| `qwenpaw app` | `cli/app_cmd.py` | 启动 FastAPI 服务器（Web UI + API） |
| `qwenpaw app --port 8080` | — | 指定端口启动 |

### 诊断与维护

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw doctor` | `cli/doctor_cmd.py` | 系统诊断：检查 Python 环境、依赖、API Key、Provider 可达性 |
| `qwenpaw update` | `cli/update_cmd.py` | 更新 QwenPaw 到最新版本 |
| `qwenpaw shutdown` | `cli/shutdown_cmd.py` | 安全关闭正在运行的服务 |
| `qwenpaw clean` | `cli/clean_cmd.py` | 清理临时文件和缓存 |
| `qwenpaw uninstall` | `cli/uninstall_cmd.py` | 卸载 QwenPaw |

### Agent 管理

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw agents` / `qwenpaw agent` | `cli/agents_cmd.py` | 列出、创建、删除、配置 Agent |

### 渠道管理

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw channels` / `qwenpaw channel` | `cli/channels_cmd.py` | 管理消息渠道（添加、配置、启停） |

### 模型管理

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw models` | `cli/providers_cmd.py` | 管理 LLM Provider（添加/删除模型、配置 API Key） |

### 技能管理

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw skills` | `cli/skills_cmd.py` | 管理技能池（安装、卸载、列表、搜索） |

### 定时任务

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw cron` | `cli/cron_cmd.py` | 管理定时任务（创建、列表、删除、启停） |

### 对话管理

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw chats` / `qwenpaw chat` | `cli/chats_cmd.py` | 管理对话会话 |

### 环境变量

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw env` | `cli/env_cmd.py` | 管理持久化环境变量 |

### 守护进程

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw daemon` | `cli/daemon_cmd.py` | 管理后台守护进程 |

### 认证

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw auth` | `cli/auth_cmd.py` | 管理 API 认证 Token |

### 插件

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw plugin` | `cli/plugin_commands.py` | 管理插件（安装、卸载、列表） |

### ACP 协议

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw acp` | `cli/acp_cmd.py` | ACP 智能体通信协议管理 |

### Mission 模式

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw mission` | `cli/mission_cmd.py` | 管理 Mission（任务模式） |

### 任务管理

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw task` | `cli/task_cmd.py` | 管理异步任务 |

### 桌面模式

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw desktop` | `cli/desktop_cmd.py` | 启动桌面应用模式 |

## 懒加载设计

CLI 采用 `LazyGroup` 模式（`cli/main.py:58-92`），子命令在首次调用时才导入：

```python
class LazyGroup(click.Group):
    """支持懒加载子命令的 Click Group"""

    lazy_subcommands = {
        "app": ("qwenpaw.cli.app_cmd", "app_cmd", ".app_cmd"),
        "channels": ("qwenpaw.cli.channels_cmd", "channels_group", ".channels_cmd"),
        # ... 20+ subcommands
    }
```

设计目的：`qwenpaw --help` 响应时间 < 100ms，避免导入所有依赖。

## 别名

| 命令 | 别名 |
|------|------|
| `agents` | `agent` |
| `channels` | `channel` |
| `chats` | `chat` |

---

*基于源码 `src/qwenpaw/cli/main.py` (v1.1.2)*
*最后更新：2026-05-10*
