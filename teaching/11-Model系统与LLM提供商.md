# Model 系统与 LLM 提供商

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
├── model_factory.py      # create_model_and_formatter - 模型工厂
├── model_wrapper.py       # TokenRecordingModelWrapper - Token记录包装器
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
| `llama.cpp` | LlamaCppProvider | 否 | 无需额外服务，内置下载 |

### 2.3 阿里云编程计划提供商

| 提供商 ID | 类名 | Base URL | 特点 |
|-----------|------|----------|------|
| `aliyun-codingplan` | OpenAIProvider | `https://coding.dashscope.aliyuncs.com/v1` | 中国区 |
| `aliyun-codingplan-intl` | OpenAIProvider | `https://coding-intl.dashscope.aliyuncs.com/v1` | 国际区 |
| `zhipu-cn-codingplan` | OpenAIProvider | `https://open.bigmodel.cn/api/coding/paas/v4` | 智谱编程计划 |
| `zhipu-intl-codingplan` | OpenAIProvider | `https://api.z.ai/api/coding/paas/v4` | 智谱国际编程计划 |

### 2.3 支持的模型列表

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
qwenpaw models set --agent default --provider openai --model gpt-4o

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

### 5.3 重试流程

```python
async def chat_with_retry(self, messages, **kwargs):
    async with self._semaphore:  # 限流信号量
        for attempt in range(max_retries):
            try:
                return await self._model.chat(messages, **kwargs)
            except RateLimitError:
                if attempt == max_retries - 1:
                    raise
                # 指数退避 + 随机抖动
                delay = min(backoff_base * (2 ** attempt), backoff_cap)
                delay += random.uniform(0, jitter_range)
                await asyncio.sleep(delay)
```

### 5.4 模型工厂与包装器管道

**源码路径**: `src/qwenpaw/providers/model_factory.py`

`create_model_and_formatter()` (line 930) 创建模型和格式化器：

```python
def create_model_and_formatter(
    agent_id: Optional[str] = None,
) -> Tuple[ChatModelBase, FormatterBase]:
    # 1. 解析 agent_id (参数 > context > None)
    # 2. 加载代理配置 (RetryConfig, RateLimitConfig)
    # 3. 获取 provider 和 model
    provider = ProviderManager.get_instance().get_provider(provider_id)
    model = provider.get_chat_model_instance(model_id)
    # 4. 创建格式化器
    formatter = _create_formatter_instance(model.__class__)
    # 5. 双重包装模型
    wrapped_model = TokenRecordingModelWrapper(provider_id, model)
    wrapped_model = RetryChatModel(
        wrapped_model,
        retry_config=retry_config,
        rate_limit_config=rate_limit_config,
    )
    return wrapped_model, formatter
```

**包装器管道架构**:

```
ProviderManager.get_active_chat_model()
         │
         ▼
   ┌─────────────────────┐
   │ OpenAIChatModelCompat│
   │ (或 Anthropic/Gemini)│
   └─────────────────────┘
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
    async def _record_usage(self, usage: ChatUsage | None) -> None:
        # 记录 prompt_tokens, completion_tokens, total_tokens

    @classmethod
    def pop_usage_for_session(cls, session_id: str) -> dict[str, Any] | None:
        # 获取会话的 token 使用记录
```

**重试可错误**: `{429, 500, 502, 503, 504, 529}` + OpenAI/Anthropic SDK 可重试异常

**流式安全**: 信号量槽位在首个 chunk 到达后释放 (非完整流结束后)，防止其他调用者饥饿

### 5.5 FileBlockSupportFormatter 与思考块

**源码路径**: `model_factory.py` line 695-913

`FileBlockSupportFormatter` 处理 thinking blocks 和视频占位符：

```python
class FileBlockSupportFormatter(base_formatter_class):
    async def _format(self, msgs) -> list[dict]:
        # 1. 标准化消息，检测格式化器类型
        # 2. 提取 thinking blocks 到 reasoning_contents dict
        # 3. Anthropic: 使用 _format_anthropic_messages() 原生传递
        # 4. OpenAI/Gemini: 提取 reasoning_content 并注入 assistant 消息
```

**Thinking block 处理流程** (非 Anthropic 模型):

```
1. 从 assistant 消息提取 thinking blocks
         │
         ▼
2. 预测哪些 assistant 消息会存活 (过滤 thinking-only 消息)
         │
         ▼
3. 对齐 reasoning_contents 与存活的 assistant 消息
         │
         ▼
4. 注入 reasoning_content 字段
```

### 5.6 消息归一化管道

**源码路径**: `agents/utils/message_request_normalizer.py` line 131

`normalize_messages_for_model_request()` 在发送前标准化消息：

