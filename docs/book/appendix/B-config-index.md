# 附录 B - 配置项索引

本附录列出 QwenPaw 所有配置项，按功能分组，便于快速查阅。

---

## B.1 Agent 配置

### B.1.1 根级 Agent 配置（config.json）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `agents.active_agent` | string | `"default"` | 当前激活的智能体 ID | 第 2.1 章 |
| `agents.agent_order` | list | `["default"]` | 智能体排序列表（UI 显示顺序） | 第 2.1 章 |
| `agents.language` | string | `"zh"` | 默认语言设置 | 第 1.4 章 |
| `agents.system_prompt_files` | list | `["AGENTS.md", "SOUL.md", "PROFILE.md"]` | 系统提示文件列表 | 第 1.4 章 |
| `agents.audio_mode` | string | `"auto"` | 音频处理模式：`auto` 或 `native` | 第 2.3 章 |
| `agents.transcription_provider_type` | string | `"disabled"` | 转录提供商类型：`disabled`、`whisper_api`、`local_whisper` | 第 2.3 章 |
| `agents.transcription_provider_id` | string | `""` | Whisper API 转录的提供商 ID | 第 2.3 章 |
| `agents.transcription_model` | string | `"whisper-1"` | Whisper 模型名称 | 第 2.3 章 |

### B.1.2 Agent Profile 配置（workspace/agent.json）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `id` | string | - | 智能体唯一标识符（2-64 字符） | 第 2.1 章 |
| `name` | string | - | 智能体显示名称 | 第 2.1 章 |
| `description` | string | `""` | 智能体描述 | 第 2.1 章 |
| `workspace_dir` | string | - | 工作空间目录路径 | 第 2.1 章 |
| `template_id` | string | `null` | 创建时使用的内置模板 ID | 第 2.1 章 |
| `language` | string | `"zh"` | 智能体语言设置 | 第 1.4 章 |
| `system_prompt_files` | list | `["AGENTS.md", "SOUL.md", "PROFILE.md"]` | 系统提示文件列表 | 第 1.4 章 |
| `active_model.provider_id` | string | `""` | 当前模型的提供商 ID | 第 3.2 章 |
| `active_model.model` | string | `""` | 当前模型名称 | 第 3.2 章 |

### B.1.3 LLM 路由配置

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `llm_routing.enabled` | bool | `false` | 是否启用 LLM 路由 | 第 3.2 章 |
| `llm_routing.mode` | string | `"local_first"` | 路由模式：`local_first` 或 `cloud_first` | 第 3.2 章 |
| `llm_routing.local.provider_id` | string | `""` | 本地模型提供商 ID | 第 3.2 章 |
| `llm_routing.local.model` | string | `""` | 本地模型名称 | 第 3.2 章 |
| `llm_routing.cloud.provider_id` | string | `null` | 云端模型提供商 ID（可选） | 第 3.2 章 |
| `llm_routing.cloud.model` | string | `null` | 云端模型名称（可选） | 第 3.2 章 |

---

## B.2 Channel 配置

### B.2.1 通用渠道配置（BaseChannelConfig）

所有渠道继承以下通用配置：

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `enabled` | bool | `false` | 是否启用该渠道 | 第 1.6 章 |
| `bot_prefix` | string | `""` | Bot 消息前缀 | 第 1.6 章 |
| `filter_tool_messages` | bool | `false` | 是否过滤工具消息 | 第 1.6 章 |
| `filter_thinking` | bool | `false` | 是否过滤思考过程 | 第 1.6 章 |
| `dm_policy` | string | `"open"` | 私聊策略：`open` 或 `allowlist` | 第 1.6 章 |
| `group_policy` | string | `"open"` | 群聊策略：`open` 或 `allowlist` | 第 1.6 章 |
| `allow_from` | list | `[]` | 允许的用户 ID 列表 | 第 1.6 章 |
| `deny_message` | string | `""` | 拒绝访问时显示的消息 | 第 1.6 章 |
| `require_mention` | bool | `false` | 是否需要 @ 提及才响应 | 第 1.6 章 |

### B.2.2 Console 渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `console.enabled` | bool | `true` | 是否启用 Console 渠道 | 第 1.6 章 |
| `console.media_dir` | string | `null` | 媒体文件存储目录 | 第 1.6 章 |

### B.2.3 Discord 渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `discord.bot_token` | string | `""` | Discord Bot Token | 第 3.4 章 |
| `discord.http_proxy` | string | `""` | HTTP 代理地址 | 第 3.4 章 |
| `discord.http_proxy_auth` | string | `""` | HTTP 代理认证信息 | 第 3.4 章 |
| `discord.accept_bot_messages` | bool | `false` | 是否接受其他 Bot 的消息 | 第 3.4 章 |

