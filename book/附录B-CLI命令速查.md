# 附录B：CLI 命令速查

QwenPaw 的命令行入口为 `qwenpaw`，基于 Click 框架构建，支持 `-h`/`--help` 查看帮助。

全局选项：

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--host` | str | `127.0.0.1` | API 主机地址 |
| `--port` | int | `8088` | API 端口 |
| `--version` | flag | — | 显示版本号 |
| `-h` / `--help` | flag | — | 显示帮助信息 |

---

## 顶层命令一览

| 命令 | 说明 |
|------|------|
| `qwenpaw init` | 交互式初始化工作目录 |
| `qwenpaw app` | 启动 FastAPI 服务 |
| `qwenpaw desktop` | 启动桌面 WebView 窗口 |
| `qwenpaw shutdown` | 强制停止运行中的 QwenPaw 进程 |
| `qwenpaw update` | 从 PyPI 升级 QwenPaw |
| `qwenpaw uninstall` | 卸载 QwenPaw |
| `qwenpaw clean` | 清空工作目录 |
| `qwenpaw doctor` | 诊断检查 |
| `qwenpaw acp` | 以 ACP Agent 模式运行（stdio） |
| `qwenpaw task` | 无头单任务执行 |

---

## `qwenpaw init` — 初始化

| 选项 | 类型 | 说明 |
|------|------|------|
| `--force` | flag | 覆盖已有的 `config.json` 和 `HEARTBEAT.md` |
| `--defaults` | flag | 使用默认值，跳过交互提示（适用于脚本） |
| `--accept-security` | flag | 跳过安全确认（与 `--defaults` 搭配用于 Docker） |

---

## `qwenpaw app` — 启动服务

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--host` | str | `127.0.0.1` | 绑定地址 |
| `--port` | int | `8088` | 绑定端口 |
| `--reload` | flag | — | 启用热重载（仅开发） |
| `--log-level` | choice | `info` | 日志级别 |
| `--hide-access-paths` | 多值 | `/console/push-messages` | 隐藏的访问日志路径 |
| `--workers` | int | — | **已废弃**，始终为 1 |

---

## `qwenpaw models` — 模型与 Provider 管理

| 子命令 | 说明 |
|--------|------|
| `models list` | 列出所有 Provider 和当前配置 |
| `models config` | 交互式配置 Provider 和活跃模型 |
| `models config-key [PROVIDER_ID]` | 配置 Provider 的 API Key |
| `models set-llm` | 交互式设置活跃 LLM 模型 |
| `models add-provider PROVIDER_ID` | 添加自定义 Provider |
| `models remove-provider PROVIDER_ID` | 删除自定义 Provider |
| `models add-model PROVIDER_ID` | 向 Provider 添加模型 |
| `models remove-model PROVIDER_ID` | 从 Provider 移除用户添加的模型 |
| `models download REPO_ID` | 下载本地模型仓库 |
| `models local` | 列出已下载的本地模型 |
| `models remove-local MODEL_ID` | 删除已下载的本地模型 |

`add-provider` 选项：

| 选项 | 说明 |
|------|------|
| `-n` / `--name` | Provider 显示名称（必填） |
| `-u` / `--base-url` | 默认 API 基础 URL |
| `--api-key-prefix` | API Key 前缀 |

`download` 选项：

| 选项 | 说明 |
|------|------|
| `--source` / `-s` | 下载源：`huggingface`（默认）或 `modelscope` |

---

## `qwenpaw agents` — 多 Agent 管理

| 子命令 | 说明 |
|--------|------|
| `agents list` | 列出所有已配置的 Agent |
| `agents create` | 创建新 Agent |
| `agents delete AGENT_ID` | 删除 Agent |
| `agents chat` | Agent 间通信 |

`create` 选项：

| 选项 | 说明 |
|------|------|
| `--name` | Agent 名称（必填） |
| `--agent-id` | 显式指定 Agent ID，省略则自动生成 |
| `--description` | Agent 描述 |
| `--workspace-dir` | 工作空间目录 |
| `--language` | 语言设置 |
| `--template` | 内置模板 |
| `--skill` | 初始技能（可重复） |
| `--provider-id` | Provider ID |
| `--model-id` | 模型 ID |

