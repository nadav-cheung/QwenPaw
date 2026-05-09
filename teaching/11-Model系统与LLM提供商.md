# Model 系统与 LLM 提供商

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 描述 Provider 抽象层的架构设计 2) 配置和管理多个 LLM 提供商 3) 理解 RetryChatModel 的重试和限流机制 4) 解释 Formatter 的消息格式化流程 |
| **前置知识** | [07-智能体核心架构](./07-智能体核心架构.md)、[03-项目架构](./03-项目架构.md) |
| **预计时长** | 50 分钟（阅读 30 分钟 + 练习 20 分钟） |
| **难度等级** | ⭐⭐⭐ |
| **核心关键词** | `Provider` `RetryChatModel` `Formatter` `限流` `模型切换` |

> **一句话概述**：深入讲解 QwenPaw 的模型系统架构，从 Provider 抽象到重试限流机制，帮你掌握 LLM 调用的完整链路。

## 概述

QwenPaw 支持接入多个 LLM 提供商，通过统一的 `ProviderManager` 管理模型配置、密钥加密和多模型支持。本教程深入讲解 Provider 系统架构、支持的提供商、以及如何配置和使用模型。

---

## 1. Provider 系统架构

### 1.1 核心组件

```
providers/
├── __init__.py
├── provider_manager.py    # ProviderManager - 单例管理器
├── provider.py            # Provider, ModelInfo, ProviderInfo - 基类和模型
├── anthropic_provider.py # Anthropic 提供商
├── openai_provider.py    # OpenAI 提供商
├── gemini_provider.py    # Google Gemini 提供商
├── ollama_provider.py     # Ollama 本地模型
├── lmstudio_provider.py   # LM Studio 本地模型
├── openrouter_provider.py # OpenRouter 聚合
├── retry_chat_model.py    # RetryChatModel - 重试包装器
├── rate_limiter.py        # LLMRateLimiter - 速率限制器
├── capability_baseline.py # 模型能力探测
└── multimodal_prober.py   # 多模态能力探测
```

### 1.2 ProviderManager 单例

`ProviderManager` 是全局唯一的提供商管理器：

```python
class ProviderManager:
    """单例模式的提供商管理器"""

    _instance: Optional["ProviderManager"] = None

    def __init__(self) -> None:
        self.builtin_providers: Dict[str, Provider] = {}
        self.custom_providers: Dict[str, Provider] = {}
        self.plugin_providers: Dict[str, Dict] = {}
        self.active_model: ModelSlotConfig | None = None
        self._prepare_disk_storage()
        self._init_builtins()  # 初始化20+内置提供商

    @staticmethod
    def get_instance() -> "ProviderManager":
        if ProviderManager._instance is None:
            ProviderManager._instance = ProviderManager()
        return ProviderManager._instance
```

**源码路径**: `src/qwenpaw/providers/provider_manager.py`

**`_init_builtins` 方法** (第760-784行) - 初始化所有内置提供商：

```python
def _init_builtins(self):
    """注册20+内置提供商"""
    self._add_builtin(PROVIDER_QWENPAW)        # QwenPaw 本地
    self._add_builtin(PROVIDER_OLLAMA)          # Ollama 本地模型
    self._add_builtin(PROVIDER_LMSTUDIO)        # LM Studio
    self._add_builtin(PROVIDER_OPENROUTER)      # OpenRouter 聚合
    self._add_builtin(PROVIDER_MODELSCOPE)       # 魔搭
    self._add_builtin(PROVIDER_DASHSCOPE)       # 阿里云 DashScope
    self._add_builtin(PROVIDER_ALIYUN_CODINGPLAN)  # 阿里云编程计划
    self._add_builtin(PROVIDER_OPENCODE)         # OpenCode
    self._add_builtin(PROVIDER_OPENAI)           # OpenAI
    self._add_builtin(PROVIDER_AZURE_OPENAI)     # Azure OpenAI
    self._add_builtin(PROVIDER_ANTHROPIC)       # Anthropic
    self._add_builtin(PROVIDER_GEMINI)           # Google Gemini
    self._add_builtin(PROVIDER_DEEPSEEK)        # DeepSeek
    self._add_builtin(PROVIDER_KIMI_CN)         # Kimi 中文
    self._add_builtin(PROVIDER_KIMI_INTL)        # Kimi 国际
    self._add_builtin(PROVIDER_MINIMAX_CN)       # MiniMax 中文
    self._add_builtin(PROVIDER_MINIMAX)          # MiniMax 国际
    self._add_builtin(PROVIDER_ZHIPU_CN)         # 智谱 中文
    self._add_builtin(PROVIDER_ZHIPU_INTL)       # 智谱 国际
    self._add_builtin(PROVIDER_SILICONFLOW_CN)  # SiliconFlow 中文
    self._add_builtin(PROVIDER_SILICONFLOW_INTL) # SiliconFlow 国际
```

**核心职责**：
- 管理所有内置和自定义提供商
- 维护 `config.json` 中的提供商配置
- 加密存储 API Key（Fernet 对称加密）
- 模型能力探测（多模态支持检测）
- 从磁盘加载和持久化提供商配置

---

## 2. 支持的 LLM 提供商

### 2.1 云端提供商

