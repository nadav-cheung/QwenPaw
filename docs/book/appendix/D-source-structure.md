# 附录 D - 源码目录结构

本附录描述 QwenPaw 智能体开发框架的源码组织结构，帮助开发者快速定位相关模块。

## D.1 目录树

```
src/qwenpaw/
├── agents/              # 智能体核心
├── app/                 # 应用层（API服务、路由、渠道）
├── cli/                 # 命令行工具
├── config/              # 配置管理
├── agent_stats/         # 智能体统计
├── envs/                # 环境变量存储
├── local_models/        # 本地模型管理
├── plugins/             # 插件系统
├── providers/           # 模型提供商
├── security/            # 安全模块
├── token_usage/         # Token使用统计
├── tokenizer/           # 分词器资源
├── tunnel/              # 隧道服务
└── utils/               # 工具函数
```

## D.2 agents/ - 智能体核心

智能体系统的核心实现，包含 Agent、Tools、Skills 等核心组件。

### D.2.1 目录结构

```
agents/
├── __init__.py
├── react_agent.py       # ReAct Agent 实现
├── model_factory.py     # 模型工厂
├── routing_chat_model.py # 路由聊天模型
├── schema.py            # 数据模型定义
├── command_handler.py   # 命令处理器
├── tool_guard_mixin.py  # 工具守卫
├── prompt.py            # Prompt 管理
├── templates.py         # 模板管理
├── skills_hub.py        # Skills 中心
├── skills_manager.py    # Skills 管理器
├── acp/                 # ACP 协议
├── hooks/               # 钩子函数
├── memory/              # 记忆系统
├── mission/             # 任务系统
├── skills/              # Skills 定义
└── tools/               # 工具实现
```

### D.2.2 主要模块说明

| 模块 | 文件 | 说明 |
|------|------|------|
| **核心** | `react_agent.py` | ReAct 范式 Agent 实现，支持多轮对话、工具调用 |
| **核心** | `model_factory.py` | 模型实例化工厂，支持多种模型创建 |
| **核心** | `routing_chat_model.py` | 智能路由，根据上下文选择合适模型 |
| **数据** | `schema.py` | 核心数据模型定义（Agent、Message、Tool等） |
| **工具** | `tools/` | 内置工具集（文件操作、Shell、浏览器控制等） |
| **记忆** | `memory/` | Agent 记忆系统实现 |
| **任务** | `mission/` | 任务分解与执行系统 |

### D.2.3 关键类

```python
# react_agent.py
class ReactAgent          # ReAct 范式智能体

# model_factory.py
class ModelFactory        # 模型工厂类

# schema.py
class Agent               # 智能体定义
class Message             # 消息模型
class Tool                 # 工具定义
```

## D.3 app/ - 应用层

FastAPI 应用服务，包含 API 路由、渠道适配器、认证授权等。

### D.3.1 目录结构

```
app/
├── __init__.py
├── _app.py               # FastAPI 应用实例
├── agent_config_watcher.py
├── agent_context.py      # Agent 上下文
├── migration.py          # 数据迁移
├── multi_agent_manager.py # 多智能体管理
├── approvals/            # 审批流程
├── channels/            # 渠道适配器
├── crons/                # 定时任务
├── mcp/                  # MCP 服务端
├── routers/              # API 路由
├── runner/               # 任务运行器
└── workspace/            # 工作空间
```

### D.3.2 主要模块说明

| 模块 | 文件 | 说明 |
|------|------|------|
| **核心** | `_app.py` | FastAPI 应用主入口 |
| **管理** | `multi_agent_manager.py` | 多智能体协调与管理 |
| **路由** | `routers/` | REST API 端点定义 |
| **渠道** | `channels/` | 多渠道适配（钉钉、飞书、微信等） |
| **MCP** | `mcp/` | Model Context Protocol 服务端 |
| **工作区** | `workspace/` | 沙盒工作空间管理 |

### D.3.3 routers/ 子目录

```
routers/
├── agent.py              # 智能体管理 API
├── agents.py             # 批量智能体操作
├── auth.py               # 认证 API
├── backup.py             # 备份 API
├── config.py             # 配置 API
├── console.py            # 控制台 API
├── envs.py               # 环境变量 API
├── files.py              # 文件管理 API
├── local_models.py       # 本地模型 API
├── mcp.py                # MCP API
├── messages.py           # 消息 API
├── plugins.py            # 插件 API
├── providers.py          # 模型提供商 API
├── schemas_config.py     # Schema 配置 API
├── settings.py           # 设置 API
├── skills.py             # Skills API
├── token_usage.py        # Token 使用 API
├── tools.py              # 工具 API
└── workspace.py          # 工作空间 API
```

## D.4 cli/ - 命令行工具

命令行接口实现，支持 agent、app、plugin 等命令。

### D.4.1 目录结构