`chat` 选项：

| 选项 | 说明 |
|------|------|
| `--from-agent` | 发送方 Agent ID |
| `--to-agent` | 接收方 Agent ID |
| `--text` | 消息文本 |
| `--session-id` | 会话 ID（复用上下文） |
| `--mode` | `stream`（增量）或 `final`（完整，默认） |
| `--background` | 提交后台任务 |
| `--task-id` | 检查后台任务状态 |
| `--timeout` | 超时秒数（默认 300） |
| `--json-output` | 输出完整 JSON |
| `--base-url` | 覆盖 API URL |

---

## `qwenpaw channels` — 频道管理

| 子命令 | 说明 |
|--------|------|
| `channels list` | 显示频道配置 |
| `channels config` | 交互式配置频道 |
| `channels install KEY` | 安装自定义频道模块 |
| `channels add KEY` | 安装并添加到配置 |
| `channels remove KEY` | 移除自定义频道 |
| `channels send` | 向频道发送消息 |

`send` 选项（全部必填）：

| 选项 | 说明 |
|------|------|
| `--agent-id` | Agent ID |
| `--channel` | 目标频道 |
| `--target-user` | 目标用户 ID |
| `--target-session` | 目标会话 ID |
| `--text` | 消息文本 |

---

## `qwenpaw chats` — 聊天会话管理

| 子命令 | 说明 |
|--------|------|
| `chats list` | 列出聊天会话 |
| `chats get CHAT_ID` | 查看聊天详情 |
| `chats create` | 创建新聊天 |
| `chats update CHAT_ID` | 更新聊天名称 |
| `chats delete CHAT_ID` | 删除聊天 |

通用选项：`--agent-id`（默认 `default`）、`--base-url`、`--user-id`、`--channel`

---

## `qwenpaw cron` — 定时任务管理

| 子命令 | 说明 |
|--------|------|
| `cron list` | 列出所有 Cron 任务 |
| `cron get JOB_ID` | 查看任务详情 |
| `cron state JOB_ID` | 查看运行时状态 |
| `cron create` | 创建任务（支持 `-f` JSON 文件或内联参数） |
| `cron delete JOB_ID` | 删除任务 |
| `cron pause JOB_ID` | 暂停任务 |
| `cron resume JOB_ID` | 恢复任务 |
| `cron run JOB_ID` | 立即触发一次运行 |

`create` 内联选项：

| 选项 | 说明 |
|------|------|
| `--type` | 任务类型：`text`（固定文本）或 `agent`（发给 Agent） |
| `--name` | 任务名称 |
| `--cron` | Cron 表达式（5 字段） |
| `--channel` | 投递频道 |
| `--target-user` | 目标用户 |
| `--target-session` | 目标会话 |
| `--text` | 消息内容 |
| `--timezone` | 时区 |
| `--enabled` / `--no-enabled` | 是否启用 |

---

## `qwenpaw skills` — 技能管理

| 子命令 | 说明 |
|--------|------|
| `skills list` | 列出所有技能及状态 |
| `skills config` | 交互式配置技能 |
| `skills info SKILL_NAME` | 查看技能详情 |

通用选项：`--agent-id`（默认 `default`）

---

## `qwenpaw env` — 环境变量管理

| 子命令 | 说明 |
|--------|------|
| `env list` | 列出所有已设置的环境变量 |
| `env set KEY VALUE` | 设置环境变量 |
| `env delete KEY` | 删除环境变量 |

---

## `qwenpaw daemon` — 守护进程命令

| 子命令 | 说明 |
|--------|------|
| `daemon status` | 显示守护进程状态 |
| `daemon restart` | 显示重启说明 |
| `daemon reload-config` | 重新加载配置 |
| `daemon version` | 显示版本和路径 |
| `daemon logs` | 查看日志尾部 |

通用选项：`--agent-id`（默认 `default`）

`logs` 选项：`-n` / `--lines`（默认 100，最大 2000）

---

## `qwenpaw plugin` — 插件管理