### B.2.4 钉钉（DingTalk）渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `dingtalk.client_id` | string | `""` | 钉钉应用 Client ID | 第 3.4 章 |
| `dingtalk.client_secret` | string | `""` | 钉钉应用 Client Secret | 第 3.4 章 |
| `dingtalk.message_type` | string | `"markdown"` | 消息类型：`markdown` 或 `text` | 第 3.4 章 |
| `dingtalk.card_template_id` | string | `""` | 卡片模板 ID | 第 3.4 章 |
| `dingtalk.card_template_key` | string | `"content"` | 卡片模板内容键 | 第 3.4 章 |
| `dingtalk.robot_code` | string | `""` | 机器人 Code | 第 3.4 章 |
| `dingtalk.media_dir` | string | `null` | 媒体文件存储目录 | 第 3.4 章 |
| `dingtalk.card_auto_layout` | bool | `false` | 是否自动布局卡片 | 第 3.4 章 |
| `dingtalk.at_sender_on_reply` | bool | `false` | 回复时是否 @ 发送者 | 第 3.4 章 |

### B.2.5 飞书（Feishu/Lark）渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `feishu.app_id` | string | `""` | 飞书应用 App ID | 第 3.4 章 |
| `feishu.app_secret` | string | `""` | 飞书应用 App Secret | 第 3.4 章 |
| `feishu.encrypt_key` | string | `""` | 加密密钥（可选） | 第 3.4 章 |
| `feishu.verification_token` | string | `""` | 验证 Token（可选） | 第 3.4 章 |
| `feishu.media_dir` | string | `null` | 媒体文件存储目录 | 第 3.4 章 |
| `feishu.domain` | string | `"feishu"` | 域名：`feishu`（国内）或 `lark`（国际） | 第 3.4 章 |

### B.2.6 QQ 渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `qq.app_id` | string | `""` | QQ 应用 App ID | 第 3.4 章 |
| `qq.client_secret` | string | `""` | QQ 应用 Client Secret | 第 3.4 章 |
| `qq.markdown_enabled` | bool | `true` | 是否启用 Markdown 解析 | 第 3.4 章 |
| `qq.max_reconnect_attempts` | int | `100` | 最大重连次数（-1 表示无限） | 第 3.4 章 |
| `qq.ack_message` | string | `""` | 确认消息内容 | 第 3.4 章 |

### B.2.7 Telegram 渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `telegram.bot_token` | string | `""` | Telegram Bot Token | 第 3.4 章 |
| `telegram.http_proxy` | string | `""` | HTTP 代理地址 | 第 3.4 章 |
| `telegram.http_proxy_auth` | string | `""` | HTTP 代理认证信息 | 第 3.4 章 |
| `telegram.show_typing` | bool | `null` | 是否显示正在输入状态 | 第 3.4 章 |

### B.2.8 Mattermost 渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `mattermost.url` | string | `""` | Mattermost 服务器 URL | 第 3.4 章 |
| `mattermost.bot_token` | string | `""` | Mattermost Bot Token | 第 3.4 章 |
| `mattermost.media_dir` | string | `null` | 媒体文件存储目录 | 第 3.4 章 |
| `mattermost.show_typing` | bool | `null` | 是否显示正在输入状态 | 第 3.4 章 |
| `mattermost.thread_follow_without_mention` | bool | `false` | 无 @ 提及时是否跟随线程 | 第 3.4 章 |

### B.2.9 MQTT 渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `mqtt.host` | string | `""` | MQTT 服务器地址 | 第 3.4 章 |
| `mqtt.port` | int | `null` | MQTT 服务器端口 | 第 3.4 章 |
| `mqtt.transport` | string | `""` | 传输协议：`tcp`、`websocket` 或 `wss` | 第 3.4 章 |
| `mqtt.clean_session` | bool | `true` | 是否清理会话 | 第 3.4 章 |
| `mqtt.qos` | int | `2` | QoS 级别：0、1 或 2 | 第 3.4 章 |
| `mqtt.username` | string | `null` | MQTT 用户名 | 第 3.4 章 |
| `mqtt.password` | string | `null` | MQTT 密码 | 第 3.4 章 |
| `mqtt.subscribe_topic` | string | `""` | 订阅主题 | 第 3.4 章 |
| `mqtt.publish_topic` | string | `""` | 发布主题 | 第 3.4 章 |
| `mqtt.tls_enabled` | bool | `false` | 是否启用 TLS | 第 3.4 章 |
| `mqtt.tls_ca_certs` | string | `null` | CA 证书路径 | 第 3.4 章 |
| `mqtt.tls_certfile` | string | `null` | 客户端证书路径 | 第 3.4 章 |
| `mqtt.tls_keyfile` | string | `null` | 客户端密钥路径 | 第 3.4 章 |

