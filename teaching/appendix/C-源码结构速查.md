# C 源码结构速查

> 完整 `src/qwenpaw/` 模块树，按职责分组。标注了本书对应的教学章节编号。

## 项目根目录结构

```
QwenPaw/
├── src/qwenpaw/           # Python 源码（核心）
├── console/               # React 前端 Web UI
├── website/               # 文档站点
├── tests/                 # 测试代码
├── teaching/              # 本书源码
├── scripts/               # 构建/检查脚本
├── deploy/                # 部署配置
├── pyproject.toml         # Python 项目配置
├── docker-compose.yml     # Docker 部署
└── Makefile               # 构建任务
```

## 源码模块树

### 智能体核心 (`agents/`) — 第 18-25 章

```
agents/
├── react_agent.py              # QwenPawAgent — 主智能体
├── tool_guard_mixin.py         # ToolGuardMixin — 工具安全拦截
├── command_handler.py          # CommandHandler — 系统命令处理
├── model_factory.py            # create_model_and_formatter — 模型工厂
├── prompt.py                   # build_system_prompt — 系统提示构建
├── templates.py                # 模板系统
├── skills_manager.py           # SkillsManager — 技能管理
├── skills_hub.py               # SkillsHub — 技能市场
├── tools/                      # 内置工具集（第 20 章）
│   ├── __init__.py             # 工具注册入口
│   ├── shell.py                # execute_shell_command
│   ├── file_io.py              # read_file, write_file, edit_file
│   ├── file_search.py          # grep_search, glob_search
│   ├── browser_control.py      # browser_use
│   ├── browser_snapshot.py     # 浏览器快照
│   ├── view_media.py           # view_image, view_video
│   ├── memory_search.py        # create_memory_search_tool
│   ├── agent_management.py     # list_agents, chat_with_agent
│   ├── delegate_external_agent.py # delegate_external_agent
│   ├── get_current_time.py     # get_current_time
│   ├── get_token_usage.py      # get_token_usage
│   ├── send_file.py            # send_file_to_user
│   ├── desktop_screenshot.py   # desktop_screenshot
│   └── utils.py                # 工具辅助函数
├── memory/                     # 记忆系统（第 21 章）
│   ├── __init__.py
│   ├── base_memory_manager.py  # BaseMemoryManager
│   ├── agent_md_manager.py     # Agent MD 文件管理
│   └── proactive/              # 主动记忆推送
│       ├── proactive_prompts.py
│       ├── proactive_responder.py
│       ├── proactive_trigger.py
│       ├── proactive_types.py
│       └── proactive_utils.py
├── acp/                        # ACP 协议（第 31 章）
│   ├── __init__.py
│   ├── core.py                 # 异常定义
│   ├── server.py               # QwenPawACPAgent
│   ├── client.py               # ACP 客户端
│   ├── service.py              # ACPService
│   ├── permissions.py          # 权限管理
│   └── tool_adapter.py         # 工具适配器
├── mission/                    # Mission 模式（第 23 章）
│   ├── __init__.py
│   ├── handler.py              # MissionHandler
│   ├── mission_runner.py       # MissionRunner
│   ├── prompts.py              # Mission 提示模板
│   └── state.py                # Mission 状态机
├── hooks/                      # 生命周期钩子（第 24 章）
│   ├── __init__.py
│   ├── bootstrap.py            # BootstrapHook
│   └── memory_compaction.py    # MemoryCompactionHook
├── skills/                     # 内置技能（第 22 章）
│   ├── skills_manager.py
│   ├── *.yaml / SKILL.md       # 各技能定义文件（中英文）
│   └── */scripts/              # 技能脚本（PDF, DOCX, PPTX, XLSX）
├── md_files/                   # 启动注入的 Markdown 知识文件
│   ├── en/ zh/ ru/             # 多语言系统知识
│   ├── qa/                     # QA Agent 知识
│   └── local/                  # 用户本地知识
└── utils/                      # 智能体工具函数
```

### 应用系统 (`app/`) — 第 26-31 章