| 提供商 ID | 类名 | 支持模型发现 | 官方文档 |
|-----------|------|-------------|----------|
| `openai` | OpenAIProvider | 否 | [OpenAI](https://platform.openai.com/) |
| `anthropic` | AnthropicProvider | 否 | [Anthropic](https://www.anthropic.com/) |
| `gemini` | GeminiProvider | 否 | [Google](https://ai.google.dev/) |
| `dashscope` | OpenAIProvider | 否 | [阿里云](https://dashscope.console.aliyun.com/) |
| `deepseek` | OpenAIProvider | 否 | [DeepSeek](https://platform.deepseek.com/) |
| `kimi-cn` / `kimi-intl` | OpenAIProvider | 否 | [月之暗面](https://platform.moonshot.cn/) |
| `minimax-cn` / `minimax` | AnthropicProvider | 否 | [MiniMax](https://platform.minimax.chat/) |
| `zhipu-cn` / `zhipu-intl` | OpenAIProvider | 否 | [智谱AI](https://open.bigmodel.cn/) |
| `openrouter` | OpenRouterProvider | 是 | [OpenRouter](https://openrouter.ai/) |
| `modelscope` | OpenAIProvider | 否 | [魔搭](https://modelscope.cn/) |
| `siliconflow-cn` / `siliconflow-intl` | OpenAIProvider | 否 | [SiliconFlow](https://siliconflow.cn/) |

### 2.2 本地模型提供商

| 提供商 ID | 类名 | 支持模型发现 | 特点 |
|-----------|------|-------------|------|
| `ollama` | OllamaProvider | 是 | 跨平台，自动发现本地模型 |
| `lmstudio` | LMStudioProvider | 是 | 跨平台，API 兼容 OpenAI |
| `qwenpaw-local` | OpenAIProvider | 是 | QwenPaw 内置 llama.cpp |

### 2.3 阿里云编程计划提供商

| 提供商 ID | 类名 | Base URL | 特点 |
|-----------|------|----------|------|
| `aliyun-codingplan` | OpenAIProvider | `https://coding.dashscope.aliyuncs.com/v1` | 中国区 |
| `aliyun-codingplan-intl` | OpenAIProvider | `https://coding-intl.dashscope.aliyuncs.com/v1` | 国际区 |
| `zhipu-cn-codingplan` | OpenAIProvider | `https://open.bigmodel.cn/api/coding/paas/v4` | 智谱编程计划 |
| `zhipu-intl-codingplan` | OpenAIProvider | `https://api.z.ai/api/coding/paas/v4` | 智谱国际编程计划 |

### 2.4 支持的模型列表

```python
# Qwen 系列
qwen3-max, qwen3-235b-a22b-thinking

# DeepSeek 系列
deepseek-chat, deepseek-reasoner, deepseek-r1

# Kimi 系列
kimi-k2.5, kimi-k2-thinking, moonshot-v1

# MiniMax 系列
MiniMax-M2.5, MiniMax-M2.7-highspeed

# GPT 系列
gpt-5, gpt-5-mini, gpt-5-nano
gpt-4.1, gpt-4.1-mini, gpt-4.1-nano
gpt-4o, gpt-4o-mini

# Claude 系列
claude-3-7-sonnet, claude-3-5-sonnet, claude-3-5-haiku

# Gemini 系列
gemini-3.1-pro, gemini-3.1-flash, gemini-2.5-flash

# GLM 系列
glm-5, glm-5-turbo, glm-4
```

---

## 3. Provider 配置

### 3.1 配置模型

```python
# config/config.py

class ModelSlotConfig(BaseModel):
    """单个模型槽位配置"""
    provider_id: str                          # 提供商 ID
    model: str                                # 模型名称
    api_key: Optional[str] = None             # API Key（可选）
    base_url: Optional[str] = None            # 自定义端点
    api_version: Optional[str] = None         # API 版本
    extra_headers: Optional[Dict[str, str]] = None  # 额外请求头
    timeout: Optional[float] = None           # 请求超时
    max_retries: int = 3                     # 最大重试次数

class ProviderConfig(BaseModel):
    """提供商配置"""
    provider_id: str
    enabled: bool = True
    api_key: Optional[str] = None
    base_url: Optional[str] = None
    api_version: Optional[str] = None
    extra_headers: Optional[Dict[str, str]] = None
    models: List[ModelSlotConfig] = []
```

### 3.2 配置文件结构

`~/.qwenpaw/config.json` 中的提供商配置：

```json
{
  "providers": {
    "openai": {
      "enabled": true,
      "api_key": "encrypted:xxxxx",
      "models": [
        {
          "model": "gpt-4o",
          "enabled": true
        },
        {
          "model": "gpt-4o-mini",
          "enabled": true
        }
      ]
    },
    "dashscope": {
      "enabled": true,
      "api_key": "encrypted:xxxxx",
      "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
      "models": [
        {
          "model": "qwen3-max",
          "enabled": true
        }
      ]
    },
    "ollama": {
      "enabled": true,
      "base_url": "http://localhost:11434",
      "models": []
    }
  }
}
```

### 3.3 API Key 加密

```python
from qwenpaw.security.secret_store import encrypt_dict_fields, decrypt_dict_fields

# 加密敏感字段
encrypted_config = encrypt_dict_fields(
    config_dict,
    fields=["api_key", "client_secret"],
    secret_dir=Path("~/.qwenpaw/.secret")
)

# 解密字段
decrypted_config = decrypt_dict_fields(
    encrypted_config,
    fields=["api_key"]
)
```

**密钥存储层级**：
1. OS Keychain（系统密钥链）
2. `~/.qwenpaw/.secret/.master_key`（本地密钥文件）

---

## 4. 模型选择与切换

### 4.1 命令行选择模型

```bash
# 查看可用模型
qwenpaw models list

# 切换模型
qwenpaw models set-llm --agent default --provider openai --model gpt-4o

# 在对话中切换
/model gpt-4o
```

### 4.2 控制台配置

1. 打开 **http://127.0.0.1:8088/** → **设置** → **模型**
2. 选择提供商
3. 填写 API Key
4. 选择要启用的模型
5. 设置默认模型

### 4.3 动态模型切换

```python
# 通过 API 动态切换
from qwenpaw.app.api import router

# PUT /api/config/model
{
    "agent_id": "default",
    "provider_id": "openai",
    "model": "gpt-4o"
}
```

### 4.4 ProviderManager 模型管理方法

**源码路径**: `src/qwenpaw/providers/provider_manager.py`

**`fetch_provider_models` 方法** (第900-941行) - 获取提供商支持的模型列表：

```python
async def fetch_provider_models(
    self,
    provider_id: str,
    save: bool = True,
) -> List[ModelInfo]:
    """Fetch the list of available models from a provider.

    Args:
        provider_id: The ID of the provider to fetch models from.
        save: If True, save the discovered models to the provider
            configuration. Defaults to True.

    Returns:
        List of ModelInfo objects representing available models.
    """
    provider = self.get_provider(provider_id)
    if not provider:
        return []
    models = await provider.fetch_models()
    if save:
        provider.extra_models = models
        # 保存到磁盘
        self._save_provider(
            provider,
            is_builtin=provider_id in self.builtin_providers,
        )
    return models
```

**`activate_model` 方法** (第987-1009行) - 激活指定模型：

```python
async def activate_model(self, provider_id: str, model_id: str):
    """Set the active provider and model for the agent."""
    provider = self.get_provider(provider_id)
    if not provider:
        raise ProviderError(f"Provider '{provider_id}' not found.")
    if not provider.has_model(model_id):
        raise ModelNotFoundException(
            model_name=f"{provider_id}/{model_id}",
        )
    self.active_model = ModelSlotConfig(
        provider_id=provider_id,
        model=model_id,
    )
    self.save_active_model(self.active_model)
    # 自动探测多模态能力
    self.maybe_probe_multimodal(provider_id, model_id)
```

**`get_provider` 方法** (第823-839行) - 获取提供商实例：

```python
def get_provider(self, provider_id: str) -> Provider | None:
    """Return a provider instance by its ID.

    检查顺序: plugin_providers → builtin_providers → custom_providers
    """
    # 兼容旧名称
    provider_id = self._normalize_provider_id(provider_id)
    if provider_id in self.plugin_providers:
        plugin_provider = self.plugin_providers[provider_id]
        provider_info = plugin_provider["info"]
        provider_class = plugin_provider["class"]
        return provider_class(**provider_info.model_dump())
    if provider_id in self.builtin_providers:
        return self.builtin_providers[provider_id]
    if provider_id in self.custom_providers:
        return self.custom_providers[provider_id]
    return None
```

---

## 5. 并发控制与速率限制

### 5.1 并发配置

```python
# constant.py
LLM_MAX_CONCURRENT = 10    # 最大并发调用数
LLM_MAX_QPM = 600          # 每分钟最大请求数
LLM_RATE_LIMIT_PAUSE = 5.0 # 限流暂停时间（秒）
LLM_ACQUIRE_TIMEOUT = 300.0 # 获取信号量超时（秒）
```

### 5.2 RetryChatModel 重试机制

```python
class RetryConfig:
    enabled: bool = True
    max_retries: int = 3
    backoff_base: float = 1.0  # 初始退避时间（秒）
    backoff_cap: float = 10.0  # 最大退避时间

class RateLimitConfig:
    max_concurrent: int = 10
    max_qpm: int = 600
    pause_seconds: float = 5.0
    jitter_range: float = 1.0
```

### 5.3 RetryChatModel 重试机制

**源码路径**: `src/qwenpaw/providers/retry_chat_model.py`

`RetryChatModel` 包装器实现指数退避重试，核心组件：

| 组件 | 行号 | 说明 |
|------|------|------|
| `RetryConfig` | 47 | 重试策略配置（启用、最大重试次数、退避基数/上限）|
| `RateLimitConfig` | 60 | 速率限制配置（最大并发、QPM、暂停时间）|
| `RetryChatModel` | 144 | 重试包装器类 |
| `_is_retryable()` | 88 | 判断异常是否可重试 |
| `_is_rate_limit()` | 95 | 判断是否为 429 限流错误 |
| `_extract_retry_after()` | 98 | 解析 Retry-After 头 |
| `_compute_backoff()` | 133 | 计算指数退避时间 |

**RetryConfig 和 RateLimitConfig 数据类** (`retry_chat_model.py:59-89`):

```python
# retry_chat_model.py:59
@dataclass(frozen=True, slots=True)
class RetryConfig:
    """Retry policy for transient LLM API failures."""
    enabled: bool = LLM_MAX_RETRIES > 0
    max_retries: int = max(LLM_MAX_RETRIES, 1)
    backoff_base: float = LLM_BACKOFF_BASE      # 默认 1.0s
    backoff_cap: float = LLM_BACKOFF_CAP          # 默认 10.0s

# retry_chat_model.py:69
@dataclass(frozen=True, slots=True)
class RateLimitConfig:
    """Rate-limiting policy for LLM calls.

    Controls the global LLMRateLimiter singleton that caps concurrency and
    coordinates pauses when a 429 is received.
    """
    max_concurrent: int = LLM_MAX_CONCURRENT      # 默认 10
    max_qpm: int = LLM_MAX_QPM                   # 默认 600
    pause_seconds: float = LLM_RATE_LIMIT_PAUSE  # 默认 5.0s
    jitter_range: float = LLM_RATE_LIMIT_JITTER  # 默认 1.0s
    acquire_timeout: float = LLM_ACQUIRE_TIMEOUT  # 默认 300s，等待信号量槽位的超时时间
```

**RetryChatModel 重试机制核心组件** (`retry_chat_model.py`):

| 组件 | 行号 | 说明 |
|------|------|------|
| `RetryConfig` | 59 | 重试策略配置（启用、最大重试次数、退避基数/上限）|
| `RateLimitConfig` | 69 | 速率限制配置（最大并发、QPM、暂停时间、**acquire_timeout**）|
| `RetryChatModel` | 204 | 重试包装器类 |
| `_is_retryable()` | 124 | 判断异常是否可重试 |
| `_is_rate_limit()` | 137 | 判断是否为 429 限流错误 |
| `_extract_retry_after()` | 142 | 解析 Retry-After 头 |
| `_compute_backoff()` | 196 | 计算指数退避时间 |
| `_consume_stream_with_slot()` | 235 | 流式响应的信号量槽位管理 |

```python
class RetryChatModel(ChatModelBase):
    """Transparent retry wrapper around any :class:`ChatModelBase`.

    委托所有调用到内部模型，透明重试瞬态错误。
    流式响应也支持：流中途失败会从头重试整个请求。
    """

    def __init__(
        self,
        inner: ChatModelBase,
        retry_config: RetryConfig | None = None,
        rate_limit_config: RateLimitConfig | None = None,
    ) -> None:
        super().__init__(model_name=inner.model_name, stream=inner.stream)
        self._inner = inner
        self._retry_config = _normalize_retry_config(retry_config)
        self._rate_limit_config = _normalize_rate_limit_config(rate_limit_config)
```

**信号量槽位传输机制** (`retry_chat_model.py:14-24`, `269-351`):

流式响应独有的槽位管理机制：

- **非流式**： `__call__` 的 finally 块总是释放槽位（`owns_semaphore` 保持 True）
- **流式**：槽位所有权在首个 chunk 到达后转移到 `_consume_stream_with_slot`
  - `__call__` 返回生成器前设置 `owns_semaphore = False`，跳过 finally 块的释放
  - `_consume_stream_with_slot` 在首个 chunk 到达后立即释放槽位
- **`acquired` 布尔标志**：跟踪信号量槽位是否真正获取，防止 `CancelledError` 时虚假释放

```python
# retry_chat_model.py:235
async def _consume_stream_with_slot(self, stream, limiter):
    """槽位在首个 chunk 到达后释放，避免流式响应期间占用槽位"""
    first_chunk = True
    try:
        async for chunk in stream:
            if first_chunk:
                first_chunk = False
                limiter.release()  # 首个 chunk 到达后立即释放
            yield chunk
    finally:
        if first_chunk:
            # 流失败未产生任何 chunk，释放槽位
            limiter.release()
```

**雷鸣 herd 问题防护**：429 时所有并发调用者暂停相同时间（加上各自的随机抖动），避免同时重试造成新一轮限流。

**`_is_retryable` 方法** (第88行) - 判断是否可重试:
```python
RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504, 529}

def _is_retryable(exc: Exception) -> bool:
    """Return *True* if *exc* should trigger a retry."""
    retryable = _get_openai_retryable() + _get_anthropic_retryable()
    if retryable and isinstance(exc, retryable):
        return True
    status = getattr(exc, "status_code", None)
    if status is not None and status in RETRYABLE_STATUS_CODES:
        return True
    return False
```

**流式重试处理** `_wrap_stream` 方法 (第270-340行):
- 流失败时重试整个请求而非仅重试失败的 chunk
- 槽位在首个 chunk 到达后释放，避免其他调用者饥饿

**重试流程图**:
```
chat() 调用
         │
         ▼
获取信号量 (max_concurrent)
         │
         ▼
try: 执行 chat
         │
         ├── 成功 → yield chunks → 释放信号量
         │
         └── 失败
                 │
                 ├── 不可重试 → 释放信号量 → 抛出异常
                 │
                 └── 可重试
                         │
                         ├── 还有重试次数 → 计算延迟 → sleep → 重试
                         │
                         └── 没有重试次数 → 释放信号量 → 抛出异常
```

### 5.4 模型工厂与包装器管道

**源码路径**: `src/qwenpaw/agents/model_factory.py`

`create_model_and_formatter()` 创建模型和格式化器，核心组件：

| 组件 | 行号 | 说明 |
|------|------|------|
| `create_model_and_formatter()` | 930 | 工厂方法入口 |
| `_create_file_block_support_formatter()` | 680 | 创建支持文件块的格式化器 |
| `_normalize_messages_for_formatter()` | 95 | 标准化消息格式 |
| `_format_anthropic_messages()` | 341 | Anthropic 消息格式化 |
| `_format_anthropic_media_block()` | 134 | Anthropic 媒体块格式化 |
| `_format_openai_video_block()` | 201 | OpenAI 视频块格式化 |
| `_promote_tool_result_videos()` | 497 | 提升工具结果中的视频 |
| `_reorder_tool_and_promoted_messages()` | 565 | 重排工具消息顺序 |
| `_fix_image_mime_types()` | 609 | 修复非标准 MIME 类型 |
| `_fixup_media_list()` | 635 | 标准化媒体列表 |
| `_file_url_to_path()` | 49 | 去除 file:// 前缀转路径 |

**create_model_and_formatter()** (第930-1010行):

```python
def create_model_and_formatter(
    agent_id: Optional[str] = None,
) -> Tuple[ChatModelBase, FormatterBase]:
    """Factory method to create model and formatter instances.

    1. 解析 agent_id (参数 > context > None)
    2. 加载代理配置 (RetryConfig, RateLimitConfig)
    3. 获取 provider 和 model
    4. 创建格式化器
    5. 双重包装模型: TokenRecordingModelWrapper → RetryChatModel
    """
    from ..app.agent_context import get_current_agent_id
    from ..config.config import load_agent_config

    # Determine agent_id (parameter > context > None)
    if agent_id is None:
        try:
            agent_id = get_current_agent_id()
        except Exception:
            pass

    # 加载代理配置
    if agent_id:
        agent_config = load_agent_config(agent_id)
        model_slot = agent_config.active_model
        retry_config = RetryConfig(
            enabled=agent_config.running.llm_retry_enabled,
            max_retries=agent_config.running.llm_max_retries,
            backoff_base=agent_config.running.llm_backoff_base,
            backoff_cap=agent_config.running.llm_backoff_cap,
        )
        rate_limit_config = RateLimitConfig(
            max_concurrent=agent_config.running.llm_max_concurrent,
            max_qpm=agent_config.running.llm_max_qpm,
            pause_seconds=agent_config.running.llm_rate_limit_pause,
            jitter_range=agent_config.running.llm_rate_limit_jitter,
            acquire_timeout=agent_config.running.llm_acquire_timeout,
        )

    # 获取 provider 和 model
    if model_slot and model_slot.provider_id and model_slot.model:
        manager = ProviderManager.get_instance()
        provider = manager.get_provider(model_slot.provider_id)
        model = provider.get_chat_model_instance(model_slot.model)
    else:
        model = ProviderManager.get_active_chat_model()

    # 创建格式化器
    formatter = _create_formatter_instance(model.__class__)

    # 双重包装模型
    wrapped_model = TokenRecordingModelWrapper(provider_id, model)
    wrapped_model = RetryChatModel(
        wrapped_model,
        retry_config=retry_config,
        rate_limit_config=rate_limit_config,
    )
    return wrapped_model, formatter
```

**FileBlockSupportFormatter** (`model_factory.py:680-913`):
- 继承任意 Formatter 类，扩展文件块支持
- 处理 thinking blocks（Anthropic 格式）
- 处理视频占位符提升和恢复
- 修复非标准 MIME 类型 (image/jpg → image/jpeg)
- 处理 tool_result 中的媒体块去重
- `convert_tool_result_to_string()` 方法扩展，支持 file 类型 block

**convert_tool_result_to_string 扩展** (`model_factory.py:836-908`):
```python
@staticmethod
def convert_tool_result_to_string(
    output: Union[str, List[dict]],
) -> tuple[str, Sequence[Tuple[str, dict]]]:
    """扩展以支持 file 类型 block。

    处理流程：
    1. 字符串直接返回
    2. 尝试父类方法
    3. 如遇 "Unsupported block type: file"，处理 file block
    4. file block 提取 path/url，返回 (文本描述, multimodal_data)
    """
```

**消息格式化流程**:
```
normalize_messages_for_model_request()
         │
         ├── 检测 formatter 类型 (Anthropic/OpenAI/Gemini)
         │
         ├── _format_anthropic_messages() ──► 处理媒体块和 tool_result
         │
         └── _format_openai_video_block() ──► 视频块转换
                   │
                   ├── _substitute_video_blocks() ──► 替换为占位符
                   ├── super()._format() ──► 父类格式化
                   ├── _replace_video_placeholders() ──► 恢复视频块
                   └── _promote_tool_result_videos() ──► 提升视频到用户消息
```

**包装器管道架构**:

```
ProviderManager.get_active_chat_model()
         │
         ▼
   ┌───────────────────────┐
   │ OpenAIChatModelCompat│
   │ (或 Anthropic/Gemini)│
   └───────────────────────┘
         │ (包装)
         ▼
   ┌─────────────────────────────┐
   │ TokenRecordingModelWrapper │
   │ - 记录 token 使用量          │
   │ - 修复 vLLM tool_choice=auto │
   └─────────────────────────────┘
         │ (包装)
         ▼
   ┌─────────────────────┐
   │   RetryChatModel    │
   │ - 限流信号量         │
   │ - 指数退避重试       │
   └─────────────────────┘
```

**TokenRecordingModelWrapper** (`token_usage/model_wrapper.py` line 15):

```python
class TokenRecordingModelWrapper(ChatModelBase):
    """Token 使用量记录包装器"""

    async def chat(self, messages, **kwargs) -> AsyncIterator[ChatMessage]:
        """包装 chat 方法，记录 token 使用量"""
        usage = None
        async for chunk in self._model.chat(messages, **kwargs):
            # 记录 usage（如果有）
            if hasattr(chunk, "usage") and chunk.usage:
                usage = chunk.usage
            yield chunk

        # 流结束后记录 usage
        if usage:
            await self._record_usage(usage)

    async def _record_usage(self, usage: ChatUsage | None) -> None:
        """记录 token 使用量到会话"""
        if usage:
            session_id = get_current_session_id()
            record_usage(session_id, self.provider_id, usage)

    @classmethod
    def pop_usage_for_session(cls, session_id: str) -> dict[str, Any] | None:
        """获取会话的 token 使用记录"""
        return token_usage_store.pop(session_id)
```

**重试可错误**: `{429, 500, 502, 503, 504, 529}` + OpenAI/Anthropic SDK 可重试异常

**流式安全**: 信号量槽位在首个 chunk 到达后释放 (非完整流结束后)，防止其他调用者饥饿

### 5.5 Token 使用量记录

**TokenUsageStore** (`token_usage/store.py`):

```python
class TokenUsageStore:
    """Token 使用量存储"""

    def __init__(self):
        self._usages: dict[str, list[dict]] = {}

    def record(self, session_id: str, provider_id: str, usage: ChatUsage) -> None:
        """记录单次 token 使用量"""
        if session_id not in self._usages:
            self._usages[session_id] = []
        self._usages[session_id].append({
            "provider_id": provider_id,
            "prompt_tokens": usage.prompt_tokens,
            "completion_tokens": usage.completion_tokens,
            "total_tokens": usage.total_tokens,
            "timestamp": time.time(),
        })

    def pop(self, session_id: str) -> dict[str, Any] | None:
        """获取并清除会话的 token 使用量"""
        return self._usages.pop(session_id, None)

    def get_total(self, session_id: str) -> dict[str, int]:
        """获取会话的总 token 使用量"""
        usages = self._usages.get(session_id, [])
        return {
            "prompt_tokens": sum(u["prompt_tokens"] for u in usages),
            "completion_tokens": sum(u["completion_tokens"] for u in usages),
            "total_tokens": sum(u["total_tokens"] for u in usages),
            "request_count": len(usages),
        }
```

### 5.6 FileBlockSupportFormatter 与思考块

**源码路径**: `model_factory.py` line 695-913

`FileBlockSupportFormatter` 处理 thinking blocks 和视频占位符：

```python
class FileBlockSupportFormatter(base_formatter_class):
    """处理 thinking blocks 和特殊内容块的格式化器"""

    async def _format(self, msgs) -> list[dict]:
        """格式化消息，处理 thinking blocks"""
        formatted = []

        for msg in msgs:
            # 1. 处理 thinking blocks
            if msg.type == "thinking":
                formatted.append({
                    "type": "thinking",
                    "thinking": msg.content,
                })
            # 2. 处理视频占位符
            elif msg.type == "video":
                formatted.append({
                    "type": "video",
                    "video_url": msg.video_url,
                    "placeholder": msg.placeholder or "Video content",
                })
            # 3. 普通消息
            else:
                formatted.append(self._format_content(msg))

        return formatted
```
        # 1. 标准化消息，检测格式化器类型
        # 2. 处理 thinking blocks
        # 3. 处理视频占位符
        # 4. 转换消息格式
```

---

## 6. 本地模型管理 (local_models)

### 6.1 核心组件

**源码路径**: `src/qwenpaw/local_models/`

```
local_models/
├── manager.py           # LocalModelManager facade (line 41)
├── llamacpp.py         # LlamaCppBackend server 管理 (line 43)
├── model_manager.py    # ModelManager 下载管理 (line 77)
├── download_manager.py # ProcessDownloadController (line 253)
└── tag_parser.py       # 标签解析
```

### 6.2 LocalModelManager 单例

```python
class LocalModelManager:
    """本地模型管理器Facade"""
    def get_instance() -> "LocalModelManager": ...      # line 237
    def get_config() -> LocalModelConfig: ...            # line 109
    def set_max_context_length(n: int): ...             # line 126
    def set_port(p: int): ...                          # line 134
    def start_llamacpp_download(): ...                  # line 147
    def setup_server(model_id: str) -> StartServerResponse: ...  # line 215
    def shutdown_server(): ...                          # line 232
```

### 6.3 Llama.cpp Server 生命周期

**启动流程** `setup_server()` (line 181-236):
```
1. 检查 llama-server 可执行文件存在
2. 验证模型路径有效
3. 解析 GGUF 模型文件和可选 mmproj 文件
4. 若相同模型已在运行 → 直接返回
5. 若不同模型运行 → 先 shutdown_server()
6. 解析端口 (自动选择空闲端口)
7. 创建子进程: llama-server --host 127.0.0.1 --port <port> --model <path>
8. 启动异步日志排出任务
9. 轮询 /health 端点等待就绪 (最多120s)
```

**命令构建** `_create_server_process()` (line 296-339):
```bash
llama-server --host 127.0.0.1 --port <port> --model <path> \
  --alias <name> --log-file <log_dir/llama-server.log> \
  --gpu-layers auto [--ctx-size <n>] [--mmproj <path>]
```

### 6.4 模型下载管理

**下载源**:
```python
class DownloadSource(str, Enum):
    HUGGINGFACE = "huggingface"   # HF Hub
    MODELSCOPE = "modelscope"      # ModelScope CN
    AUTO = "auto"                  # 先HF后MS
```

**推荐模型** (按内存):
| 内存 | 推荐模型 |
|------|----------|
| ≤8GB | QwenPaw-Flash-2B (Q4_K_M 或 Q8_0) |
| ≤16GB | QwenPaw-Flash-4B |
| >16GB | QwenPaw-Flash-9B |

### 6.5 API 端点

**`routers/local_models.py`**:

| 端点 | 功能 |
|------|------|
| `GET /local-models/server` | 检查服务器状态 |
| `POST /local-models/server` | 启动 llama.cpp server |
| `DELETE /local-models/server` | 停止 server |
| `POST /local-models/models/download` | 开始模型下载 |
| `GET /local-models/models/download` | 下载进度 |

---

## 7. 应用场景

### 7.1 云端 API 模型使用

适用于需要高性能、强算力的场景：
- **优势**: 无需本地硬件配置，随时切换不同模型
- **场景**: 复杂推理、长文本生成、多轮对话
- **推荐**: GPT-4o、Claude 3.5 Sonnet、Qwen3-max

### 7.2 本地模型使用

适用于隐私敏感或需要离线使用的场景：
- **优势**: 数据不离开本地，支持离线使用，成本为零
- **场景**: 隐私文档处理、内网环境、频繁调用
- **推荐**: Ollama + Llama 3.2、Qwen2.5

### 7.3 多模型协作

适用于需要不同模型互补的场景：
- **架构**: 主模型负责对话 + 专业模型处理特定任务
- **场景**: 代码生成用 Claude、翻译用 DeepSeek、对话用 GPT-4o
- **实现**: 通过 `delegate_external_agent` 委托任务

---

## 8. 模型选择指南

| 需求 | 推荐模型 |
|------|----------|
| 通用对话 | GPT-4o, Claude 3.5 Sonnet, Qwen3-max |
| 编程辅助 | Claude 3.7 Sonnet, GPT-4.1, Qwen2.5-Coder |
| 长上下文 | Gemini 1.5 Pro, Claude 3.5 Sonnet, DeepSeek-R1 |
| 本地部署 | Llama 3.2, Qwen2.5, Mistral |
| 多模态 | GPT-4o, Gemini 2.0, Claude 3.5 Sonnet |
| 成本敏感 | GPT-4o-mini, Gemini 2.0 Flash, DeepSeek-V3 |

---

## 9. 常见问题

### 9.1 模型连接失败

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| API Key 错误 | Key 无效或过期 | 在控制台重新设置 API Key |
| 限流触发 | 请求频率超出限制 | 启用 RetryChatModel 或降低并发 |
| 网络问题 | 防火墙/代理阻止 | 检查网络设置或配置代理 |

### 9.2 本地模型问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| llama.cpp 启动失败 | 未下载或路径错误 | 使用 Web 界面下载 Llama.cpp 或参考 [43-本地模型管理系统](./43-本地模型管理系统.md) |
| 模型加载慢 | GPU 内存不足 | 减少 gpu-layers 或使用量化模型 |
| 端口被占用 | 已有进程占用端口 | 修改端口或关闭占用进程 |

### 9.3 Token 使用问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| Token 记录不准确 | 模型不支持 usage 返回 | 依赖估算值而非精确值 |
| 上下文溢出 | 对话历史过长 | 启用 MemoryCompactionHook 自动压缩 |

---

## 10. 最佳实践

### 10.1 安全建议

1. **API Key 保护**: 使用加密存储，避免明文写在配置中
2. **最小权限**: 仅启用需要的模型，禁用不使用的提供商
3. **定期轮换**: 定期更换 API Key 并更新配置
4. **监控使用**: 启用 TokenRecordingModelWrapper 监控使用量

### 10.2 性能优化

| 场景 | 优化方案 |
|------|----------|
| 高并发 | 调整 LLM_MAX_CONCURRENT 和 LLM_MAX_QPM |
| 成本控制 | 使用 GPT-4o-mini 等低成本模型处理简单任务 |
| 响应速度 | 本地模型处理简单请求，云端模型处理复杂推理 |
| 缓存结果 | 启用 embedding cache 避免重复计算 |

### 10.3 可靠性保障

1. **配置重试**: 始终启用 RetryChatModel 处理临时性故障
2. **多模型备份**: 配置多个 provider，当主模型不可用时自动切换
3. **健康检查**: 使用 `qwenpaw doctor` 定期检查模型状态

---

## 11. 总结

### 核心要点

1. **ProviderManager 单例**: 统一管理 20+ 内置提供商和自定义提供商
2. **三层包装器**: OpenAIChatModelCompat → TokenRecordingModelWrapper → RetryChatModel
3. **并发控制**: 信号量 + 指数退避 + 随机抖动
4. **本地模型**: 内置 llama.cpp 支持，支持 HuggingFace/ModelScope 下载
5. **API Key 安全**: Fernet 对称加密 + OS Keychain 存储

### 关键配置

| 配置项 | 位置 | 说明 |
|--------|------|------|
| `~/.qwenpaw/config.json` | providers | 提供商配置 |
| `~/.qwenpaw/.secret/` | master_key | 加密密钥 |
| 环境变量 | QWENPAW_LLM_* | 运行时限制 |

### 故障排查流程

```
模型无法连接
    │
    ├─► 检查 API Key: qwenpaw doctor
    │
    ├─► 检查网络: curl <provider_url>/models
    │
    └─► 检查限流: 查看日志中的 RateLimitError
```

---

## 参考资料

- 源码路径：`src/qwenpaw/providers/`
- Provider 基类：`src/qwenpaw/providers/provider.py`
- 管理器：`src/qwenpaw/providers/provider_manager.py`
- 配置模型：`src/qwenpaw/config/config.py`
- 本地模型：`src/qwenpaw/local_models/`

---

## 如果你来自 Java...

### LLM Provider 概念对照

| QwenPaw | Java (Spring AI / LangChain4j) | 说明 |
|---------|-------------------------------|------|
| `ProviderManager` | `ModelController` | 全局模型控制器 |
| `Provider` | `AiModel` / `ChatModel` | 模型接口 |
| `OpenAIProvider` | `OpenAiAiModel` | 具体模型实现 |
| `ModelSlotConfig` | `ChatModelOptions` | 模型配置选项 |
| `ModelInfo` | `Model` | 模型元信息 |
| `api_key` 加密 | `EncryptedProperty` | 敏感信息加密 |

### Provider 实现对比

**Java (Spring AI)：**
```java
@Configuration
public class OpenAiConfig {
    @Bean
    public ChatModel openAiChatModel(
            @Value("${openai.api-key}") String apiKey) {
        return OpenAiChatModel.builder()
                .apiKey(apiKey)
                .model("gpt-4o")
                .temperature(0.7)
                .build();
    }
}
```

**QwenPaw (Python)：**
```python
# config.json
{
    "providers": {
        "openai": {
            "enabled": true,
            "api_key": "encrypted:xxxxx",
            "models": [{"model": "gpt-4o", "enabled": true}]
        }
    }
}

# 使用
provider = ProviderManager.get_instance().get_provider("openai")
model = provider.chat(model="gpt-4o")
```

### 模型工厂对比

**Java (工厂模式)：**
```java
public interface AiModelFactory {
    AiModel create(ModelConfig config);
}

@Service
public class OpenAiModelFactory implements AiModelFactory {
    @Override
    public AiModel create(ModelConfig config) {
        return OpenAiChatModel.builder()
                .apiKey(config.getApiKey())
                .model(config.getModelName())
                .build();
    }
}
```

**QwenPaw (工厂模式)：**
```python
# model_factory.py
def create_model_and_formatter(
    provider_id: str,
    model: str,
    api_key: str | None = None,
    **kwargs,
) -> tuple[ChatModelBase, OutputFormatter]:
    """工厂方法创建模型和格式化器"""
    provider = ProviderManager.get_instance().get_provider(provider_id)
    inner_model = provider.chat(model=model, api_key=api_key, **kwargs)
    wrapped = RetryChatModel(inner_model)
    formatter = OutputFormatter(model_name=model)
    return wrapped, formatter
```

### 重试机制对比

**Java (Resilience4j)：**
```java
@CircuitBreaker(name = "llm", fallbackMethod = "fallback")
@Retry(name = "llm")
public String chat(String prompt) {
    return chatModel.call(prompt);
}

public String fallback(String prompt, Exception e) {
    return "模型暂时不可用，请稍后重试";
}
```

**QwenPaw (指数退避)：**
```python
# RetryChatModel 内部实现
async def _compute_backoff(attempt: int) -> float:
    wait = self._retry_config.backoff_base * (2 ** attempt)
    return min(wait, self._retry_config.backoff_cap)

# 调用
wrapped_model = RetryChatModel(inner_model)
response = await wrapped_model.chat(messages)
```

### 速率限制对比

**Java (Bucket4j)：**
```java
@Bean
public FilterRegistrationBean<RateLimitFilter> rateLimitFilter() {
    Bucket bucket = Bucket.builder()
            .addLimit(Bandwidth.classic(600, Refill.intervals(1, MINUTES)))
            .build();
    return new FilterRegistrationBean<>(new RateLimitFilter(bucket));
}
```

**QwenPaw (信号量 + 定时器)：**
```python
# rate_limiter.py
class LLMRateLimiter:
    def __init__(self, max_concurrent: int = 10, max_qpm: int = 600):
        self._semaphore = asyncio.Semaphore(max_concurrent)
        self._qpm_limiter = QPMLimiter(max_qpm)

    async def acquire(self):
        await self._semaphore.acquire()
        await self._qpm_limiter.acquire()
```

### 并发控制对比

**Java (CompletableFuture + ExecutorService)：**
```java
@Bean(name = "llmExecutor")
public ExecutorService llmExecutor() {
    return Executors.newFixedThreadPool(10);
}

public CompletableFuture<String> chatAsync(String prompt) {
    return CompletableFuture.supplyAsync(
        () -> chatModel.call(prompt),
        llmExecutor
    );
}
```

**QwenPaw (asyncio)：**
```python
# 内置并发控制
LLM_MAX_CONCURRENT = 10  # 最大并发

async def chat_async(messages):
    async with semaphore:  # 信号量控制
        return await model.chat(messages)

# 流式响应的槽位管理
async for chunk in stream:
    if first_chunk:
        limiter.release()  # 首个 chunk 后释放槽位
```

### API Key 安全对比

**Java (Jasypt)：**
```java
@Bean
public StringEncryptor stringEncryptor() {
    PooledPBEStringEncryptor encryptor = new PooledPBEStringEncryptor();
    encryptor.setPoolSize(2);
    encryptor.setPassword("my-secret-key");
    encryptor.setAlgorithm("PBEWithMD5AndDES");
    return encryptor;
}

// 配置
spring.datasource.password=ENC(encodedPassword)
```

**QwenPaw (Fernet)：**
```python
from cryptography.fernet import Fernet

# 加密
master_key = Fernet.generate_key()
f = Fernet(master_key)
encrypted = f.encrypt(b"api-key-value")

# 解密
config["api_key"] = f.decrypt(encrypted)
```

### 本地模型部署对比

**Java (Ollama Java Client)：**
```java
OllamaApiClient client = OllamaClient.builder()
        .baseUrl("http://localhost:11434")
        .build();

ChatRequest request = ChatRequest.builder()
        .model("llama3.2")
        .message(Message.user("Hello"))
        .build();

ChatResponse response = client.chat(request);
```

**QwenPaw：**
```python
# 配置 Ollama provider
{
    "providers": {
        "ollama": {
            "enabled": true,
            "base_url": "http://localhost:11434",
            "models": []
        }
    }
}

# 自动发现模型
qwenpaw models list --provider ollama

# 使用
/model ollama/llama3.2
```

### 关键设计差异

| 方面 | Java (Spring AI) | QwenPaw |
|------|-----------------|---------|
| 架构风格 | 强类型 + 依赖注入 | 动态类型 + 单例模式 |
| 配置方式 | `@Configuration` + YAML | JSON + 环境变量 |
| 并发模型 | 线程池 + CompletableFuture | asyncio + async/await |
| 重试策略 | Resilience4j 注解 | 装饰器模式 (RetryChatModel) |
| 速率限制 | Bucket4j | 自实现信号量 + QPM |
| API 兼容 | OpenAI 格式 | OpenAI 兼容 + 原始 API |

---

## 练习题

### 基础练习

1. **Provider 列表**：运行 `qwenpaw models list` 查看所有可用模型
2. **配置查看**：查看 `~/.qwenpaw/config.json` 中的 providers 配置
3. **模型切换**：使用 `/model gpt-4o-mini` 在对话中切换模型

### 进阶练习

4. **API Key 配置**：为 OpenAI provider 配置 API Key，观察加密存储
5. **本地模型**：安装 Ollama 并配置 QwenPaw 连接本地模型
6. **能力探测**：阅读 `multimodal_prober.py` 理解多模态检测机制

### 高级练习

7. **Provider 扩展**：创建一个自定义 Provider，连接不支持的 LLM 服务
8. **重试机制分析**：阅读 `retry_chat_model.py`，绘制重试流程图
9. **速率限制调优**：分析 `rate_limiter.py`，设计一个自适应限流策略

### 参考答案

<details>
<summary>点击展开答案</summary>

**练习 1：**
```bash
qwenpaw models list
# 或
qwenpaw providers list
```

**练习 2：**
```bash
cat ~/.qwenpaw/config.json | jq '.providers'
```

**练习 3：**
```
/model gpt-4o-mini
```

**练习 4：**
```bash
qwenpaw providers configure openai
# 输入 API Key
# 查看 config.json 中变为 encrypted:xxxxx
```

**练习 5：**
```bash
# 安装 Ollama
brew install ollama
ollama serve
ollama pull llama3.2

# QwenPaw 配置
qwenpaw providers configure ollama
```

**练习 6：**
`MultimodalProber` 检测模型是否支持图像输入，通过发送测试请求判断。

**练习 7：**
参考 `openai_provider.py` 实现 `CustomProvider`，覆盖 `chat()` 和 `fetch_models()` 方法。

**练习 8：**
```
调用 chat()
    │
    ├─► 检查信号量槽位
    │
    ├─► 检查 QPM 限制
    │
    ├─► 首次失败 → 等待 backoff_base
    │
    ├─► 重试 → 2x backoff
    │
    └─► 达到 max_retries → 抛出异常
```

**练习 9：**
可基于令牌使用量动态调整 QPM，或使用滑动窗口算法实现更精确的限流。

</details>

---

## 实战演练

### 基础练习（⭐）
**目标**: 使用 CLI 命令列出当前可用的 Provider 和模型
**提示**: 运行 `qwenpaw models list` 查看已配置的提供商和启用的模型
**参考思路**: 该命令调用 `ProviderManager.get_instance().get_all_providers()` 返回所有已注册提供商，然后遍历每个提供商的 models 列表输出

### 进阶练习（⭐⭐⭐）
**目标**: 追踪从用户选择模型到 ChatModel 实例创建的完整流程
**提示**: 从 `create_model_and_formatter()` 工厂方法出发，跟踪 Provider 获取 → 模型实例创建 → 双重包装的完整链路
**参考思路**: 工厂方法解析 agent_id → 加载 AgentProfileConfig → 获取 active_model 配置 → `ProviderManager.get_provider()` → `provider.get_chat_model_instance()` → 包装为 `TokenRecordingModelWrapper` → 再包装为 `RetryChatModel`

### 挑战练习（⭐⭐⭐⭐⭐）
**目标**: 分析 ProviderManager 的单例模式实现，讨论其在多线程/多进程环境下的安全性
**提示**: 查看 `_instance` 类变量和 `get_instance()` 静态方法，思考 asyncio 并发下的线程安全问题
**参考思路**: 当前实现使用简单的 `if _instance is None` 检查，在 asyncio 单线程模型下是安全的；但在多线程环境（如多 worker）下存在竞态条件，可通过 `threading.Lock` 或 `__new__` 方法保证线程安全；多进程场景下每个进程有独立的 `_instance`，需通过共享存储保持配置一致

## 知识检查

1. **ProviderManager 查找顺序**：当调用 `get_provider("openai")` 时，ProviderManager 按什么顺序查找提供商实例？如果同一个 ID 同时出现在 plugin_providers 和 builtin_providers 中，会返回哪个？

2. **RetryChatModel 流式槽位管理**：在流式响应中，信号量槽位为什么在首个 chunk 到达后就释放，而不是等整个流结束后再释放？如果流在首个 chunk 之前就失败了，槽位如何处理？

3. **模型包装管道**：`create_model_and_formatter()` 对原始模型做了哪两层包装？每层包装各自的职责是什么？为什么 RetryChatModel 是最外层而不是最内层？

---

## 延伸阅读

- [82-Provider系统深度解析](./82-Provider系统深度解析.md) -- Provider 抽象层的完整设计、自定义 Provider 扩展指南
- [85-模型探测与能力检测](./85-模型探测与能力检测.md) -- 多模态能力探测、模型特性自动检测机制
- [07-智能体核心架构](./07-智能体核心架构.md) -- 智能体如何调用模型系统、Agent 与 Provider 的协作关系
