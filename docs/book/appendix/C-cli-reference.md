# 附录 C: QwenPaw CLI 命令参考

本文档列出所有 QwenPaw CLI 命令及其用法。

## C.1 启动命令

### C.1.1 qwenpaw app

运行 QwenPaw FastAPI 应用。

```bash
qwenpaw app [OPTIONS]
```

**参数：**

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--host` | 绑定主机 | `127.0.0.1` |
| `--port` | 绑定端口 | `8088` |
| `--reload` | 启用自动重载（开发模式） | 禁用 |
| `--log-level` | 日志级别 | `info` |
| `--hide-access-paths` | 从访问日志中隐藏的路径 | `/console/push-messages` |

**示例：**

```bash
# 启动后台服务
qwenpaw app

# 开发模式（启用热重载）
qwenpaw app --reload

# 自定义端口
qwenpaw app --port 9000 --host 0.0.0.0

# 调试模式
qwenpaw app --log-level debug
```

### C.1.2 qwenpaw desktop

在原生 webview 窗口中运行 QwenPaw。

```bash
qwenpaw desktop [OPTIONS]
```

**参数：**

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--host` | 绑定主机 | `127.0.0.1` |
| `--log-level` | 日志级别 | `info` |

**示例：**

```bash
qwenpaw desktop
```

### C.1.3 qwenpaw shutdown

停止正在运行的 QwenPaw 应用进程。

```bash
qwenpaw shutdown [OPTIONS]
```

**参数：**

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--port` | 后端端口 | 全局 `--port` |

**示例：**

```bash
qwenpaw shutdown
qwenpaw shutdown --port 8088
```

---

## C.2 初始化与配置命令

### C.2.1 qwenpaw init

创建工作目录配置文件和 HEARTBEAT.md（交互式）。

```bash
qwenpaw init [OPTIONS]
```

**参数：**

| 参数 | 说明 |
|------|------|
| `--force` | 覆盖现有配置 |
| `--defaults` | 使用默认值，无交互提示 |
| `--accept-security` | 跳过安全确认 |

**示例：**

```bash
# 交互式初始化
qwenpaw init

# 非交互式初始化（用于脚本/Docker）
qwenpaw init --defaults --accept-security
```

### C.2.2 qwenpaw env

管理环境变量。

```bash
qwenpaw env <子命令> [OPTIONS]
```

**子命令：**

| 子命令 | 说明 |
|--------|------|
| `list` | 列出所有环境变量 |
| `set <KEY> <VALUE>` | 设置环境变量 |
| `delete <KEY>` | 删除环境变量 |

**示例：**

```bash
# 列出所有环境变量
qwenpaw env list

# 设置环境变量
qwenpaw env set OPENAI_API_KEY sk-xxx

# 删除环境变量
qwenpaw env delete OPENAI_API_KEY
```

### C.2.3 qwenpaw clean

清理 QwenPaw 工作目录。

```bash
qwenpaw clean [OPTIONS]
```

**参数：**

| 参数 | 说明 |
|------|------|
| `--yes` | 不提示确认 |
| `--dry-run` | 仅显示将被删除的内容 |

**示例：**

```bash
# 预览将被删除的内容
qwenpaw clean --dry-run

# 确认删除
qwenpaw clean --yes
```

---

## C.3 模型与提供商命令

### C.3.1 qwenpaw models

LLM 提供商和模型管理。

```bash
qwenpaw models <子命令> [OPTIONS]
```

#### qwenpaw models list

显示所有提供商及其配置。

```bash
qwenpaw models list
```

**示例输出：**

```
=== Providers ===

────────────────────────────────────────────
  OpenAI (openai)
────────────────────────────────────────────
  base_url       : https://api.openai.com/v1
  api_key        : sk-***xx
  models         :
    - GPT-4 (gpt-4)
    - GPT-3.5 (gpt-3.5-turbo)

════════════════════════════════════════════
  Active Model Slot
════════════════════════════════════════════
  LLM            : openai / gpt-4