### B.2.10 Matrix 渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `matrix.homeserver` | string | `""` | Matrix Home Server 地址 | 第 3.4 章 |
| `matrix.user_id` | string | `""` | Matrix 用户 ID | 第 3.4 章 |
| `matrix.access_token` | string | `""` | Matrix Access Token | 第 3.4 章 |
| `matrix.group_allow_from` | list | `[]` | 允许加入群组的用户列表 | 第 3.4 章 |
| `matrix.groups` | dict | `{}` | 群组配置 | 第 3.4 章 |
| `matrix.encryption` | bool | `false` | 是否启用端到端加密 | 第 3.4 章 |
| `matrix.vision_enabled` | bool | `true` | 是否启用图片预览 | 第 3.4 章 |
| `matrix.history_limit` | int | `50` | 历史消息限制条数 | 第 3.4 章 |
| `matrix.username` | string | `""` | 登录用户名 | 第 3.4 章 |
| `matrix.password` | string | `""` | 登录密码 | 第 3.4 章 |
| `matrix.device_name` | string | `"qwenpaw-worker"` | 设备名称 | 第 3.4 章 |
| `matrix.sync_timeout_ms` | int | `30000` | Matrix 同步超时（毫秒） | 第 3.4 章 |
| `matrix.mention_pill_in_body` | bool | `false` | 是否在消息体中包含 @ 提及胶囊 | 第 3.4 章 |
| `matrix.outbound_structured_mentions` | bool | `true` | 是否在出站消息中包含结构化 @ 提及 | 第 3.4 章 |

### B.2.11 语音（Voice）渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `voice.twilio_account_sid` | string | `""` | Twilio Account SID | 第 3.4 章 |
| `voice.twilio_auth_token` | string | `""` | Twilio Auth Token | 第 3.4 章 |
| `voice.phone_number` | string | `""` | Twilio 电话号码 | 第 3.4 章 |
| `voice.phone_number_sid` | string | `""` | Twilio 电话号码 SID | 第 3.4 章 |
| `voice.tts_provider` | string | `"google"` | TTS 提供商 | 第 3.4 章 |
| `voice.tts_voice` | string | `"en-US-Journey-D"` | TTS 语音 | 第 3.4 章 |
| `voice.stt_provider` | string | `"deepgram"` | STT 提供商 | 第 3.4 章 |
| `voice.language` | string | `"en-US"` | 语言设置 | 第 3.4 章 |
| `voice.welcome_greeting` | string | `"Hi! This is QwenPaw. How can I help you?"` | 欢迎语 | 第 3.4 章 |

### B.2.12 企业微信（Wecom）渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `wecom.bot_id` | string | `""` | 企业微信机器人 ID | 第 3.4 章 |
| `wecom.secret` | string | `""` | 企业微信应用 Secret | 第 3.4 章 |
| `wecom.media_dir` | string | `null` | 媒体文件存储目录 | 第 3.4 章 |
| `wecom.welcome_text` | string | `""` | 欢迎文本 | 第 3.4 章 |
| `wecom.max_reconnect_attempts` | int | `-1` | 最大重连次数（-1 表示无限） | 第 3.4 章 |

### B.2.13 小艺（XiaoYi）渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `xiaoyi.ak` | string | `""` | 华为访问密钥 Access Key | 第 3.4 章 |
| `xiaoyi.sk` | string | `""` | 华为访问密钥 Secret Key | 第 3.4 章 |
| `xiaoyi.agent_id` | string | `""` | 小艺平台 Agent ID | 第 3.4 章 |
| `xiaoyi.ws_url` | string | `"wss://hag.cloud.huawei.com/openclaw/v1/ws/link"` | WebSocket 连接地址 | 第 3.4 章 |
| `xiaoyi.task_timeout_ms` | int | `3600000` | 任务超时（毫秒，1 小时） | 第 3.4 章 |

### B.2.14 微信（Weixin）渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `weixin.bot_token` | string | `""` | iLink Bot Bearer Token | 第 3.4 章 |
| `weixin.bot_token_file` | string | `""` | Bot Token 持久化文件路径 | 第 3.4 章 |
| `weixin.base_url` | string | `""` | iLink API 基础地址（空则使用默认） | 第 3.4 章 |
| `weixin.media_dir` | string | `null` | 媒体文件存储目录 | 第 3.4 章 |

### B.2.15 OneBot 渠道

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `onebot.ws_host` | string | `"0.0.0.0"` | WebSocket 主机地址 | 第 3.4 章 |
| `onebot.ws_port` | int | `6199` | WebSocket 端口 | 第 3.4 章 |
| `onebot.access_token` | string | `""` | 访问令牌 | 第 3.4 章 |
| `onebot.share_session_in_group` | bool | `false` | 是否在群组中共享会话 | 第 3.4 章 |

---

## B.3 Provider 配置

### B.3.1 Provider 通用配置

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `providers.*.id` | string | - | 提供商唯一标识符 | 第 3.1 章 |
| `providers.*.name` | string | - | 提供商显示名称 | 第 3.1 章 |
| `providers.*.base_url` | string | `""` | API 基础地址 | 第 3.1 章 |
| `providers.*.api_key` | string | `""` | API 密钥 | 第 3.1 章 |
| `providers.*.chat_model` | string | `"OpenAIChatModel"` | AgentScope 模型类名 | 第 3.1 章 |
| `providers.*.api_key_prefix` | string | `""` | API Key 前缀（如 `sk-`） | 第 3.1 章 |
| `providers.*.is_local` | bool | `false` | 是否为本地提供商 | 第 3.1 章 |
| `providers.*.freeze_url` | bool | `false` | 是否冻结 URL（不可编辑） | 第 3.1 章 |
| `providers.*.require_api_key` | bool | `true` | 是否需要 API Key | 第 3.1 章 |
| `providers.*.is_custom` | bool | `false` | 是否为用户自定义提供商 | 第 3.1 章 |
| `providers.*.support_model_discovery` | bool | `false` | 是否支持从 API 获取模型列表 | 第 3.1 章 |
| `providers.*.support_connection_check` | bool | `true` | 是否支持连接检查 | 第 3.1 章 |
| `providers.*.generate_kwargs` | dict | `{}` | 生成参数（per-model 级别覆盖） | 第 3.1 章 |