| 子命令 | 说明 |
|--------|------|
| `plugin install SOURCE` | 从本地路径或 URL 安装插件 |
| `plugin list` | 列出已安装的插件 |
| `plugin info PLUGIN_ID` | 查看插件详情 |
| `plugin uninstall PLUGIN_ID` | 卸载插件 |
| `plugin validate PATH` | 验证插件结构 |

`install` 选项：`--force`（强制重装）

---

## `qwenpaw mission` — 任务模式

| 子命令 | 说明 |
|--------|------|
| `mission start TASK` | 启动任务 |
| `mission status` | 查看当前任务状态 |
| `mission list` | 列出所有任务 |

`start` 选项：

| 选项 | 说明 |
|------|------|
| `--agent` | Agent ID（默认 `default`） |
| `--verify` | 验证命令（如 `pytest`） |
| `--max-iterations` | 最大迭代次数（默认 20） |

---

## `qwenpaw task` — 无头单任务执行

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `-i` / `--instruction` | str | — | 任务指令文本或 `.md` 文件路径（必填） |
| `-m` / `--model` | str | — | 模型覆盖（如 `anthropic/claude-sonnet-4-5`） |
| `--max-iters` | int | `30` | ReAct 最大迭代次数 |
| `-t` / `--timeout` | int | `900` | 最大执行时间（秒） |
| `--no-guard` | flag | — | 禁用工具防护 |
| `--skills-dir` | path | — | 直接指定技能目录 |
| `--output-dir` | path | — | 输出日志和 `result.json` 的目录 |
| `--agent-id` | str | `default` | Agent ID |

---

## `qwenpaw auth` — Web 认证管理

| 子命令 | 说明 |
|--------|------|
| `auth reset-password` | 重置 Web 登录密码 |

---

## `qwenpaw acp` — ACP Agent 模式

| 选项 | 类型 | 说明 |
|------|------|------|
| `--agent` | str | Agent ID（默认活跃 Agent） |
| `--workspace` | path | 工作空间目录覆盖 |
| `--debug` | flag | 启用调试日志到 stderr |

---

## `qwenpaw desktop` — 桌面 WebView

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--host` | str | `127.0.0.1` | 绑定地址 |
| `--log-level` | choice | `info` | 日志级别 |

---

## `qwenpaw doctor` — 诊断

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--timeout` | float | `5.0` | HTTP 检查超时（秒） |
| `--llm-timeout` | float | `15.0` | LLM 连通性检查超时（秒） |
| `--deep` | flag | — | 深度检查（频道连通性、本地模型状态） |

### `qwenpaw doctor fix` — 修复

| 选项 | 类型 | 说明 |
|------|------|------|
| `--dry-run` | flag | 仅列出计划操作，不执行 |
| `-y` / `--yes` | flag | 跳过确认 |
| `--non-interactive` | flag | 仅允许安全修复 |
| `--only IDS` | str | 限制执行的修复 ID（逗号分隔） |
| `--no-backup` | flag | 跳过备份 |
| `--backup-dir` | path | 备份目录 |

修复 ID 列表：`ensure-working-dir`、`ensure-workspace-dirs`、`validate-all-jobs-json`、`reconcile-workspace-skills`、`seed-missing-agent-json`、`reset-invalid-agent-json`、`write-empty-jobs-json`、`normalize-jobs-cron`、`rebuild-console-npm`

---

## `qwenpaw shutdown` — 停止进程

| 选项 | 类型 | 说明 |
|------|------|------|
| `--port` | int | 指定后端端口（默认从全局配置读取） |

---

## `qwenpaw update` — 升级

| 选项 | 类型 | 说明 |
|------|------|------|
| `-y` / `--yes` | flag | 跳过确认直接升级 |

---

## `qwenpaw uninstall` — 卸载

| 选项 | 类型 | 说明 |
|------|------|------|
| `--purge` | flag | 同时删除所有数据（配置、聊天、模型等） |
| `--yes` | flag | 跳过确认 |

---

## `qwenpaw clean` — 清空工作目录

| 选项 | 类型 | 说明 |
|------|------|------|
| `--yes` | flag | 跳过确认 |
| `--dry-run` | flag | 仅列出将删除的内容 |
