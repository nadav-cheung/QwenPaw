# QwenPaw Providers System Research Report

## Table of Contents
1. [ProviderManager Architecture](#1-providermanager-architecture)
2. [Supported LLM Providers](#2-supported-llm-providers)
3. [BaseProvider Abstraction](#3-baseprovider-abstraction)
4. [Model Routing and Fallback Mechanisms](#4-model-routing-and-fallback-mechanisms)
5. [Key Data Structures](#5-key-data-structures)
6. [Persistence and Security](#6-persistence-and-security)

---

## 1. ProviderManager Architecture

### Overview
`ProviderManager` (`provider_manager.py`) is a **singleton** class that serves as the central hub for managing all LLM providers in QwenPaw. It provides a unified interface for:
- Listing available providers
- Adding/removing custom providers
- Fetching provider details
- Activating models
- Probing multimodal capabilities
- Persisting configuration to disk

### Singleton Pattern
```python
class ProviderManager:
    _instance = None

    @staticmethod
    def get_instance() -> "ProviderManager":
        if ProviderManager._instance is None:
            ProviderManager._instance = ProviderManager()
        return ProviderManager._instance
```

### Provider Storage Architecture
The `ProviderManager` maintains three separate provider dictionaries:

| Dictionary | Purpose | Storage Location |
|------------|---------|------------------|
| `builtin_providers` | Built-in providers (DashScope, OpenAI, etc.) | In-memory + encrypted JSON at `~/.config/qwenpaw/providers/builtin/` |
| `custom_providers` | User-created providers | In-memory + encrypted JSON at `~/.config/qwenpaw/providers/custom/` |
| `plugin_providers` | Third-party plugin providers | In-memory + encrypted JSON at `~/.config/qwenpaw/providers/plugin/` |

### Disk Storage Structure
```
~/.config/qwenpaw/providers/
├── builtin/           # Built-in provider configs (encrypted)
│   ├── dashscope.json
│   ├── openai.json
│   └── ...
├── custom/            # User-created provider configs (encrypted)
│   └── ...
├── plugin/            # Plugin provider configs (encrypted)
│   └── ...
├── active_model.json  # Currently active provider/model
└── provider.json      # Legacy format (migrated on startup)
```

### Initialization Flow
```
__init__()
  ├── _prepare_disk_storage()       # Create directory structure with 0o700 permissions
  ├── _init_builtins()             # Register all built-in providers
  ├── _migrate_legacy_providers()  # Migrate old providers.json format
  ├── _init_from_storage()         # Load saved configs (decrypt + restore)
  └── _apply_default_annotations() # Fill in capability info from baseline registry
```

### Key Public API Methods

| Method | Description |
|--------|-------------|
| `get_provider(provider_id)` | Return provider instance by ID (checks plugin > builtin > custom) |
| `get_provider_info(provider_id)` | Return serializable ProviderInfo for UI |
| `list_provider_info()` | List all providers (async, parallel) |
| `activate_model(provider_id, model_id)` | Set active model and trigger multimodal probing |
| `update_provider(provider_id, config)` | Update provider config (base_url, api_key, etc.) |
| `add_custom_provider(provider_data)` | Add new custom provider |
| `remove_custom_provider(provider_id)` | Delete custom provider |
| `fetch_provider_models(provider_id)` | Fetch models from provider API |
| `probe_model_multimodal(provider_id, model_id)` | Test image/video support |
| `get_active_chat_model()` | Get ChatModelBase instance for current model |

---

## 2. Supported LLM Providers

### Built-in Providers (22 total)

| Provider ID | Provider Name | ChatModel Class | Base URL | Notes |
|-------------|---------------|-----------------|----------|-------|
| `modelscope` | ModelScope | OpenAIChatModel | `https://api-inference.modelscope.cn/v1` | China |
| `dashscope` | DashScope | OpenAIChatModel | `https://dashscope.aliyuncs.com/compatible-mode/v1` | Alibaba |
| `aliyun-codingplan` | Aliyun Coding Plan (China) | OpenAIChatModel | `https://coding.dashscope.aliyuncs.com/v1` | |
| `aliyun-codingplan-intl` | Aliyun Coding Plan (Intl) | OpenAIChatModel | `https://coding-intl.dashscope.aliyuncs.com/v1` | |
| `zhipu-cn` | Zhipu (BigModel) | OpenAIChatModel | `https://open.bigmodel.cn/api/paas/v4` | China |
| `zhipu-cn-codingplan` | Zhipu Coding Plan (BigModel) | OpenAIChatModel | `https://open.bigmodel.cn/api/coding/paas/v4` | |
| `zhipu-intl` | Zhipu (Z.AI) | OpenAIChatModel | `https://api.z.ai/api/paas/v4` | International |
| `zhipu-intl-codingplan` | Zhipu Coding Plan (Z.AI) | OpenAIChatModel | `https://api.z.ai/api/coding/paas/v4` | |
| `openai` | OpenAI | OpenAIChatModel | `https://api.openai.com/v1` | |
| `opencode` | OpenCode | OpenAIChatModel | `https://opencode.ai/zen/v1` | Free models |
| `azure-openai` | Azure OpenAI | OpenAIChatModel | (configurable) | |
| `anthropic` | Anthropic | AnthropicChatModel | `https://api.anthropic.com` | |
| `gemini` | Google Gemini | GeminiChatModel | `https://generativelanguage.googleapis.com` | |
| `deepseek` | DeepSeek | OpenAIChatModel | `https://api.deepseek.com` | |
| `kimi-cn` | Kimi (China) | OpenAIChatModel | `https://api.moonshot.cn/v1` | |
| `kimi-intl` | Kimi (International) | OpenAIChatModel | `https://api.moonshot.ai/v1` | |
| `minimax` | MiniMax (International) | AnthropicChatModel | `https://api.minimax.io/anthropic` | |
| `minimax-cn` | MiniMax (China) | AnthropicChatModel | `https://api.minimaxi.com/anthropic` | |
| `ollama` | Ollama | OpenAIChatModel | `http://127.0.0.1:11434` | Local, supports discovery |
| `lmstudio` | LM Studio | OpenAIChatModel | `http://localhost:1234/v1` | Local, supports discovery |
| `openrouter` | OpenRouter | OpenAIChatModel | `https://openrouter.ai/api/v1` | Aggregator |
| `siliconflow-cn` | SiliconFlow (China) | OpenAIChatModel | `https://api.siliconflow.cn/v1` | |
| `siliconflow-intl` | SiliconFlow (Intl) | OpenAIChatModel | `https://api.siliconflow.com/v1` | |
| `qwenpaw-local` | QwenPaw Local | OpenAIChatModel | (dynamic) | Local model server |

### Provider Implementation Classes

```
Provider (ABC)
├── OpenAIProvider          # OpenAI-compatible APIs
│   ├── OllamaProvider      # Ollama-specific base URL handling
│   └── LMStudioProvider    # LM Studio-specific checks
├── AnthropicProvider       # Anthropic Claude API
├── GeminiProvider          # Google Gemini API
└── OpenRouterProvider      # OpenRouter with special headers + model filtering
```

### DashScope Special Headers
When using DashScope-compatible endpoints (`dashscope.aliyuncs.com` or `coding.dashscope.aliyuncs.com`), providers add special headers:

```python
# For standard DashScope
"x-dashscope-agentapp": json.dumps({
    "agentType": "QwenPaw",
    "deployType": "UnKnown",
    "moduleCode": "model",
    "agentCode": "UnKnown",
})

# For Coding Plan endpoint
"X-DashScope-Cdpl": json.dumps({...})
```

### OpenRouter Special Headers
OpenRouter requires specific HTTP headers for all requests:
```python
_DEFAULT_HEADERS = {
    "HTTP-Referer": "https://qwenpaw.agentscope.io/",
    "X-Title": "QwenPaw",
    "User-Agent": "QwenPaw/1.1",
}
```

---

## 3. BaseProvider Abstraction

### Class Hierarchy

```
ProviderInfo (Pydantic BaseModel)  # Data container
└── Provider (ABC)                 # Full provider with methods
    ├── check_connection()
    ├── fetch_models()
    ├── check_model_connection()
    ├── get_chat_model_instance()
    ├── add_model()
    ├── delete_model()
    ├── update_config()
    ├── get_effective_generate_kwargs()
    ├── update_model_config()
    ├── has_model()
    ├── probe_model_multimodal()
    └── get_info()
```

### Key Data Models

#### ModelInfo (Pydantic BaseModel)
```python
class ModelInfo(BaseModel):
    id: str                          # API model identifier (e.g., "gpt-4o")
    name: str                        # Human-readable name
    supports_multimodal: bool | None # None = not yet probed
    supports_image: bool | None
    supports_video: bool | None
    probe_source: str | None         # "documentation" or "probed"
    is_free: bool = False
    generate_kwargs: Dict[str, Any]  # Per-model overrides
```

#### ExtendedModelInfo (extends ModelInfo)
```python
class ExtendedModelInfo(ModelInfo):
    provider: str                     # Provider/series (e.g., "openai")
    input_modalities: List[str]      # ["text", "image", "video"]
    output_modalities: List[str]     # ["text"]
    pricing: Dict[str, str]          # {"prompt": "0.001", "completion": "0.002"}
```

#### ProviderInfo (Pydantic BaseModel)
```python
class ProviderInfo(BaseModel):
    id: str
    name: str
    base_url: str
    api_key: str
    chat_model: str                  # "OpenAIChatModel", "AnthropicChatModel", etc.
    models: List[ModelInfo]          # Pre-defined models
    extra_models: List[ModelInfo]    # User-added or discovered models
    api_key_prefix: str             # Expected prefix (e.g., "sk-")
    is_local: bool
    freeze_url: bool                # Prevent URL editing
    require_api_key: bool
    is_custom: bool
    support_model_discovery: bool    # Can fetch models from API
    support_connection_check: bool   # Can test connection without model
    generate_kwargs: Dict[str, Any]
    meta: Dict[str, Any]
```

### Abstract Methods (must implement)

| Method | Signature | Purpose |
|--------|-----------|---------|
| `check_connection` | `(timeout=5) -> tuple[bool, str]` | Test provider API reachability |
| `fetch_models` | `(timeout=5) -> List[ModelInfo]` | List available models from API |
| `check_model_connection` | `(model_id, timeout=5) -> tuple[bool, str]` | Test specific model usability |
| `get_chat_model_instance` | `(model_id) -> ChatModelBase` | Create AgentScope ChatModel instance |

### Default Implementations

| Method | Behavior |
|--------|----------|
| `add_model` | Append to `extra_models` (or `models` if target specified) |
| `delete_model` | Remove from `extra_models` only |
| `update_config` | Update name, base_url, api_key, chat_model, generate_kwargs |
| `get_effective_generate_kwargs` | Deep-merge provider-level + model-level kwargs |
| `update_model_config` | Update per-model generate_kwargs |
| `has_model` | Check if model_id exists in models + extra_models |
| `probe_model_multimodal` | Return default `ProbeResult()` (all False) — override for actual probing |
| `get_info` | Return masked ProviderInfo (api_key hidden) |

### Provider Discovery and Type Resolution

When loading providers from disk, the correct provider class is resolved:

```python
def _provider_from_data(self, data: Dict) -> Provider:
    provider_id = str(data.get("id", ""))
    chat_model = str(data.get("chat_model", ""))

    if provider_id == "openrouter":
        return OpenRouterProvider.model_validate(data)
    if provider_id == "anthropic" or chat_model == "AnthropicChatModel":
        return AnthropicProvider.model_validate(data)
    if provider_id == "gemini" or chat_model == "GeminiChatModel":
        return GeminiProvider.model_validate(data)
    if provider_id == "ollama":
        return OllamaProvider.model_validate(data)
    return OpenAIProvider.model_validate(data)  # Default
```

---

## 4. Model Routing and Fallback Mechanisms

### 4.1 Model Activation Flow

```
activate_model(provider_id, model_id)
  ├── Validate provider exists
  ├── Validate model exists in provider
  ├── Create ModelSlotConfig
  ├── save_active_model()           # Persist to active_model.json
  └── maybe_probe_multimodal()      # Async probe if capability unknown
```

### 4.2 Multimodal Capability Probing

**Purpose**: Determine if a model supports image and/or video input.

**Probe Process**:
1. Check if model already has capability annotations
2. If not, schedule background async probe via `_auto_probe_multimodal()`
3. Probe uses semantic verification (not just API acceptance)

**Image Probe Strategy** (Two-stage):
1. Send minimal 1x1 PNG → if 400 error or media-keyword error → not supported
2. If accepted, ask model "What color is this image?" → verify it detects red correctly

**Video Probe Strategy**:
1. Try base64-encoded MP4 first
2. Fall back to HTTP URL if base64 rejected
3. Ask "What is the dominant color?" → verify "blue" detection

**Probe Result Caching**:
- Results stored in `ModelInfo.supports_image`, `supports_video`, `supports_multimodal`
- `probe_source` set to "probed"
- Persisted to disk

### 4.3 Capability Baseline Registry

`capability_baseline.py` provides **expected capabilities** for all built-in models based on official documentation. After probing, results are compared:

```python
# If probe result != expected, log warning
discrepancies = compare_probe_result(expected, actual_image, actual_video)
for d in discrepancies:
    logger.warning("Probe discrepancy: %s/%s %s expected=%s actual=%s",
                   d.provider_id, d.model_id, d.field, d.expected, d.actual)
```

### 4.4 generate_kwargs Deep Merge

Provider-level and model-level `generate_kwargs` are deep-merged:

```python
# Provider-level defaults
generate_kwargs = {"temperature": 0.7, "top_p": 0.9}

# Model-level override
model.generate_kwargs = {"temperature": 0.5}

# Result: merged
effective = {"temperature": 0.5, "top_p": 0.9}  # temperature overridden, top_p inherited
```

### 4.5 Retry and Rate Limiting

**RetryChatModel** wrapper provides:
- **Exponential backoff**: `base * 2^(attempt-1)`, capped
- **Retryable errors**: 429, 500, 502, 503, 504, 529 + SDK-specific errors
- **Streaming support**: Full request retry on stream failure

**LLMRateLimiter** provides:
- **Concurrency cap**: Semaphore limits in-flight requests
- **QPM sliding window**: Tracks request timestamps, waits if exceeded
- **429 coordination**: Global pause on rate-limit, all callers wait same duration + jitter

### 4.6 Fallback Chain for Local Models

```python
async def _resume_local_model(self, local_manager) -> None:
    # 1. Check llama.cpp installed
    # 2. Check model downloaded
    # 3. Setup server
    # 4. Update qwenpaw-local provider with new base_url
    # On failure: clear provider config
```

### 4.7 Custom Provider Fallback

When a custom provider ID conflicts with a built-in:
```python
def _resolve_custom_provider_id(self, provider_id: str) -> str:
    if provider_id in self.builtin_providers:
        provider_id = f"{provider_id}-custom"
    while provider_id in self.builtin_providers or self.custom_providers:
        provider_id = f"{provider_id}-new"
    return provider_id
```

---

## 5. Key Data Structures

### ProbeResult
```python
@dataclass
class ProbeResult:
    supports_image: bool = False
    supports_video: bool = False
    image_message: str = ""
    video_message: str = ""

    @property
    def supports_multimodal(self) -> bool:
        return self.supports_image or self.supports_video
```

### ExpectedCapability
```python
@dataclass
class ExpectedCapability:
    provider_id: str
    model_id: str
    expected_image: bool | None
    expected_video: bool | None
    doc_url: str = ""
    note: str = ""
```

### DiscrepancyLog
```python
@dataclass
class DiscrepancyLog:
    provider_id: str
    model_id: str
    field: str          # "image" or "video"
    expected: bool | None
    actual: bool
    discrepancy_type: str  # "false_negative" or "false_positive"
```

### ModelSlotConfig
```python
class ModelSlotConfig(BaseModel):
    provider_id: str
    model: str
```

---

## 6. Persistence and Security

### Encryption
Sensitive fields (`api_key`) are encrypted before disk storage:
```python
# From secret_store.py
encrypt_dict_fields(provider.model_dump(), PROVIDER_SECRET_FIELDS)
decrypt_dict_fields(data, PROVIDER_SECRET_FIELDS)
```

### Permission Hardening
```python
os.chmod(path, 0o700)  # Provider directories
os.chmod(provider_path, 0o600)  # Provider JSON files
```

### Legacy Migration
- `providers.json` (legacy) → individual JSON files per provider
- `copaw-local` → `qwenpaw-local` (backward compatibility)

### Active Model Persistence
```json
// active_model.json
{
  "provider_id": "dashscope",
  "model": "qwen3-max"
}
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      ProviderManager (Singleton)                 │
├─────────────────────────────────────────────────────────────────┤
│  builtin_providers: Dict[str, Provider]                         │
│  custom_providers: Dict[str, Provider]                          │
│  plugin_providers: Dict[str, Dict]  # {info, class}             │
│  active_model: ModelSlotConfig | None                          │
├─────────────────────────────────────────────────────────────────┤
│  _init_builtins()           # Register 22 built-in providers     │
│  _init_from_storage()      # Load encrypted configs from disk   │
│  _apply_default_annotations()  # Fill capability baselines      │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
   │ OpenAIProvider│    │AnthropicProvider│  │GeminiProvider│
   │             │    │             │    │             │
   │ _client()   │    │ _client()   │    │ _client()   │
   │ fetch_models│    │ fetch_models│    │ fetch_models│
   │ probe_image │    │ probe_image │    │ probe_image │
   │ probe_video │    │ probe_video │    │ probe_video │
   └─────────────┘    └─────────────┘    └─────────────┘
          │                   │                   │
          └───────────────────┼───────────────────┘
                              │
                              ▼
                   ┌─────────────────────┐
                   │ Provider (ABC)      │
                   │                     │
                   │ check_connection()  │
                   │ fetch_models()      │
                   │ get_chat_model_instance()
                   │ probe_model_multimodal()
                   └─────────────────────┘
                              │
                              ▼
                   ┌─────────────────────┐
                   │ ChatModelBase        │
                   │ (AgentScope)         │
                   │                      │
                   │ OpenAIChatModel      │
                   │ AnthropicChatModel   │
                   │ GeminiChatModel       │
                   └─────────────────────┘
                              │
                              ▼
                   ┌─────────────────────┐
                   │ RetryChatModel       │
                   │ (Retry Wrapper)      │
                   │                      │
                   │ Exponential backoff   │
                   │ Rate limiting        │
                   └─────────────────────┘
                              │
                              ▼
                   ┌─────────────────────┐
                   │ LLMRateLimiter       │
                   │ (Global Singleton)   │
                   │                      │
                   │ Semaphore (concurr)  │
                   │ QPM sliding window   │
                   │ 429 coordination     │
                   └─────────────────────┘
```

---

## File Reference

| File | Lines | Purpose |
|------|-------|---------|
| `/src/qwenpaw/providers/provider_manager.py` | 1748 | ProviderManager singleton, built-in definitions |
| `/src/qwenpaw/providers/provider.py` | ~400 | BaseProvider ABC, ModelInfo, ProviderInfo |
| `/src/qwenpaw/providers/openai_provider.py` | 518 | OpenAI-compatible provider implementation |
| `/src/qwenpaw/providers/anthropic_provider.py` | 270 | Anthropic Claude API provider |
| `/src/qwenpaw/providers/gemini_provider.py` | 320 | Google Gemini API provider |
| `/src/qwenpaw/providers/openrouter_provider.py` | 320 | OpenRouter aggregator provider |
| `/src/qwenpaw/providers/ollama_provider.py` | 68 | Ollama local provider |
| `/src/qwenpaw/providers/lmstudio_provider.py` | 20 | LM Studio local provider |
| `/src/qwenpaw/providers/multimodal_prober.py` | 200 | Shared probe constants and evaluation |
| `/src/qwenpaw/providers/capability_baseline.py` | 400 | Expected capabilities registry |
| `/src/qwenpaw/providers/openai_chat_model_compat.py` | 200 | Tool-call parsing for streaming |
| `/src/qwenpaw/providers/retry_chat_model.py` | 350 | Retry wrapper + rate limiting |
| `/src/qwenpaw/providers/rate_limiter.py` | 220 | Global rate limiter implementation |