```
app/
├── _app.py                     # FastAPI 应用工厂 + DynamicMultiAgentRunner
├── server.py                   # Uvicorn 服务器启动
├── auth.py                     # AuthMiddleware
├── multi_agent_manager.py      # MultiAgentManager（第 25 章）
├── agent_context.py            # AgentContext
├── agent_config_watcher.py     # 配置文件热重载
├── migration.py                # 旧版工作区迁移
├── console_push_store.py       # Console 推送存储
├── utils.py                    # 应用工具函数
├── routers/                    # FastAPI 路由
│   ├── __init__.py             # API 路由注册
│   ├── agent_scoped.py         # AgentContextMiddleware
│   └── voice.py                # 语音路由
├── runner/                     # 请求处理器（第 27-28 章）
│   ├── runner.py               # Runner
│   ├── session.py              # Session 管理
│   ├── task_tracker.py         # 任务追踪
│   ├── control_commands/       # 控制命令
│   └── repo/                   # 数据持久化
├── channels/                   # 消息渠道（第 29-30 章）
│   ├── registry.py             # 渠道注册
│   ├── manager.py              # ChannelManager
│   ├── schema.py               # 渠道数据模型
│   ├── renderer.py             # 消息渲染
│   ├── command_registry.py     # 命令注册
│   ├── console/                # Console 渠道
│   ├── dingtalk/               # 钉钉
│   ├── feishu/                 # 飞书/Lark
│   ├── telegram/               # Telegram
│   ├── discord_/               # Discord
│   ├── weixin/                 # 微信 iLink
│   ├── wecom/                  # 企业微信
│   ├── qq/                     # QQ
│   ├── onebot/                 # OneBot 协议
│   ├── imessage/               # Apple iMessage
│   ├── matrix/                 # Matrix
│   ├── mattermost/             # Mattermost
│   ├── mqtt/                   # MQTT
│   ├── voice/                  # Twilio 语音
│   └── xiaoyi/                 # 小i机器人
├── mcp/                        # MCP 客户端管理
│   ├── manager.py              # MCPClientManager
│   ├── stateful_client.py      # HttpStatefulClient, StdIOStatefulClient
│   └── watcher.py              # MCPConfigWatcher
├── crons/                      # 定时任务（第 42 章）
│   ├── manager.py              # CronManager
│   ├── executor.py             # CronExecutor
│   ├── heartbeat.py            # 心跳机制
│   ├── models.py               # 数据模型
│   ├── api.py                  # REST 端点
│   └── repo/                   # 持久化
├── approvals/                  # 审批系统
├── workspace/                  # 工作区管理
│   ├── workspace.py            # Workspace
│   └── service_manager.py      # ServiceManager
```

### 模型与安全 — 第 32-38 章

```
providers/                      # Provider 系统（第 32-34 章）
├── provider_manager.py         # ProviderManager — 单例管理器
├── provider.py                 # Provider, ModelInfo, ProviderInfo
├── openai_provider.py          # OpenAI 集成
├── anthropic_provider.py       # Anthropic 集成
├── gemini_provider.py          # Google Gemini 集成
├── ollama_provider.py          # Ollama 本地模型
├── lmstudio_provider.py        # LM Studio 本地模型
├── openrouter_provider.py      # OpenRouter 聚合
├── openai_chat_model_compat.py # OpenAI ChatModel 兼容
├── retry_chat_model.py         # RetryChatModel — 重试包装
├── rate_limiter.py             # LLMRateLimiter — 限流
├── capability_baseline.py      # 模型能力基线
└── multimodal_prober.py        # 多模态能力探测

security/                       # 安全系统（第 35-38 章）
├── secret_store.py             # SecretStore — 密钥加密
├── tool_guard/                 # ToolGuard（第 36 章）
│   ├── __init__.py
│   ├── engine.py               # 守卫引擎
│   ├── approval.py             # 审批机制
│   ├── models.py               # 数据模型
│   ├── utils.py                # 工具函数
│   ├── i18n.py                 # 国际化
│   └── guardians/              # 守卫器插件
│       ├── file_guardian.py    # 文件操作守卫
│       ├── rule_guardian.py    # 规则匹配守卫
│       └── shell_evasion_guardian.py # Shell 注入检测
└── skill_scanner/              # 技能扫描（第 38 章）
    ├── scanner.py              # SkillScanner — 编排器
    ├── scan_policy.py          # ScanPolicy — 策略配置
    ├── models.py               # Finding, ScanResult, ThreatCategory
    ├── analyzers/              # 分析器插件
    │   ├── __init__.py         # BaseAnalyzer 抽象
    │   └── pattern_analyzer.py # PatternAnalyzer — YAML 签名匹配
    ├── rules/signatures/       # YAML 检测签名
    │   ├── command_injection.yaml
    │   ├── data_exfiltration.yaml
    │   ├── hardcoded_secrets.yaml
    │   ├── obfuscation.yaml
    │   ├── prompt_injection.yaml
    │   ├── social_engineering.yaml
    │   ├── supply_chain.yaml
    │   └── unauthorized_tool_use.yaml
    └── data/
        └── default_policy.yaml # 默认安全策略

local_models/                   # 本地模型管理
├── manager.py                  # LocalModelManager
├── download_manager.py         # 模型下载
└── llamacpp.py                 # llama.cpp 集成
```

### 配置、CLI 与插件 — 第 39-43 章