```

#### qwenpaw models config

交互式配置提供商和模型。

```bash
qwenpaw models config
```

#### qwenpaw models config-key

配置提供商的 API 密钥。

```bash
qwenpaw models config-key [PROVIDER_ID]
```

**示例：**

```bash
qwenpaw models config-key openai
```

#### qwenpaw models set-llm

交互式设置活跃的 LLM 模型。

```bash
qwenpaw models set-llm
```

#### qwenpaw models add-provider

添加自定义提供商。

```bash
qwenpaw models add-provider PROVIDER_ID --name NAME --base-url URL
```

**示例：**

```bash
qwenpaw models add-provider custom-llm \
  --name "Custom LLM" \
  --base-url https://api.custom.com/v1
```

#### qwenpaw models remove-provider

移除自定义提供商。

```bash
qwenpaw models remove-provider PROVIDER_ID [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--yes`, `-y` | 跳过确认 |

**示例：**

```bash
qwenpaw models remove-provider custom-llm --yes
```

#### qwenpaw models add-model

向提供商添加模型。

```bash
qwenpaw models add-model PROVIDER_ID --model-id ID --model-name NAME
```

**示例：**

```bash
qwenpaw models add-model openai \
  --model-id gpt-4-turbo \
  --model-name "GPT-4 Turbo"
```

#### qwenpaw models remove-model

从提供商移除模型。

```bash
qwenpaw models remove-model PROVIDER_ID --model-id MODEL_ID
```

#### qwenpaw models download

下载本地模型。

```bash
qwenpaw models download REPO_ID [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--source`, `-s` | 下载源 (`huggingface`/`modelscope`) | `huggingface` |

**示例：**

```bash
# 从 HuggingFace 下载
qwenpaw models download TheBloke/Mistral-7B-Instruct-v0.2-GGUF

# 从 ModelScope 下载
qwenpaw models download Qwen/Qwen2-0.5B-Instruct-GGUF --source modelscope
```

#### qwenpaw models local

列出所有已下载的本地模型。

```bash
qwenpaw models local
```

#### qwenpaw models remove-local

移除已下载的本地模型。

```bash
qwenpaw models remove-local MODEL_ID [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--yes`, `-y` | 跳过确认 |

**示例：**

```bash
qwenpaw models remove-local mistral-7b --yes
```

---

## C.4 渠道命令

### C.4.1 qwenpaw channels

渠道配置管理。

```bash
qwenpaw channels <子命令> [OPTIONS]
```

#### qwenpaw channels list

显示当前渠道配置。

```bash
qwenpaw channels list [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--agent-id` | 智能体 ID | `default` |

**示例：**

```bash
qwenpaw channels list
qwenpaw channels list --agent-id my-agent
```

#### qwenpaw channels config

交互式配置渠道。

```bash
qwenpaw channels config [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--agent-id` | 智能体 ID | `default` |

#### qwenpaw channels add

安装渠道到自定义目录并添加到配置。

```bash
qwenpaw channels add KEY [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--path` | 从本地路径复制 |
| `--url` | 从 URL 下载 |
| `--configure/--no-configure` | 交互式配置 | `true` |

**示例：**

```bash
qwenpaw channels add discord
qwenpaw channels add custom_channel --path ./my_channel.py
```

#### qwenpaw channels remove

移除自定义渠道。

```bash
qwenpaw channels remove KEY [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--keep-config/--no-keep-config` | 保留配置中的条目 | `false` |

**示例：**

```bash
qwenpaw channels remove custom_channel
```

#### qwenpaw channels install

安装渠道到工作目录（创建模板）。

```bash
qwenpaw channels install KEY [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--path` | 从本地路径复制 |
| `--url` | 从 URL 下载 |

**示例：**

```bash
qwenpaw channels install my_channel
qwenpaw channels install my_channel --path ./my_channel.py
```

---

## C.5 技能命令

### C.5.1 qwenpaw skills

技能管理。

```bash
qwenpaw skills <子命令> [OPTIONS]
```

#### qwenpaw skills list

显示所有技能及其启用/禁用状态。

```bash
qwenpaw skills list [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--agent-id` | 智能体 ID | `default` |

**示例：**

```bash
qwenpaw skills list
qwenpaw skills list --agent-id my-agent
```

**示例输出：**

```
Skills for agent: default

──────────────────────────────────────────────────
  Skill Name                  Source      Status
──────────────────────────────────────────────────
  builtin-time                builtin     ✓ enabled
  builtin-files              builtin     ✓ enabled
  github                      pool        ✓ enabled
  web-search                  pool        ✗ disabled
──────────────────────────────────────────────────
  Total: 4 skills, 3 enabled, 1 disabled
```

#### qwenpaw skills config

交互式配置技能。

```bash
qwenpaw skills config [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--agent-id` | 智能体 ID | `default` |

#### qwenpaw skills info

显示特定技能详情。

```bash
qwenpaw skills info SKILL_NAME [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--agent-id` | 智能体 ID | `default` |

**示例：**

```bash
qwenpaw skills info github
```

---

## C.6 插件命令

### C.6.1 qwenpaw plugin

插件管理。

```bash
qwenpaw plugin <子命令> [OPTIONS]
```

#### qwenpaw plugin install

从本地路径或 URL 安装插件。

```bash
qwenpaw plugin install SOURCE [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `SOURCE` | 本地路径或 URL |
| `--force` | 强制重装 |

**示例：**

```bash
# 从本地路径安装
qwenpaw plugin install examples/plugins/idealab-provider

# 从 URL 安装
qwenpaw plugin install https://example.com/plugin.zip

# 强制重装
qwenpaw plugin install ./my-plugin --force
```

#### qwenpaw plugin list

列出所有已安装的插件。

```bash
qwenpaw plugin list
```

#### qwenpaw plugin info

显示插件详细信息。

```bash
qwenpaw plugin info PLUGIN_ID
```

**示例：**

```bash
qwenpaw plugin info idealab-provider
```

#### qwenpaw plugin uninstall

卸载插件。

```bash
qwenpaw plugin uninstall PLUGIN_ID
```

**示例：**

```bash
qwenpaw plugin uninstall idealab-provider
```

#### qwenpaw plugin validate

验证插件。

```bash
qwenpaw plugin validate PATH
```

**示例：**

```bash
qwenpaw plugin validate ./my-plugin
```

---

## C.7 智能体命令

### C.7.1 qwenpaw agents

智能体管理。

```bash
qwenpaw agents <子命令> [OPTIONS]
```

#### qwenpaw agents list

列出所有配置的智能体。

```bash
qwenpaw agents list [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--base-url` | API 基础 URL | 全局配置 |

#### qwenpaw agents create

创建新智能体。

```bash
qwenpaw agents create --name NAME [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--name` | 必填，人类可读的智能体名称 |
| `--agent-id` | 显式智能体 ID |
| `--description` | 智能体描述 |
| `--workspace-dir` | 工作目录 |
| `--language` | 智能体语言 |
| `--template` | 模板类型 |
| `--skill` | 初始技能（可重复） |
| `--provider-id` | 提供商 ID |
| `--model-id` | 模型 ID |

**示例：**

```bash
# 创建基础智能体
qwenpaw agents create --name "Research Agent"

# 从模板创建
qwenpaw agents create --name "Coder" --template coding

# 带技能创建
qwenpaw agents create --name "Assistant" --skill github --skill web-search
```

#### qwenpaw agents delete

删除智能体。

```bash
qwenpaw agents delete AGENT_ID [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--remove-workspace` | 同时删除工作目录 |
| `--yes` | 跳过确认 |

**示例：**

```bash
qwenpaw agents delete research
qwenpaw agents delete research --remove-workspace
```

#### qwenpaw agents chat

与智能体聊天。

```bash
qwenpaw agents chat [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--from-agent` | 源智能体 ID | 必填 |
| `--to-agent` | 目标智能体 ID | 必填 |
| `--text` | 消息文本 | 必填 |
| `--session-id` | 会话 ID | 自动生成 |
| `--mode` | 响应模式 (`stream`/`final`) | `final` |
| `--background` | 后台任务模式 | 禁用 |
| `--task-id` | 检查后台任务状态 | - |
| `--timeout` | 请求超时（秒） | `300` |
| `--json-output` | JSON 输出 | 禁用 |

**示例：**

```bash
# 简单聊天
qwenpaw agents chat \
  --from-agent bot_a \
  --to-agent bot_b \
  --text "What is the weather?"

# 后台任务
qwenpaw agents chat --background \
  --from-agent bot_a \
  --to-agent bot_b \
  --text "Analyze large dataset"

# 检查任务状态
qwenpaw agents chat --background --task-id <task_id>
```

---

## C.8 计划任务命令

### C.8.1 qwenpaw cron

计划任务管理。

```bash
qwenpaw cron <子命令> [OPTIONS]
```

#### qwenpaw cron list

列出所有计划任务。

```bash
qwenpaw cron list [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--base-url` | API 基础 URL | 全局配置 |
| `--agent-id` | 智能体 ID | `default` |

#### qwenpaw cron get

获取任务详情。

```bash
qwenpaw cron get JOB_ID [OPTIONS]
```

#### qwenpaw cron state

获取任务运行时状态。

```bash
qwenpaw cron state JOB_ID [OPTIONS]
```

#### qwenpaw cron create

创建任务。

```bash
qwenpaw cron create [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `-f, --file` | JSON 规范文件 |
| `--type` | 任务类型 (`text`/`agent`) |
| `--name` | 任务名称 |
| `--cron` | Cron 表达式 |
| `--channel` | 投递渠道 |
| `--target-user` | 目标用户 ID |
| `--target-session` | 目标会话 ID |
| `--text` | 内容 |
| `--timezone` | 时区 |
| `--enabled/--no-enabled` | 启用状态 | `true` |
| `--mode` | 投递模式 | `final` |

**示例：**

```bash
# 从文件创建
qwenpaw cron create -f job.json

# 内联创建
qwenpaw cron create \
  --type agent \
  --name "Daily Report" \
  --cron "0 9 * * *" \
  --channel console \
  --text "Generate daily report"
```

#### qwenpaw cron delete

删除任务。

```bash
qwenpaw cron delete JOB_ID [OPTIONS]
```

#### qwenpaw cron pause

暂停任务。

```bash
qwenpaw cron pause JOB_ID [OPTIONS]
```

#### qwenpaw cron resume

恢复任务。

```bash
qwenpaw cron resume JOB_ID [OPTIONS]
```

#### qwenpaw cron run

立即触发任务。

```bash
qwenpaw cron run JOB_ID [OPTIONS]
```

---

## C.9 守护进程命令

### C.9.1 qwenpaw daemon

守护进程控制。

```bash
qwenpaw daemon <子命令> [OPTIONS]
```

#### qwenpaw daemon status

显示守护进程状态。

```bash
qwenpaw daemon status [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--agent-id` | 智能体 ID | `default` |

#### qwenpaw daemon restart

重启守护进程。

```bash
qwenpaw daemon restart [OPTIONS]
```

#### qwenpaw daemon reload-config

重新加载配置。

```bash
qwenpaw daemon reload-config [OPTIONS]
```

#### qwenpaw daemon version

显示版本和路径。

```bash
qwenpaw daemon version [OPTIONS]
```

#### qwenpaw daemon logs

显示日志。

```bash
qwenpaw daemon logs [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-n, --lines` | 显示行数 | `100` |

**示例：**

```bash
qwenpaw daemon logs
qwenpaw daemon logs -n 200
```

---

## C.10 聊天会话命令

### C.10.1 qwenpaw chats

聊天会话管理。

```bash
qwenpaw chats <子命令> [OPTIONS]
```

#### qwenpaw chats list

列出所有聊天。

```bash
qwenpaw chats list [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--user-id` | 按用户 ID 筛选 | - |
| `--channel` | 按渠道筛选 | - |
| `--base-url` | API 基础 URL | 全局配置 |
| `--agent-id` | 智能体 ID | `default` |

**示例：**

```bash
qwenpaw chats list
qwenpaw chats list --user-id alice
qwenpaw chats list --channel discord
```

#### qwenpaw chats get

查看聊天详情。

```bash
qwenpaw chats get CHAT_ID [OPTIONS]
```

#### qwenpaw chats create

创建聊天。

```bash
qwenpaw chats create [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--session-id` | 会话 ID |
| `--user-id` | 用户 ID |
| `--channel` | 渠道 |

#### qwenpaw chats delete

删除聊天。

```bash
qwenpaw chats delete CHAT_ID [OPTIONS]
```

---

## C.11 任务命令

### C.11.1 qwenpaw task

无头运行单个任务（无需 Web 服务器）。

```bash
qwenpaw task -i INSTRUCTION [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-i, --instruction` | 任务指令或 .md 文件路径 | 必填 |
| `-m, --model` | 模型覆盖 | - |
| `--max-iters` | 最大 ReAct 迭代次数 | `30` |
| `-t, --timeout` | 最大执行时间（秒） | `900` |
| `--no-guard` | 禁用工具守卫安全检查 | 禁用 |
| `--skills-dir` | 直接指定技能目录 | - |
| `--output-dir` | 输出目录 | - |
| `--agent-id` | 智能体 ID | `default` |

**示例：**

```bash
# 简单任务
qwenpaw task -i "What is 2 + 2?"

# 从文件读取任务
qwenpaw task -i ./task.md

# 自定义模型
qwenpaw task -i "Analyze this data" --model anthropic/claude-sonnet-4-5

# 带输出
qwenpaw task -i "Process files" --output-dir ./results
```

---

## C.12 任务模式命令

### C.12.1 qwenpaw mission

任务模式 - 自主迭代智能体。

```bash
qwenpaw mission <子命令> [OPTIONS]
```

#### qwenpaw mission start

开始任务。

```bash
qwenpaw mission start TASK [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--agent` | 智能体 ID | `default` |
| `--verify` | 验证命令 | - |
| `--max-iterations` | 最大迭代次数 | `20` |

**示例：**

```bash
qwenpaw mission start "Add authentication to the API"
qwenpaw mission start "Build a web scraper" --verify "pytest"
```

#### qwenpaw mission status

显示当前任务状态。

```bash
qwenpaw mission status [OPTIONS]
```

#### qwenpaw mission list

列出所有任务。

```bash
qwenpaw mission list [OPTIONS]
```

---

## C.13 诊断与修复命令

### C.13.1 qwenpaw doctor

健康检查。

```bash
qwenpaw doctor [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--timeout` | HTTP 超时（秒） | `5.0` |
| `--llm-timeout` | LLM 超时（秒） | `15.0` |
| `--deep` | 运行额外检查 | 禁用 |

**示例：**

```bash
# 基本检查
qwenpaw doctor

# 深度检查（包括渠道连通性）
qwenpaw doctor --deep
```

### C.13.2 qwenpaw doctor fix

应用保守的文件系统修复。

```bash
qwenpaw doctor fix [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--dry-run` | 仅列出计划操作 |
| `--yes`, `-y` | 无需确认应用 |
| `--non-interactive` | 仅允许安全修复 |
| `--only` | 指定的修复 ID |
| `--no-backup` | 跳过备份 |
| `--backup-dir` | 备份目录 |

**示例：**

```bash
# 预览修复计划
qwenpaw doctor fix --dry-run

# 应用所有安全修复
qwenpaw doctor fix --yes

# 仅特定修复
qwenpaw doctor fix --only ensure-working-dir,ensure-workspace-dirs
```

---

## C.14 更新与卸载命令

### C.14.1 qwenpaw update

升级 QwenPaw。

```bash
qwenpaw update [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--yes`, `-y` | 不提示 |

**示例：**

```bash
qwenpaw update
qwenpaw update --yes
```

### C.14.2 qwenpaw uninstall

卸载 QwenPaw。

```bash
qwenpaw uninstall [OPTIONS]
```

| 参数 | 说明 |
|------|------|
| `--yes`, `-y` | 不提示 |

**示例：**

```bash
qwenpaw uninstall --yes
```

---

## C.15 认证命令

### C.15.1 qwenpaw auth

Web 认证管理。

```bash
qwenpaw auth <子命令> [OPTIONS]
```

#### qwenpaw auth reset-password

重置 Web 用户密码。

```bash
qwenpaw auth reset-password
```

**示例：**

```bash
qwenpaw auth reset-password
```

---

## C.16 ACP 模式命令

### C.16.1 qwenpaw acp

以 ACP 智能体模式运行（通过 stdio）。

```bash
qwenpaw acp [OPTIONS]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--agent` | 智能体 ID | 活跃智能体 |
| `--workspace` | 工作目录覆盖 | - |
| `--debug` | 启用调试日志 | 禁用 |

**示例：**

```bash
qwenpaw acp
qwenpaw acp --agent my-agent --debug
```

---

## C.17 全局选项

所有命令都支持以下全局选项：

| 选项 | 说明 |
|------|------|
| `--host HOST` | API 主机（默认从上次运行读取） |
| `--port PORT` | API 端口（默认从上次运行读取） |
| `--version` | 显示版本 |
| `-h, --help` | 显示帮助 |

**示例：**

```bash
qwenpaw --host 127.0.0.1 --port 8088 app
qwenpaw --version
```

---

## C.18 命令索引表

| 命令 | 说明 |
|------|------|
| `qwenpaw acp` | ACP 智能体模式（stdio） |
| `qwenpaw agents chat` | 与智能体聊天 |
| `qwenpaw agents create` | 创建智能体 |
| `qwenpaw agents delete` | 删除智能体 |
| `qwenpaw agents list` | 列出智能体 |
| `qwenpaw app` | 运行 FastAPI 应用 |
| `qwenpaw auth reset-password` | 重置密码 |
| `qwenpaw channels add` | 添加渠道 |
| `qwenpaw channels config` | 配置渠道 |
| `qwenpaw channels install` | 安装渠道 |
| `qwenpaw channels list` | 列出渠道 |
| `qwenpaw channels remove` | 移除渠道 |
| `qwenpaw chats create` | 创建聊天 |
| `qwenpaw chats delete` | 删除聊天 |
| `qwenpaw chats get` | 获取聊天详情 |
| `qwenpaw chats list` | 列出聊天 |
| `qwenpaw clean` | 清理工作目录 |
| `qwenpaw cron create` | 创建计划任务 |
| `qwenpaw cron delete` | 删除计划任务 |
| `qwenpaw cron get` | 获取任务详情 |
| `qwenpaw cron list` | 列出计划任务 |
| `qwenpaw cron pause` | 暂停任务 |
| `qwenpaw cron resume` | 恢复任务 |
| `qwenpaw cron run` | 立即运行任务 |
| `qwenpaw cron state` | 获取任务状态 |
| `qwenpaw daemon logs` | 查看日志 |
| `qwenpaw daemon reload-config` | 重新加载配置 |
| `qwenpaw daemon restart` | 重启守护进程 |
| `qwenpaw daemon status` | 守护进程状态 |
| `qwenpaw daemon version` | 守护进程版本 |
| `qwenpaw desktop` | 原生 webview 模式 |
| `qwenpaw doctor` | 健康检查 |
| `qwenpaw doctor fix` | 修复问题 |
| `qwenpaw env delete` | 删除环境变量 |
| `qwenpaw env list` | 列出环境变量 |
| `qwenpaw env set` | 设置环境变量 |
| `qwenpaw init` | 初始化 |
| `qwenpaw mission list` | 列出任务 |
| `qwenpaw mission start` | 开始任务 |
| `qwenpaw mission status` | 任务状态 |
| `qwenpaw models add-model` | 添加模型 |
| `qwenpaw models add-provider` | 添加提供商 |
| `qwenpaw models config` | 配置模型/提供商 |
| `qwenpaw models config-key` | 配置 API 密钥 |
| `qwenpaw models download` | 下载本地模型 |
| `qwenpaw models list` | 列出提供商/模型 |
| `qwenpaw models local` | 列出本地模型 |
| `qwenpaw models remove-local` | 移除本地模型 |
| `qwenpaw models remove-model` | 移除模型 |
| `qwenpaw models remove-provider` | 移除提供商 |
| `qwenpaw models set-llm` | 设置活跃 LLM |
| `qwenpaw plugin info` | 插件详情 |
| `qwenpaw plugin install` | 安装插件 |
| `qwenpaw plugin list` | 列出插件 |
| `qwenpaw plugin uninstall` | 卸载插件 |
| `qwenpaw plugin validate` | 验证插件 |
| `qwenpaw shutdown` | 停止服务 |
| `qwenpaw skills config` | 配置技能 |
| `qwenpaw skills info` | 技能详情 |
| `qwenpaw skills list` | 列出技能 |
| `qwenpaw task` | 运行头less 任务 |
| `qwenpaw uninstall` | 卸载 |
| `qwenpaw update` | 更新版本 |