```
cli/
├── __init__.py
├── main.py               # CLI 入口
├── utils.py              # CLI 工具函数
├── process_utils.py     # 进程管理
├── http.py               # HTTP 客户端
├── acp_cmd.py            # ACP 命令
├── agents_cmd.py         # Agent 命令
├── app_cmd.py            # 应用命令
├── auth_cmd.py           # 认证命令
├── channels_cmd.py       # 渠道命令
├── chats_cmd.py          # 聊天命令
├── clean_cmd.py          # 清理命令
├── cron_cmd.py           # 定时任务命令
├── daemon_cmd.py         # 守护进程命令
├── desktop_cmd.py        # 桌面命令
├── doctor_cmd.py         # 诊断命令
├── env_cmd.py            # 环境命令
├── init_cmd.py           # 初始化命令
├── mission_cmd.py        # 任务命令
├── plugin_commands.py    # 插件命令
├── providers_cmd.py      # 提供商命令
├── shutdown_cmd.py       # 关闭命令
├── skills_cmd.py         # Skills 命令
├── task_cmd.py           # 任务命令
└── update_cmd.py        # 更新命令
```

## D.5 providers/ - 模型提供商

支持多种大语言模型提供商的适配实现。

### D.5.1 目录结构

```
providers/
├── __init__.py
├── provider.py           # Provider 基类
├── provider_manager.py   # 提供商管理器
├── rate_limiter.py       # 速率限制器
├── retry_chat_model.py   # 重试机制
├── capability_baseline.py # 能力基线
├── multimodal_prober.py  # 多模态探测
├── openai_provider.py    # OpenAI
├── anthropic_provider.py # Anthropic (Claude)
├── gemini_provider.py    # Google Gemini
├── ollama_provider.py    # Ollama
├── lmstudio_provider.py  # LM Studio
└── openrouter_provider.py # OpenRouter
```

### D.5.2 主要 Provider

| Provider | 文件 | 支持模型 |
|----------|------|----------|
| OpenAI | `openai_provider.py` | GPT-4, GPT-3.5-turbo |
| Anthropic | `anthropic_provider.py` | Claude 3.5, Claude 3 |
| Google | `gemini_provider.py` | Gemini Pro, Gemini Flash |
| Ollama | `ollama_provider.py` | Llama, Qwen, Mistral 等 |
| LM Studio | `lmstudio_provider.py` | 本地开源模型 |
| OpenRouter | `openrouter_provider.py` | 聚合多种模型 |

## D.6 plugins/ - 插件系统

插件化扩展系统，支持运行时加载外部功能。

### D.6.1 目录结构

```
plugins/
├── __init__.py
├── api.py                # 插件 API
├── architecture.py       # 插件架构
├── loader.py             # 插件加载器
├── registry.py           # 插件注册表
└── runtime.py            # 插件运行时
```

## D.7 辅助模块

### D.7.1 config/ - 配置管理

```
config/
├── config.py             # 配置主文件
├── context.py            # 配置上下文
├── timezone.py           # 时区配置
└── utils.py              # 配置工具
```

### D.7.2 security/ - 安全模块

```
security/
├── secret_store.py       # 密钥存储
├── skill_scanner/        # Skill 安全扫描
└── tool_guard/           # 工具调用守卫
```

### D.7.3 local_models/ - 本地模型

```
local_models/
├── download_manager.py   # 下载管理
├── llamacpp.py           # Llama.cpp 集成
├── manager.py            # 模型管理器
├── model_manager.py      # 模型生命周期管理
└── tag_parser.py         # 模型标签解析
```

### D.7.4 其他模块

| 目录 | 说明 |
|------|------|
| `agent_stats/` | 智能体运行统计与监控 |
| `envs/` | 环境变量存储（加密） |
| `token_usage/` | Token 使用量追踪 |
| `tokenizer/` | BPE 分词器资源文件 |
| `tunnel/` | Cloudflare 隧道服务 |
| `utils/` | 通用工具函数 |

## D.8 源码阅读指南

### D.8.1 查找特定功能的源码

| 功能 | 源码位置 |
|------|----------|
| **创建新 Agent** | `agents/react_agent.py` |
| **添加 Tool** | `agents/tools/` |
| **添加 Skill** | `agents/skills/` |
| **API 路由** | `app/routers/` |
| **渠道适配** | `app/channels/` |
| **Provider 实现** | `providers/` |
| **CLI 命令** | `cli/` |
| **插件开发** | `plugins/` |

### D.8.2 核心调用链

```
用户请求
    ↓
cli/main.py (命令行入口)
    ↓
app/_app.py (FastAPI 应用)
    ↓
app/routers/ (API 路由)
    ↓
agents/react_agent.py (Agent 核心)
    ↓
agents/tools/ (工具执行)
    ↓
providers/ (模型调用)
```

### D.8.3 扩展开发建议

- **新增 Provider**: 继承 `providers/provider.py` 中的 `ChatModelProvider` 基类
- **新增 Tool**: 在 `agents/tools/` 创建新模块并注册
- **新增 Skill**: 在 `agents/skills/` 创建新 Skill 目录
- **新增 Channel**: 在 `app/channels/` 实现 `ChannelAdapter` 接口
- **新增 CLI 命令**: 在 `cli/` 添加新命令模块