```
config/                         # 配置系统（第 39 章）
├── __init__.py
├── config.py                   # load_config, Config
├── context.py                  # 配置上下文
├── utils.py                    # get_config_path, read_last_api
└── timezone.py                 # 时区处理

cli/                            # CLI 命令（第 41 章）
├── main.py                     # LazyGroup — 懒加载命令组
├── init_cmd.py                 # qwenpaw init
├── app_cmd.py                  # qwenpaw app
├── doctor_cmd.py               # qwenpaw doctor
├── channels_cmd.py             # qwenpaw channels
├── agents_cmd.py               # qwenpaw agents
├── skills_cmd.py               # qwenpaw skills
├── providers_cmd.py            # qwenpaw models
├── cron_cmd.py                 # qwenpaw cron
├── plugin_commands.py          # qwenpaw plugin
├── chats_cmd.py                # qwenpaw chats
├── env_cmd.py                  # qwenpaw env
├── auth_cmd.py                 # qwenpaw auth
├── acp_cmd.py                  # qwenpaw acp
├── mission_cmd.py              # qwenpaw mission
├── task_cmd.py                 # qwenpaw task
├── daemon_cmd.py               # qwenpaw daemon
├── desktop_cmd.py              # qwenpaw desktop
├── clean_cmd.py                # qwenpaw clean
├── update_cmd.py               # qwenpaw update
├── shutdown_cmd.py             # qwenpaw shutdown
├── uninstall_cmd.py            # qwenpaw uninstall
├── doctor_checks.py            # 诊断检查项
├── doctor_connectivity.py      # 连通性检查
├── doctor_fix_runner.py        # 修复运行器
├── doctor_registry.py          # 诊断注册
├── http.py                     # HTTP 客户端
├── process_utils.py            # 进程工具
└── utils.py                    # CLI 工具函数

plugins/                        # 插件系统（第 40 章）
├── __init__.py
├── loader.py                   # PluginLoader
├── registry.py                 # PluginRegistry
├── runtime.py                  # 插件运行时
├── api.py                      # 插件 API
└── architecture.py             # 插件架构

envs/                           # 环境变量持久化
├── __init__.py                 # load_envs_into_environ

backup/                         # 备份系统
├── _ops.py                     # 备份操作
└── _utils.py                   # 备份工具

tunnel/                         # 隧道/穿透
├── binary_manager.py           # 隧道二进制管理
```

### 基础设施

```
constant.py                     # 全局常量 + EnvVarLoader（附录 A）
exceptions.py                   # 业务异常（附录 E）
__init__.py                     # 包初始化
__version__.py                  # 版本号
__main__.py                     # python -m qwenpaw 入口

utils/                          # 通用工具
├── logging.py                  # 日志（setup_logger, LOG_FILE_PATH）
├── stdio.py                    # 标准 I/O（ensure_standard_streams）
└── system_info.py              # 系统信息（summarize_python_environment）

token_usage/                    # Token 统计
├── manager.py
└── model_wrapper.py

tokenizer/                      # 分词器
├── tokenizer.json
├── tokenizer_config.json
├── vocab.json
└── merges.txt

agent_stats/                    # Agent 统计
├── models.py
└── service.py
```

## 教学章节与源码映射

| 章节 | 编号 | 主要源码路径 |
|------|------|-------------|
| QwenPaw 是什么 | 01 | `__version__.py`, `constant.py` |
| 源码架构概览 | 02 | 全部模块 |
| 安装和运行 | 14 | `cli/main.py`, `cli/init_cmd.py` |
| 控制台使用 | 15 | `app/_app.py` |
| 技能系统入门 | 16 | `agents/skills_manager.py` |
| 项目结构 | 17 | 全部模块 |
| 智能体架构 | 18 | `agents/react_agent.py` |
| ReAct 模式 | 19 | `agents/react_agent.py` |
| 工具系统 | 20 | `agents/tools/` |
| 记忆系统 | 21 | `agents/memory/` |
| 技能系统 | 22 | `agents/skills_manager.py`, `agents/skills/` |
| Mission 模式 | 23 | `agents/mission/` |
| 模板与钩子 | 24 | `agents/templates.py`, `agents/hooks/` |
| 多智能体协作 | 25 | `app/multi_agent_manager.py` |
| FastAPI 服务器 | 26 | `app/_app.py` |
| 请求处理器 | 27 | `app/runner/runner.py` |
| 会话管理 | 28 | `app/runner/session.py` |
| 消息渠道架构 | 29 | `app/channels/` |
| 渠道实现 | 30 | `app/channels/console/` |
| ACP 协议 | 31 | `agents/acp/` |
| Provider 系统 | 32 | `providers/provider_manager.py` |
| OpenAIProvider | 33 | `providers/provider.py` 等 |
| 本地模型 Provider | 34 | `providers/ollama_provider.py` |
| 安全架构 | 35 | `security/` |
| ToolGuard 系统 | 36 | `security/tool_guard/` |
| 密钥存储 | 37 | `security/secret_store.py` |
| 技能安全扫描 | 38 | `security/skill_scanner/` |
| 配置系统 | 39 | `config/` |
| 插件系统 | 40 | `plugins/` |
| CLI 命令系统 | 41 | `cli/` |
| 定时任务 | 42 | `app/crons/` |
| 部署与运维 | 43 | `app/_app.py`, `deploy/` |