```python
def normalize_messages_for_model_request(
    msgs: list[Msg],
    *,
    supports_multimodal: bool,
    target_family: str = "openai",
) -> list[Msg]:
```

**标准化流程**:

```
1. _clone_messages() - 深拷贝所有消息，避免修改存储历史
         │
         ▼
2. _sanitize_tool_messages() - 修复/移除无效 tool blocks
         │
         ├─► _repair_empty_tool_inputs() - 修复空的 input={}
         ├─► _remove_invalid_tool_blocks() - 移除无效 id/name
         ├─► _dedup_tool_blocks() - 去重相同 ID 的 tool_use
         └─► _remove_unpaired_tool_messages() - 移除孤立 tool 结果
         │
         ▼
3. _clean_provider_specific_fields() - 清除提供商特定字段
         │
         ├─► 剥离 extra_content (Gemini thought_signature)
         └─► 剥离 raw_input (AgentScope 流解析产物)
         │
         ▼
4. _strip_media_blocks_in_place() - 如果不支持多模态
         └─► 移除 image/audio/video blocks
         └─► 替换为空内容占位符
```

**完整消息流程** (用户输入 → LLM 格式化消息):

```
用户输入
    │
    ▼
process_file_and_media_blocks_in_message() - 下载文件/媒体
    │
    ▼
QwenPawAgent.reply() - 工具调用拦截
    │
    ▼
normalize_messages_for_model_request() - 消息归一化
    │
    ▼
FileBlockSupportFormatter._format() - 格式化
    │
    ├─► Anthropic: _format_anthropic_messages() 原生处理
    └─► OpenAI/Gemini: thinking/video 块注入
    │
    ▼
Provider API 请求
```

**Provider Target Families**:

| Target | 处理方式 |
|--------|---------|
| `openai` | 默认，剥离所有提供商特定字段 |
| `anthropic` | 使用 _format_anthropic_messages() 原生 thinking/image/video |
| `gemini` | 保留 extra_content (Gemini thought_signature) |

**视频占位符处理** (OpenAI/Gemini):

```
_substitute_video_blocks() → base formatter → _replace_video_placeholders()
     替换视频为 __QWENPAW_VID_{id}__        还原视频块
```

---

## 6. 模型能力探测

### 6.1 多模态能力检测

```python
async def probe_model_multimodal(
    provider_id: str,
    model_id: str,
    image_only: bool = False,
) -> dict:
    """探测模型是否支持多模态"""
    model_info = get_model_info(provider_id, model_id)
    
    # 方法1: 从已知模型列表查询
    if model_info.probe_source == "documentation":
        return {
            "supports_vision": model_info.supports_image,
            "supports_video": model_info.supports_video,
        }
    
    # 方法2: 实际调用探测
    result = await multimodal_prober.probe(
        model=model,
        test_image=True,
        test_video=False,
    )
    return result
```

### 6.2 内置能力基线

```python
# capability_baseline.py
CAPABILITY_BASELINE = {
    # GPT-4o 系列 - 全能型
    "gpt-4o": {"vision": True, "video": False, "audio": False},
    
    # Claude 3.5 Sonnet - 强推理
    "claude-3-5-sonnet-20241022": {"vision": True, "video": False, "audio": False},
    
    # Gemini 2.0 - 多模态领先
    "gemini-2.0-flash": {"vision": True, "video": True, "audio": False},
}
```

---

## 7. 本地模型配置

### 7.1 Ollama 配置

```bash
# 1. 安装 Ollama
# macOS/Linux: brew install ollama
# Windows: 下载安装包

# 2. 启动 Ollama 服务
ollama serve

# 3. 拉取模型
ollama pull llama3.2
ollama pull qwen2.5

# 4. 测试
curl http://localhost:11434/api/tags
```

**QwenPaw 配置**：
```json
{
  "providers": {
    "ollama": {
      "enabled": true,
      "base_url": "http://localhost:11434/v1",
      "models": []
    }
  }
}
```

### 7.2 LM Studio 配置

```bash
# 1. 下载 LM Studio
# https://lmstudio.ai/

# 2. 启动 LM Studio
# - 选择模型
# - 启动本地服务器（默认端口 1234）

# 3. 配置 QwenPaw
```

```json
{
  "providers": {
    "lmstudio": {
      "enabled": true,
      "base_url": "http://localhost:1234/v1",
      "models": []
    }
  }
}
```

### 7.3 llama.cpp 内置下载

QwenPaw 内置 llama.cpp 支持，无需单独安装：

1. 在 Web 界面中点击 `Download Llama.cpp`
2. 选择模型并下载
3. 自动配置并启用

---

## 8. OpenRouter 聚合

OpenRouter 聚合多个模型提供商的访问：

