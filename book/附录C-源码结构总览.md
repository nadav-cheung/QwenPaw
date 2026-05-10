# 附录C：源码结构总览

源码根目录：`src/qwenpaw/`

---

## 顶层文件

| 文件 | 说明 |
|------|------|
| `__init__.py` | 包入口，导出版本等基本信息 |
| `__main__.py` | 入口点，支持 `python -m qwenpaw` 运行 |
| `__version__.py` | 版本号定义 |
| `constant.py` | 全局常量：路径、默认值、环境变量加载与解析 |
| `exceptions.py` | 自定义异常类与 LLM API 异常转换器 |

---

## 目录结构

```
src/qwenpaw/
├── agent_stats/         # Agent 统计信息收集
├── agents/              # Agent 核心：ReAct 循环、技能、提示词、工具
│   ├── acp/             # ACP（Agent Communication Protocol）服务端
│   ├── hooks/           # Agent 生命周期钩子
│   ├── md_files/        # 内置 Markdown 模板文件（zh/en/ru）
│   ├── memory/          # 记忆管理与向量搜索
│   │   └── proactive/   # 主动记忆检索
│   ├── mission/         # Mission 模式（自治迭代任务）
│   ├── skills/          # 内置技能目录（多语言版本）
│   ├── skills_hub/      # 技能池（Skill Pool）管理
│   ├── tools/           # 内置工具实现
│   └── utils/           # Agent 相关工具函数
├── app/                 # FastAPI 应用层
│   ├── approvals/       # 工具防护审批机制
│   ├── channels/        # 频道实现（各通信平台）
│   │   ├── console/     # 控制台频道
│   │   ├── dingtalk/    # 钉钉频道
│   │   ├── discord_/    # Discord 频道
│   │   ├── feishu/      # 飞书/Lark 频道
│   │   ├── imessage/    # iMessage 频道
│   │   ├── matrix/      # Matrix 频道
│   │   ├── mattermost/  # Mattermost 频道
│   │   ├── mqtt/        # MQTT 频道
│   │   ├── onebot/      # OneBot v11 频道
│   │   ├── qq/          # QQ 频道
│   │   ├── telegram/    # Telegram 频道
│   │   ├── voice/       # Twilio 语音频道
│   │   ├── wecom/       # 企业微信频道
│   │   ├── weixin/      # 微信（iLink）频道
│   │   └── xiaoyi/      # 小艺（华为 A2A）频道
│   ├── crons/           # Cron 定时任务引擎
│   │   └── repo/        # Cron 任务持久化仓库
│   ├── mcp/             # MCP（Model Context Protocol）客户端管理
│   ├── routers/         # FastAPI 路由（REST API 端点）
│   ├── runner/          # Agent 运行器（会话管理、守护命令）
│   │   ├── control_commands/ # 运行时控制命令
│   │   └── repo/        # 会话存储仓库
│   └── workspace/       # 工作空间管理
├── backup/              # 备份与恢复
│   ├── _ops/            # 备份/恢复操作
│   └── _utils/          # 安全文件交换工具
├── cli/                 # 命令行接口（Click 框架）
├── config/              # 配置系统（Pydantic 模型、加载/保存）
├── envs/                # 环境变量持久化（加密存储）
├── local_models/        # 本地模型管理（下载、llama.cpp 集成）
├── plugins/             # 插件系统（加载、运行、注册表）
├── providers/           # LLM Provider 实现
├── security/            # 安全子系统
│   ├── secret_store.py  # 加密密钥存储
│   ├── skill_scanner/   # 技能安全扫描
│   │   ├── analyzers/   # 代码分析器
│   │   ├── data/        # 扫描规则数据
│   │   └── rules/       # 扫描规则与签名
│   └── tool_guard/      # 工具防护
│       ├── guardians/   # 各类工具守护者
│       └── rules/       # 防护规则
├── token_usage/         # Token 用量追踪
├── tokenizer/           # 分词器（Token 计数）
├── tunnel/              # 隧道（Cloudflare Tunnel 集成）
└── utils/               # 通用工具（日志、遥测、系统信息）
```

---

## 关键模块导出

### `qwenpaw.config`

| 导出 | 说明 |
|------|------|
| `Config` | 根配置模型（`config.json` 完整结构） |
| `ChannelConfig` | 频道配置集合 |
| `AgentsConfig` | Agent 管理配置 |
| `AgentsRunningConfig` | Agent 运行时参数 |
| `SecurityConfig` | 安全配置（工具防护、文件防护、技能扫描） |
| `ToolGuardConfig` | 工具防护配置 |
| `ACPConfig` | ACP 协议配置 |
| `load_config` | 加载配置文件 |
| `save_config` | 保存配置文件 |
| `get_available_channels` | 获取可用频道列表 |

### `qwenpaw.envs`

| 导出 | 说明 |
|------|------|
| `load_envs` | 从 `envs.json` 加载环境变量（自动解密） |
| `save_envs` | 保存环境变量到 `envs.json`（自动加密） |
| `set_env_var` | 设置单个环境变量 |
| `delete_env_var` | 删除单个环境变量 |
| `load_envs_into_environ` | 启动时注入环境变量到 `os.environ` |

### `qwenpaw.exceptions`

| 导出 | 说明 |
|------|------|
| `ProviderError` | Provider 错误（`PROVIDER_ERROR`） |
| `ModelFormatterError` | 模型消息格式化错误（`MODEL_FORMATTER_ERROR`） |
| `SystemCommandException` | 系统命令执行错误（`SYSTEM_COMMAND_ERROR`） |
| `ChannelError` | 频道通信错误 |
| `AgentStateError` | Agent 状态与会话错误（`AGENT_STATE_ERROR`） |
| `SkillsError` | 技能管理错误（`SKILLS_ERROR`） |
| `convert_model_exception` | LLM API 异常自动转换器 |

---

## 内置 Provider

| Provider ID | 模块文件 | 说明 |
|-------------|---------|------|
| `openai` | `providers/openai_provider.py` | OpenAI 及兼容 API |
| `anthropic` | `providers/anthropic_provider.py` | Anthropic Claude |
| `gemini` | `providers/gemini_provider.py` | Google Gemini |
| `ollama` | `providers/ollama_provider.py` | Ollama 本地推理 |
| `lmstudio` | `providers/lmstudio_provider.py` | LM Studio 本地推理 |
| `openrouter` | `providers/openrouter_provider.py` | OpenRouter 聚合 |
| `qwenpaw-local` | `providers/provider.py` + `local_models/` | 内置 llama.cpp 本地推理 |