### B.3.2 内置 Provider

| Provider ID | 说明 | 默认模型 |
|-------------|------|----------|
| `openai` | OpenAI GPT 系列 | gpt-4o, gpt-4o-mini, gpt-4-turbo |
| `anthropic` | Anthropic Claude 系列 | claude-3-5-sonnet, claude-3-haiku |
| `google` | Google Gemini 系列 | gemini-1.5-pro, gemini-1.5-flash |
| `ollama` | Ollama 本地模型 | qwen2.5, llama3 |
| `lmstudio` | LM Studio 本地模型 | - |
| `openrouter` | OpenRouter 聚合 | - |
| `dashscope` | 阿里云 DashScope | qwen3-max, qwen3-235b-a22b-thinking |
| `modelscope` | ModelScope 魔搭 | Qwen3.5-122B-A10B |

---

## B.4 Memory 配置

### B.4.1 运行时配置（AgentsRunningConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `running.max_iters` | int | `100` | ReAct Agent 最大迭代次数 | 第 2.2 章 |
| `running.auto_continue_on_text_only` | bool | `false` | 模型仅返回文本时是否继续 | 第 2.2 章 |
| `running.llm_retry_enabled` | bool | `true` | 是否启用 LLM 自动重试 | 第 2.2 章 |
| `running.llm_max_retries` | int | `3` | LLM 最大重试次数 | 第 2.2 章 |
| `running.llm_backoff_base` | float | `1.0` | LLM 重试指数退避基础值（秒） | 第 2.2 章 |
| `running.llm_backoff_cap` | float | `10.0` | LLM 重试指数退避上限（秒） | 第 2.2 章 |
| `running.llm_max_concurrent` | int | `10` | 最大并发 LLM 调用数 | 第 2.2 章 |
| `running.llm_max_qpm` | int | `600` | 每分钟最大查询数（0 表示无限） | 第 2.2 章 |
| `running.llm_rate_limit_pause` | float | `5.0` | 收到 429 时的默认暂停时长（秒） | 第 2.2 章 |
| `running.llm_rate_limit_jitter` | float | `1.0` | 限流暂停的随机抖动范围（秒） | 第 2.2 章 |
| `running.llm_acquire_timeout` | float | `300.0` | 获取限流槽位的超时时间（秒） | 第 2.2 章 |
| `running.max_input_length` | int | `131072` | 模型上下文窗口最大输入长度（tokens） | 第 2.2 章 |
| `running.history_max_length` | int | `10000` | /history 命令输出的最大长度 | 第 2.2 章 |
| `running.memory_manager_backend` | string | `"remelight"` | 记忆管理器后端类型 | 第 2.4 章 |

### B.4.2 Embedding 配置（EmbeddingConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `running.embedding_config.backend` | string | `"openai"` | Embedding 后端类型 | 第 2.4 章 |
| `running.embedding_config.api_key` | string | `""` | Embedding 提供商 API Key | 第 2.4 章 |
| `running.embedding_config.base_url` | string | `""` | Embedding API 基础地址 | 第 2.4 章 |
| `running.embedding_config.model_name` | string | `""` | Embedding 模型名称 | 第 2.4 章 |
| `running.embedding_config.dimensions` | int | `1024` | Embedding 向量维度 | 第 2.4 章 |
| `running.embedding_config.enable_cache` | bool | `true` | 是否启用 Embedding 缓存 | 第 2.4 章 |
| `running.embedding_config.use_dimensions` | bool | `false` | 是否使用自定义维度 | 第 2.4 章 |
| `running.embedding_config.max_cache_size` | int | `3000` | 最大缓存条数 | 第 2.4 章 |
| `running.embedding_config.max_input_length` | int | `8192` | 最大输入长度（tokens） | 第 2.4 章 |
| `running.embedding_config.max_batch_size` | int | `10` | 最大批处理大小 | 第 2.4 章 |

### B.4.3 上下文压缩配置（ContextCompactConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `running.context_compact.token_count_model` | string | `"default"` | Token 计数使用的模型 | 第 2.4 章 |
| `running.context_compact.token_count_use_mirror` | bool | `false` | 是否使用 HuggingFace 镜像 | 第 2.4 章 |
| `running.context_compact.token_count_estimate_divisor` | float | `4` | 字节 Token 估算除数 | 第 2.4 章 |
| `running.context_compact.context_compact_enabled` | bool | `true` | 是否启用自动上下文压缩 | 第 2.4 章 |
| `running.context_compact.memory_compact_ratio` | float | `0.75` | 压缩触发阈值（上下文达到此比例时压缩） | 第 2.4 章 |
| `running.context_compact.memory_reserve_ratio` | float | `0.1` | 压缩后保留的最近上下文比例 | 第 2.4 章 |
| `running.context_compact.compact_with_thinking_block` | bool | `true` | 压缩时是否包含思考块 | 第 2.4 章 |