```json
{
  "providers": {
    "openrouter": {
      "enabled": true,
      "api_key": "sk-or-v1-xxxxx",
      "base_url": "https://openrouter.ai/api/v1",
      "models": []
    }
  }
}
```

**优点**：
- 统一接口访问多个模型
- 内置积分管理
- 自动路由最优模型

**缺点**：
- 额外的网络跳转
- 可能的延迟增加

---

## 9. 自定义 Provider

### 9.1 实现自定义 Provider

```python
from qwenpaw.providers.provider import Provider, ModelInfo

class MyCustomProvider(Provider):
    """自定义 Provider 示例"""
    
    provider_id = "my-provider"
    provider_name = "My Custom Provider"
    
    def __init__(self, config: ProviderConfig):
        super().__init__(config)
        self._client = self._create_client()
    
    def _create_client(self):
        # 创建 API 客户端
        pass
    
    def get_chat_model_instance(self, model_name: str) -> ChatModelBase:
        # 返回模型实例
        return MyCustomChatModel(
            api_key=self.config.api_key,
            base_url=self.config.base_url,
            model=model_name,
        )
    
    async def list_models(self) -> List[ModelInfo]:
        # 实现模型发现
        return [
            ModelInfo(id="my-model-1", name="My Model 1", supports_image=False),
        ]
```

### 9.2 注册自定义 Provider

```python
from qwenpaw.providers.provider_manager import ProviderManager

# 方式1: 通过配置
# 在 config.json 中添加 provider 配置

# 方式2: 代码注册
manager = ProviderManager.get_instance()
manager.register_provider(MyCustomProvider(custom_config))
```

---

## 10. 故障排查

### 10.1 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `ProviderError: API key missing` | 未配置 API Key | 在控制台配置 API Key |
| `RateLimitError: 429` | 请求超限 | 等待后重试，或降低 QPM |
| `AuthenticationError: 401` | API Key 无效 | 检查 API Key 是否正确 |
| `ModelNotFoundError` | 模型不存在 | 检查模型名称是否正确 |
| `ConnectionError` | 网络问题 | 检查网络连接和代理设置 |

### 10.2 调试技巧

```python
import logging

# 启用调试日志
logging.getLogger("qwenpaw.providers").setLevel(logging.DEBUG)
logging.getLogger("qwenpaw.providers.provider_manager").setLevel(logging.DEBUG)
```

### 10.3 诊断命令

```bash
# 检查提供商状态
qwenpaw doctor --check models

# 测试模型连接
qwenpaw models test --provider openai --model gpt-4o

# 查看详细配置
qwenpaw models list --verbose
```

---

## 11. 最佳实践

### 11.1 API Key 安全

1. **使用环境变量**而非硬编码
2. **启用 OS Keychain**存储（系统偏好设置）
3. **定期轮换**API Key
4. **最小权限**原则 - 只授权需要的模型

### 11.2 性能优化

| 场景 | 建议 |
|------|------|
| 高并发 | 启用 RetryChatModel，设置合适的 max_concurrent |
| 低延迟 | 使用本地模型（Ollama/LM Studio） |
| 成本控制 | 设置模型使用配额，监控用量 |
| 可靠性 | 配置多个 Provider 作为备份 |

### 11.2.1 OpenAIChatModelCompat 流式兼容 (openai_chat_model_compat.py)

**源码路径**: `src/qwenpaw/providers/openai_chat_model_compat.py`

**问题背景**: 不同模型在流式输出中会产生格式不一致的工具调用块

**核心类**: `_SanitizedStream` (line 138-188) - 流式响应代理包装器

**流式处理流程** `_parse_openai_stream_response()` (line 196-312):
```
1. _SanitizedStream 包装流
2. _capture_extra_content() 捕获 tool_call chunk 中的 extra_content
3. _sanitize_stream_item() 修复/丢弃格式错误的 tool_call
4. 如无结构化 tool_use 块 → 从 <tool_call> 标签提取
5. 合并到 parsed.content
```

**extra_content 捕获** (line 170-188):
```python
# 从 Gemini thought_signature 提取 extra_content
for tc in delta.tool_calls:
    extra = tc.extra_content or tc.model_extra.get("extra_content")
    self.extra_contents[tc_id] = extra
```

**工具调用标签解析** `tag_parser.py:parse_tool_calls_from_text()` (line 313):
- 解析 `<tool_call>...</tool_call>` XML 块
- 支持 JSON / 严格 XML / 无闭合标签宽松格式
- 提取 text_before / tool_calls / has_open_tag

**thinking 块处理** (line 240-266):
```python
# 从 <think>...</think> 文本中提取 <tool_call> 标签
# 转换为合成 tool_use 块, ID 如 "think_call_{i}"
```