### B.4.4 工具结果压缩配置（ToolResultCompactConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `running.tool_result_compact.enabled` | bool | `true` | 是否启用工具结果压缩 | 第 2.4 章 |
| `running.tool_result_compact.recent_n` | int | `2` | 使用 recent_max_bytes 的最近消息数 | 第 2.4 章 |
| `running.tool_result_compact.old_max_bytes` | int | `3000` | 旧消息的字节阈值 | 第 2.4 章 |
| `running.tool_result_compact.recent_max_bytes` | int | `50000` | 最近消息的字节阈值 | 第 2.4 章 |
| `running.tool_result_compact.retention_days` | int | `5` | 工具结果文件保留天数 | 第 2.4 章 |

### B.4.5 记忆摘要配置（MemorySummaryConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `running.memory_summary.memory_summary_enabled` | bool | `true` | 是否启用记忆摘要 | 第 2.4 章 |
| `running.memory_summary.memory_prompt_enabled` | bool | `true` | 是否在系统提示中包含记忆引导 | 第 2.4 章 |
| `running.memory_summary.dream_cron` | string | `"0 23 * * *"` | 梦境优化作业的 Cron 表达式（空则禁用） | 第 2.4 章 |
| `running.memory_summary.force_memory_search` | bool | `false` | 是否每轮强制搜索记忆 | 第 2.4 章 |
| `running.memory_summary.force_max_results` | int | `1` | 强制记忆搜索的最大结果数 | 第 2.4 章 |
| `running.memory_summary.force_min_score` | float | `0.3` | 强制记忆搜索的最小相关度分数 | 第 2.4 章 |
| `running.memory_summary.force_memory_search_timeout` | float | `10.0` | 强制记忆搜索超时（秒） | 第 2.4 章 |
| `running.memory_summary.rebuild_memory_index_on_start` | bool | `false` | 启动时是否重建记忆索引 | 第 2.4 章 |
| `running.memory_summary.recursive_file_watcher` | bool | `false` | 是否递归监视记忆目录 | 第 2.4 章 |

---

## B.5 Guard / 安全配置

### B.5.1 工具守卫配置（ToolGuardConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `security.tool_guard.enabled` | bool | `true` | 是否启用工具守卫 | 第 4.1 章 |
| `security.tool_guard.guarded_tools` | list | `null` | 要守卫的工具列表（null 表示使用内置默认集） | 第 4.1 章 |
| `security.tool_guard.denied_tools` | list | `[]` | 明确拒绝的工具列表 | 第 4.1 章 |
| `security.tool_guard.custom_rules` | list | `[]` | 自定义守卫规则列表 | 第 4.1 章 |
| `security.tool_guard.disabled_rules` | list | `[]` | 禁用的规则 ID 列表 | 第 4.1 章 |

### B.5.2 自定义规则配置（ToolGuardRuleConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `security.tool_guard.custom_rules.*.id` | string | - | 规则唯一标识符 | 第 4.1 章 |
| `security.tool_guard.custom_rules.*.tools` | list | `[]` | 关联的工具列表 | 第 4.1 章 |
| `security.tool_guard.custom_rules.*.params` | list | `[]` | 检查的参数列表 | 第 4.1 章 |
| `security.tool_guard.custom_rules.*.category` | string | `"command_injection"` | 威胁类别 | 第 4.1 章 |
| `security.tool_guard.custom_rules.*.severity` | string | `"HIGH"` | 严重等级：`LOW`、`MEDIUM`、`HIGH`、`CRITICAL` | 第 4.1 章 |
| `security.tool_guard.custom_rules.*.patterns` | list | `[]` | 匹配模式列表（正则表达式） | 第 4.1 章 |
| `security.tool_guard.custom_rules.*.exclude_patterns` | list | `[]` | 排除模式列表（正则表达式） | 第 4.1 章 |
| `security.tool_guard.custom_rules.*.description` | string | `""` | 规则描述 | 第 4.1 章 |
| `security.tool_guard.custom_rules.*.remediation` | string | `""` | 修复建议 | 第 4.1 章 |

### B.5.3 文件守卫配置（FileGuardConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `security.file_guard.enabled` | bool | `true` | 是否启用文件守卫 | 第 4.1 章 |
| `security.file_guard.sensitive_files` | list | `[]` | 敏感文件路径列表 | 第 4.1 章 |

### B.5.4 Skill 扫描器配置（SkillScannerConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `security.skill_scanner.mode` | string | `"warn"` | 扫描模式：`block`（阻止）、`warn`（警告）、`off`（关闭） | 第 4.2 章 |
| `security.skill_scanner.timeout` | int | `30` | 扫描最大等待秒数 | 第 4.2 章 |
| `security.skill_scanner.whitelist` | list | `[]` | 白名单 Skill 列表 | 第 4.2 章 |

---

## B.6 MCP 配置

### B.6.1 MCP 客户端配置（MCPClientConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `mcp.clients.*.name` | string | - | MCP 客户端名称 | 第 3.3 章 |
| `mcp.clients.*.description` | string | `""` | MCP 客户端描述 | 第 3.3 章 |
| `mcp.clients.*.enabled` | bool | `true` | 是否启用 | 第 3.3 章 |
| `mcp.clients.*.transport` | string | `"stdio"` | 传输类型：`stdio`、`streamable_http`、`sse` | 第 3.3 章 |
| `mcp.clients.*.url` | string | `""` | 服务器 URL（用于 http 传输） | 第 3.3 章 |
| `mcp.clients.*.headers` | dict | `{}` | HTTP 请求头 | 第 3.3 章 |
| `mcp.clients.*.command` | string | `""` | 启动命令（用于 stdio 传输） | 第 3.3 章 |
| `mcp.clients.*.args` | list | `[]` | 命令参数 | 第 3.3 章 |
| `mcp.clients.*.env` | dict | `{}` | 环境变量 | 第 3.3 章 |
| `mcp.clients.*.cwd` | string | `""` | 工作目录 | 第 3.3 章 |

### B.6.2 内置 MCP 客户端

| 客户端名称 | 说明 | 默认启用条件 |
|-----------|------|-------------|
| `tavily_search` | Tavily 网络搜索 | 环境变量 `TAVILY_API_KEY` 存在时自动启用 |

---

## B.7 ACP 配置

### B.7.1 ACP Agent 配置（ACPAgentConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `acp.agents.*.enabled` | bool | `false` | 是否启用 | 第 3.5 章 |
| `acp.agents.*.command` | string | `""` | 启动命令 | 第 3.5 章 |
| `acp.agents.*.args` | list | `[]` | 命令参数 | 第 3.5 章 |
| `acp.agents.*.env` | dict | `{}` | 环境变量 | 第 3.5 章 |
| `acp.agents.*.trusted` | bool | `true` | 是否信任（信任时跳过安全扫描） | 第 3.5 章 |
| `acp.agents.*.tool_parse_mode` | string | `"call_title"` | 工具解析模式 | 第 3.5 章 |
| `acp.agents.*.stdio_buffer_limit_bytes` | int | `52428800` | 标准 I/O 缓冲区限制（50MB） | 第 3.5 章 |

### B.7.2 内置 ACP Agent

| Agent 名称 | command | 默认启用 | tool_parse_mode |
|------------|---------|----------|-----------------|
| `opencode` | `opencode` | `true` | `update_detail` |
| `qwen_code` | `qwen --acp` | `true` | `call_detail` |
| `claude_code` | `npx -y @zed-industries/claude-agent-acp` | `true` | `update_detail` |
| `codex` | `npx -y @zed-industries/codex-acp` | `true` | `call_detail` |

---

## B.8 工具配置

### B.8.1 内置工具配置（BuiltinToolConfig）

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `tools.builtin_tools.*.name` | string | - | 工具函数名 | 第 2.3 章 |
| `tools.builtin_tools.*.enabled` | bool | `true` | 是否启用 | 第 2.3 章 |
| `tools.builtin_tools.*.description` | string | `""` | 工具描述 | 第 2.3 章 |
| `tools.builtin_tools.*.display_to_user` | bool | `true` | 是否向用户显示工具输出 | 第 2.3 章 |
| `tools.builtin_tools.*.async_execution` | bool | `false` | 是否异步执行 | 第 2.3 章 |
| `tools.builtin_tools.*.icon` | string | `null` | 工具图标（emoji） | 第 2.3 章 |

### B.8.2 内置工具列表

| 工具名称 | 默认启用 | 说明 | 图标 |
|----------|---------|------|------|
| `execute_shell_command` | 是 | 执行 Shell 命令 | 💻 |
| `read_file` | 是 | 读取文件内容 | 📄 |
| `write_file` | 是 | 写入文件内容 | ✍️ |
| `edit_file` | 是 | 使用查找替换编辑文件 | 🖊️ |
| `grep_search` | 是 | 按模式搜索文件内容 | 🔍 |
| `glob_search` | 是 | 查找匹配 glob 模式的文件 | 📁 |
| `browser_use` | 是 | 浏览器自动化和网页交互 | 🌐 |
| `desktop_screenshot` | 是 | 捕获桌面截图 | 📸 |
| `view_image` | 是 | 将图片加载到 LLM 上下文进行视觉分析 | 🖼️ |
| `view_video` | 是 | 将视频加载到 LLM 上下文进行视觉分析 | 🎥 |
| `send_file_to_user` | 是 | 发送文件给用户 | 📤 |
| `get_current_time` | 是 | 获取当前日期和时间 | 🕐 |
| `set_user_timezone` | 是 | 设置用户时区 | 🌍 |
| `get_token_usage` | 是 | 获取 LLM Token 使用量 | 📊 |
| `delegate_external_agent` | 否 | 委托给外部 ACP Agent 运行器 | 📡 |
| `list_agents` | 是 | 列出本地 API 配置的智能体 | 🤖 |
| `chat_with_agent` | 是 | 向另一个智能体发送消息并等待响应 | 💬 |
| `submit_to_agent` | 是 | 向另一个智能体提交后台任务 | 📨 |
| `check_agent_task` | 是 | 检查后台智能体任务状态 | ⏳ |