**集成点**: OpenAI/Ollama/OpenRouter Provider 的 `get_chat_model_instance()` 均返回 `OpenAIChatModelCompat(stream=True)`

---

### 11.2.2 本地模型管理 (local_models)
**源码路径**: `src/qwenpaw/local_models/`

```
local_models/
├── manager.py           # LocalModelManager facade (line 41)
├── llamacpp.py         # LlamaCppBackend server 管理 (line 43)
├── model_manager.py    # ModelManager 下载管理 (line 77)
├── download_manager.py # ProcessDownloadController (line 253)
└── tag_parser.py       # 标签解析
```

#### LocalModelManager 单例 (manager.py:41-243)

```python
class LocalModelManager:
    """本地模型管理器Facade"""
    def get_instance() -> "LocalModelManager": ...      # line 237
    def get_config() -> LocalModelConfig: ...            # line 118
    def set_max_context_length(n: int): ...             # line 126
    def set_port(p: int): ...                          # line 134
    def start_llamacpp_download(): ...                  # line 147
    def setup_server(model_id: str) -> StartServerResponse: ...  # line 215
    def shutdown_server(): ...                          # line 232
```

**LocalModelConfig** (manager.py:23-38):
```python
class LocalModelConfig(BaseModel):
    max_context_length: int = Field(default=65536, ge=32768)
    port: int | None = Field(default=None, ge=1, le=65535)
```

#### Llama.cpp Server 生命周期 (llamacpp.py)

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

**关闭流程** `shutdown_server()` (line 279-289):
```python
# 使用 _server_shutdown_context() 上下文管理器
# 优雅关闭 5s → 强制 kill 3s
```

#### ModelManager 下载管理 (model_manager.py:77-470)

**下载源**:
```python
class DownloadSource(str, Enum):
    HUGGINGFACE = "huggingface"   # HF Hub
    MODELSCOPE = "modelscope"      # ModelScope CN
    AUTO = "auto"                  # 先HF后MS
```

**下载流程** `start_download()` (line 186-242):
```
1. 验证无活跃下载
2. 解析下载源 (HuggingFace/ModelScope)
3. 估算下载大小
4. 验证远程有 GGUF 文件
5. 创建 ProcessDownloadTaskSpec (暂存目录)
6. 委托 ProcessDownloadController.start()
```

**推荐模型** (按内存):
| 内存 | 推荐模型 |
|------|----------|
| ≤8GB | QwenPaw-Flash-2B (Q4_K_M 或 Q8_0) |
| ≤16GB | QwenPaw-Flash-4B |
| >16GB | QwenPaw-Flash-9B |

#### ProcessDownloadController (download_manager.py:253-421)

```python
class ProcessDownloadController:
    """后台进程下载控制器"""
    def start(): ...     # 启动下载线程
    def cancel(): ...    # 优雅/kill 关闭下载进程
    def get_progress() -> DownloadProgress: ...
```

#### ProviderManager 集成 (provider_manager.py)

**本地模型恢复** `_resume_local_model()` (line 1578-1630):
```
1. 获取 qwenpaw-local provider 的上次活跃模型
2. 检查 llama.cpp 安装
3. 检查模型已下载
4. 调用 local_manager.setup_server(model_id)
5. 更新 provider: base_url = http://127.0.0.1:<port>/v1
```

**API 端点** (`routers/local_models.py`):
| 端点 | 功能 |
|------|------|
| `GET /local-models/server` | 检查服务器状态 |
| `POST /local-models/server` | 启动 llama.cpp server |
| `DELETE /local-models/server` | 停止 server |
| `POST /local-models/models/download` | 开始模型下载 |
| `GET /local-models/models/download` | 下载进度 |

---

### 11.3 模型选择指南

| 需求 | 推荐模型 |
|------|----------|
| 通用对话 | GPT-4o, Claude 3.5 Sonnet, Qwen3-max |
| 编程辅助 | Claude 3.7 Sonnet, GPT-4.1, Qwen2.5-Coder |
| 长上下文 | Gemini 1.5 Pro, Claude 3.5 Sonnet, DeepSeek-R1 |
| 本地部署 | Llama 3.2, Qwen2.5, Mistral |
| 多模态 | GPT-4o, Gemini 2.0, Claude 3.5 Sonnet |
| 成本敏感 | GPT-4o-mini, Gemini 2.0 Flash, DeepSeek-V3 |

---

## 12. 参考资料

- 源码路径：`src/qwenpaw/providers/`
- Provider 基类：`src/qwenpaw/providers/provider.py`
- 管理器：`src/qwenpaw/providers/provider_manager.py`
- 配置模型：`src/qwenpaw/config/config.py`