---

## B.9 其他配置

### B.9.1 API 配置

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `last_api.host` | string | `null` | 上次使用的 API 主机 | 第 2.1 章 |
| `last_api.port` | int | `null` | 上次使用的 API 端口 | 第 2.1 章 |
| `show_tool_details` | bool | `true` | 是否显示工具执行详情 | 第 2.1 章 |
| `user_timezone` | string | `(系统时区)` | 用户 IANA 时区 | 第 2.4 章 |

### B.9.2 Heartbeat 配置

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `agents.defaults.heartbeat.enabled` | bool | `false` | 是否启用心跳 | 第 2.5 章 |
| `agents.defaults.heartbeat.every` | string | `"6h"` | 心跳间隔（如 `6h`、`30m`） | 第 2.5 章 |
| `agents.defaults.heartbeat.target` | string | `"main"` | 心跳目标（`main` 或 `last`） | 第 2.5 章 |
| `agents.defaults.heartbeat.active_hours.start` | string | `"08:00"` | 活跃时段开始时间 | 第 2.5 章 |
| `agents.defaults.heartbeat.active_hours.end` | string | `"22:00"` | 活跃时段结束时间 | 第 2.5 章 |

### B.9.3 插件配置

| 配置路径 | 类型 | 默认值 | 说明 | 涉及章节 |
|---------|------|--------|------|----------|
| `plugins.*` | dict | `{}` | 插件特定配置（键为 plugin_id） | 第 3.6 章 |

---

## B.10 完整配置示例

以下是一个完整的 `config.json` 配置示例：

```json
{
  "channels": {
    "console": {
      "enabled": true,
      "media_dir": null
    },
    "discord": {
      "enabled": false,
      "bot_token": "",
      "http_proxy": "",
      "http_proxy_auth": "",
      "accept_bot_messages": false,
      "bot_prefix": "",
      "filter_tool_messages": false,
      "filter_thinking": false,
      "dm_policy": "open",
      "group_policy": "open",
      "allow_from": [],
      "deny_message": "",
      "require_mention": false
    }
  },
  "mcp": {
    "clients": {
      "tavily_search": {
        "name": "tavily_mcp",
        "enabled": false,
        "command": "npx",
        "args": ["-y", "tavily-mcp@latest"],
        "env": {
          "TAVILY_API_KEY": ""
        }
      }
    }
  },
  "tools": {
    "builtin_tools": {
      "execute_shell_command": {"name": "execute_shell_command", "enabled": true, "icon": "💻"},
      "read_file": {"name": "read_file", "enabled": true, "icon": "📄"},
      "write_file": {"name": "write_file", "enabled": true, "icon": "✍️"},
      "edit_file": {"name": "edit_file", "enabled": true, "icon": "🖊️"},
      "grep_search": {"name": "grep_search", "enabled": true, "icon": "🔍"},
      "glob_search": {"name": "glob_search", "enabled": true, "icon": "📁"},
      "browser_use": {"name": "browser_use", "enabled": true, "icon": "🌐"},
      "desktop_screenshot": {"name": "desktop_screenshot", "enabled": true, "icon": "📸"},
      "view_image": {"name": "view_image", "enabled": true, "icon": "🖼️"},
      "view_video": {"name": "view_video", "enabled": true, "icon": "🎥"},
      "send_file_to_user": {"name": "send_file_to_user", "enabled": true, "icon": "📤"},
      "get_current_time": {"name": "get_current_time", "enabled": true, "icon": "🕐"},
      "set_user_timezone": {"name": "set_user_timezone", "enabled": true, "icon": "🌍"},
      "get_token_usage": {"name": "get_token_usage", "enabled": true, "icon": "📊"},
      "delegate_external_agent": {"name": "delegate_external_agent", "enabled": false, "icon": "📡"},
      "list_agents": {"name": "list_agents", "enabled": true, "icon": "🤖"},
      "chat_with_agent": {"name": "chat_with_agent", "enabled": true, "icon": "💬"},
      "submit_to_agent": {"name": "submit_to_agent", "enabled": true, "icon": "📨"},
      "check_agent_task": {"name": "check_agent_task", "enabled": true, "icon": "⏳"}
    }
  },
  "agents": {
    "active_agent": "default",
    "agent_order": ["default"],
    "language": "zh",
    "system_prompt_files": ["AGENTS.md", "SOUL.md", "PROFILE.md"],
    "audio_mode": "auto",
    "transcription_provider_type": "disabled",
    "transcription_provider_id": "",
    "transcription_model": "whisper-1",
    "running": {
      "max_iters": 100,
      "auto_continue_on_text_only": false,
      "llm_retry_enabled": true,
      "llm_max_retries": 3,
      "llm_backoff_base": 1.0,
      "llm_backoff_cap": 10.0,
      "llm_max_concurrent": 10,
      "llm_max_qpm": 600,
      "llm_rate_limit_pause": 5.0,
      "llm_rate_limit_jitter": 1.0,
      "llm_acquire_timeout": 300.0,
      "max_input_length": 131072,
      "history_max_length": 10000,
      "memory_manager_backend": "remelight",
      "context_compact": {
        "token_count_model": "default",
        "token_count_use_mirror": false,
        "token_count_estimate_divisor": 4.0,
        "context_compact_enabled": true,
        "memory_compact_ratio": 0.75,
        "memory_reserve_ratio": 0.1,
        "compact_with_thinking_block": true
      },
      "tool_result_compact": {
        "enabled": true,
        "recent_n": 2,
        "old_max_bytes": 3000,
        "recent_max_bytes": 50000,
        "retention_days": 5
      },
      "memory_summary": {
        "memory_summary_enabled": true,
        "memory_prompt_enabled": true,
        "dream_cron": "0 23 * * *",
        "force_memory_search": false,
        "force_max_results": 1,
        "force_min_score": 0.3,
        "force_memory_search_timeout": 10.0,
        "rebuild_memory_index_on_start": false,
        "recursive_file_watcher": false
      },
      "embedding_config": {
        "backend": "openai",
        "api_key": "",
        "base_url": "",
        "model_name": "",
        "dimensions": 1024,
        "enable_cache": true,
        "use_dimensions": false,
        "max_cache_size": 3000,
        "max_input_length": 8192,
        "max_batch_size": 10
      }
    },
    "llm_routing": {
      "enabled": false,
      "mode": "local_first",
      "local": {"provider_id": "", "model": ""},
      "cloud": null
    },
    "profiles": {
      "default": {
        "id": "default",
        "workspace_dir": "~/.qwenpaw/workspaces/default",
        "enabled": true
      }
    }
  },
  "security": {
    "tool_guard": {
      "enabled": true,
      "guarded_tools": null,
      "denied_tools": [],
      "custom_rules": [],
      "disabled_rules": []
    },
    "file_guard": {
      "enabled": true,
      "sensitive_files": []
    },
    "skill_scanner": {
      "mode": "warn",
      "timeout": 30,
      "whitelist": []
    }
  },
  "acp": {
    "agents": {
      "opencode": {
        "enabled": true,
        "command": "opencode",
        "args": ["acp"],
        "trusted": true,
        "tool_parse_mode": "update_detail",
        "stdio_buffer_limit_bytes": 52428800
      },
      "qwen_code": {
        "enabled": true,
        "command": "qwen",
        "args": ["--acp"],
        "trusted": true,
        "tool_parse_mode": "call_detail",
        "stdio_buffer_limit_bytes": 52428800
      },
      "claude_code": {
        "enabled": true,
        "command": "npx",
        "args": ["-y", "@zed-industries/claude-agent-acp"],
        "trusted": true,
        "tool_parse_mode": "update_detail",
        "stdio_buffer_limit_bytes": 52428800
      },
      "codex": {
        "enabled": true,
        "command": "npx",
        "args": ["-y", "@zed-industries/codex-acp"],
        "trusted": true,
        "tool_parse_mode": "call_detail",
        "stdio_buffer_limit_bytes": 52428800
      }
    }
  },
  "show_tool_details": true,
  "user_timezone": "Asia/Shanghai",
  "plugins": {}
}
```

---

## B.11 配置路径速查表

### B.11.1 按配置用途速查

| 用途 | 配置路径 |
|------|----------|
| 修改默认智能体语言 | `agents.language` |
| 启用/禁用工具 | `tools.builtin_tools.<tool_name>.enabled` |
| 配置 Discord Bot | `channels.discord.bot_token` |
| 配置飞书应用 | `channels.feishu.app_id` / `channels.feishu.app_secret` |
| 配置 LLM 提供商 API Key | `providers.<provider_id>.api_key` |
| 配置 LLM 重试策略 | `running.llm_max_retries` / `running.llm_backoff_base` |
| 启用 LLM 路由 | `llm_routing.enabled` |
| 配置 Embedding 模型 | `running.embedding_config` |
| 启用上下文压缩 | `running.context_compact.context_compact_enabled` |
| 配置心跳任务 | `agents.defaults.heartbeat` |
| 启用工具守卫 | `security.tool_guard.enabled` |
| 配置 MCP 客户端 | `mcp.clients.<client_name>` |
| 配置 ACP Agent | `acp.agents.<agent_name>` |
| 配置插件 | `plugins.<plugin_id>` |

### B.11.2 按数据类型速查

| 类型 | 配置路径 |
|------|----------|
| 布尔值（开关） | `channels.console.enabled`、`security.tool_guard.enabled` |
| 字符串 | `agents.language`、`channels.feishu.app_id` |
| 整数 | `running.max_iters`、`running.llm_max_qpm` |
| 浮点数 | `running.llm_backoff_base`、`running.llm_rate_limit_pause` |
| 列表 | `agents.system_prompt_files`、`tools.builtin_tools` |
| 字典/对象 | `running.context_compact`、`mcp.clients.tavily_search` |
