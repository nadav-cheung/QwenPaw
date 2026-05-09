# Provider 系统深度解析

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 分析 Provider 抽象层的设计模式 2) 理解模型路由和切换策略 3) 扩展自定义 Provider |
| **前置知识** | [11-Model系统与LLM提供商](./11-Model系统与LLM提供商.md) |
| **预计时长** | 45 分钟（阅读 35 分钟 + 练习 10 分钟） |
| **难度等级** | ⭐⭐⭐⭐ |
| **核心关键词** | `Provider` `路由策略` `模型切换` |

> **一句话概述**：本章深入分析 QwenPaw 的 Provider 抽象层架构，涵盖 ProviderManager 单例管理、模型激活流程、多模态探测机制和密钥加密存储，帮助读者理解模型路由策略并掌握自定义 Provider 的扩展方法。

## 概述

Provider 是 QwenPaw 的模型供应抽象层，通过 ProviderManager 统一管理，支持本地模型、OpenAI 兼容 API 和多 Provider 路由。系统内置 24+ Provider，支持模型探测、多模态检测和密钥加密存储。

**核心职责：**
- 统一封装不同模型 API 的差异
- 提供模型发现、连接检查、多模态探测能力
- 管理 API 密钥加密存储
- 支持 Provider 热切换和自定义 Provider 扩展

**源码路径：** `src/qwenpaw/providers/`

---

## 1. Provider 抽象

**源码路径**: `src/qwenpaw/providers/provider.py:137`

### 1.1 Provider 基类

`Provider` 是所有模型供应者的抽象基类，继承自 `ProviderInfo`：

```python
class Provider(ProviderInfo, ABC):
    """Represents a provider instance with its configuration."""

    @abstractmethod
    async def check_connection(self, timeout: float = 5) -> tuple[bool, str]:
        """Check if the provider is reachable with the current config."""

    @abstractmethod
    async def fetch_models(self, timeout: float = 5) -> List[ModelInfo]:
        """Fetch the list of available models from the provider."""

    @abstractmethod
    async def check_model_connection(
        self,
        model_id: str,
        timeout: float = 5,
    ) -> tuple[bool, str]:
        """Check if a specific model is reachable/usable."""

    @abstractmethod
    def get_chat_model_instance(self, model_id: str) -> ChatModelBase:
        """Return an instance of the chat model associated with this provider."""
```

### 1.2 ModelInfo 数据类

**源码路径**: `src/qwenpaw/providers/provider.py:22`

```python
class ModelInfo(BaseModel):
    id: str                           # API 调用使用的模型标识符
    name: str                         # 人类可读的模型名称
    supports_multimodal: bool | None # 是否支持多模态输入
    supports_image: bool | None       # 是否支持图像输入
    supports_video: bool | None       # 是否支持视频输入
    probe_source: str | None         # 'documentation' 或 'probed'
    is_free: bool = False            # 是否免费使用
    generate_kwargs: Dict[str, Any] = {}  # 模型级生成参数覆盖
```

### 1.3 ExtendedModelInfo 扩展模型信息

**源码路径**: `src/qwenpaw/providers/provider.py:54`

`ExtendedModelInfo` 继承 `ModelInfo`，增加 Provider 关联、模态类型和定价等元数据，主要用于内部探测和注册表比对：

```python
class ExtendedModelInfo(ModelInfo):
    """Extended model info with additional metadata for providers."""
    provider: str = Field(
        default="",
        description="Provider/series (e.g., 'openai', 'google')",
    )
    input_modalities: List[str] = Field(
        default_factory=list,
        description="Supported input modalities",
    )
    output_modalities: List[str] = Field(
        default_factory=list,
        description="Supported output modalities",
    )
    pricing: Dict[str, str] = Field(
        default_factory=dict,
        description="Pricing info (prompt/completion)",
    )
```

| 字段 | 用途 | 示例 |
|------|------|------|
| `provider` | 所属系列 | `"openai"`, `"google"` |
| `input_modalities` | 支持的输入类型 | `["text", "image", "video"]` |
| `output_modalities` | 支持的输出类型 | `["text"]` |
| `pricing` | 计费信息 | `{"prompt": "$2.50/1M", "completion": "$10.00/1M"}` |

`ExtendedModelInfo` 与 `ModelInfo` 的区别：`ModelInfo` 是运行时的轻量模型描述，`ExtendedModelInfo` 用于探测基线注册表（`ExpectedCapabilityRegistry`），承载更丰富的元数据以支持能力比对。

### 1.4 ProviderInfo 数据类

**源码路径**: `src/qwenpaw/providers/provider.py:70`

```python
class ProviderInfo(BaseModel):
    id: str                           # Provider 标识符
    name: str                         # 人类可读的 Provider 名称
    base_url: str = ""                # API 基础 URL
    api_key: str = ""                 # API 密钥（加密存储）
    chat_model: str = "OpenAIChatModel"  # AgentScope ChatModel 名称
    models: List[ModelInfo] = []      # 预定义模型列表
    extra_models: List[ModelInfo] = []  # 用户添加的模型列表
    api_key_prefix: str = ""         # API 密钥前缀（如 'sk-'）
    is_local: bool = False            # 是否为本地托管平台
    freeze_url: bool = False        # base_url 是否冻结（不可编辑）
    require_api_key: bool = True     # 是否需要 API 密钥
    is_custom: bool = False         # 是否为用户创建（内置 vs 自定义）
    support_model_discovery: bool = False  # 是否支持从 API 获取模型列表
    support_connection_check: bool = True  # 是否支持连接检查
    generate_kwargs: Dict[str, Any] = {}  # Provider 级生成参数
```

---

## 2. ProviderManager

**源码路径**: `src/qwenpaw/providers/provider_manager.py:720`

`ProviderManager` 是全局单例，负责管理所有内置和自定义 Provider。

### 2.1 类定义

```python
class ProviderManager:  # pylint: disable=too-many-public-methods
    """A manager class to handle all providers, including built-in and custom ones."""

    _instance = None  # 单例模式

    def __init__(self) -> None:
        self.builtin_providers: Dict[str, Provider] = {}
        self.custom_providers: Dict[str, Provider] = {}
        self.plugin_providers: Dict[str, Dict] = {}  # 插件 Provider
        self.active_model: ModelSlotConfig | None = None
        self.root_path = SECRET_DIR / "providers"
        self.builtin_path = self.root_path / "builtin"
        self.custom_path = self.root_path / "custom"
        self.plugin_path = self.root_path / "plugin"
        self._prepare_disk_storage()
        self._init_builtins()
        self._init_from_storage()
```

### 2.2 内置 Provider 初始化

**源码路径**: `src/qwenpaw/providers/provider_manager.py:745`

```python
def _init_builtins(self):
    # 本地 / 聚合
    self._add_builtin(PROVIDER_QWENPAW)          # QwenPaw 本地模型
    self._add_builtin(PROVIDER_OLLAMA)            # Ollama 本地
    self._add_builtin(PROVIDER_LMSTUDIO)          # LM Studio
    self._add_builtin(PROVIDER_OPENROUTER)        # OpenRouter 聚合
    self._add_builtin(PROVIDER_MODELSCOPE)        # ModelScope
    # 阿里云系列
    self._add_builtin(PROVIDER_DASHSCOPE)         # DashScope
    self._add_builtin(PROVIDER_ALIYUN_CODINGPLAN) # 阿里云编码计划 CN
    self._add_builtin(PROVIDER_ALIYUN_CODINGPLAN_INTL) # 阿里云编码计划 INTL
    self._add_builtin(PROVIDER_OPENCODE)          # OpenCode
    # 国际大厂
    self._add_builtin(PROVIDER_OPENAI)            # OpenAI
    self._add_builtin(PROVIDER_AZURE_OPENAI)      # Azure OpenAI
    self._add_builtin(PROVIDER_ANTHROPIC)         # Anthropic
    self._add_builtin(PROVIDER_GEMINI)            # Google Gemini
    # 国内大模型
    self._add_builtin(PROVIDER_DEEPSEEK)          # DeepSeek
    self._add_builtin(PROVIDER_KIMI_CN)           # Kimi CN
    self._add_builtin(PROVIDER_KIMI_INTL)         # Kimi INTL
    self._add_builtin(PROVIDER_MINIMAX_CN)        # MiniMax CN
    self._add_builtin(PROVIDER_MINIMAX)           # MiniMax INTL
    self._add_builtin(PROVIDER_ZHIPU_CN)          # 智谱 CN
    self._add_builtin(PROVIDER_ZHIPU_CN_CODINGPLAN)   # 智谱 CN 编码计划
    self._add_builtin(PROVIDER_ZHIPU_INTL)        # 智谱 INTL
    self._add_builtin(PROVIDER_ZHIPU_INTL_CODINGPLAN) # 智谱 INTL 编码计划
    self._add_builtin(PROVIDER_SILICONFLOW_CN)    # SiliconFlow CN
    self._add_builtin(PROVIDER_SILICONFLOW_INTL)  # SiliconFlow INTL
```

共 **24 个内置 Provider**，按功能分为四类：

| 类别 | Provider | Provider 类 |
|------|----------|-------------|
| 本地/聚合 | QwenPaw, Ollama, LM Studio, OpenRouter, ModelScope | OpenAIProvider / OllamaProvider / LMStudioProvider / OpenRouterProvider |
| 阿里云 | DashScope, Aliyun CodingPlan CN/INTL, OpenCode | OpenAIProvider |
| 国际大厂 | OpenAI, Azure OpenAI, Anthropic, Gemini | OpenAIProvider / AnthropicProvider / GeminiProvider |
| 国内大模型 | DeepSeek, Kimi CN/INTL, MiniMax CN/INTL, 智谱 CN/CodingPlan/INTL/INTL CodingPlan, SiliconFlow CN/INTL | OpenAIProvider / AnthropicProvider |

### 2.3 核心方法表

| 行号 | 方法签名 | 说明 |
|------|----------|------|
| 720 | `__init__()` | 初始化，加载内置和自定义 Provider |
| 789 | `get_provider(provider_id)` | 通过 ID 获取 Provider 实例 |
| 797 | `get_provider_info(provider_id)` | 获取 Provider 信息（异步） |
| 800 | `get_active_model()` | 获取当前活跃的模型配置 |
| 850 | `update_provider(provider_id, config)` | 更新 Provider 配置 |
| 888 | `start_local_model_resume(local_manager)` | 调度后台本地模型恢复 |
| 895 | `fetch_provider_models(provider_id, save)` | 从 Provider 获取可用模型列表 |
| 955 | `add_custom_provider(provider_data)` | 添加自定义 Provider |
| 965 | `remove_custom_provider(provider_id)` | 移除自定义 Provider |
| 985 | `activate_model(provider_id, model_id)` | 激活指定模型 |
| 1000 | `maybe_probe_multimodal(provider_id, model_id)` | 调度多模态探测 |
| 1024 | `_auto_probe_multimodal(provider_id, model_id)` | 后台多模态探测任务 |
| 1050 | `add_model_to_provider(provider_id, model_info)` | 添加模型到 Provider |
| 1070 | `update_model_config(provider_id, model_id, config)` | 更新模型配置 |
| 1124 | `probe_model_multimodal(provider_id, model_id, image_only)` | 探测模型多模态能力 |

### 2.4 模型激活流程

**源码路径**: `src/qwenpaw/providers/provider_manager.py:985`

```python
async def activate_model(self, provider_id: str, model_id: str):
    """Set the active provider and model for the agent."""
    provider_id = self._normalize_provider_id(provider_id)
    provider = self.get_provider(provider_id)
    if not provider:
        raise ProviderError(message=f"Provider '{provider_id}' not found.")
    if not provider.has_model(model_id):
        raise ModelNotFoundException(model_name=f"{provider_id}/{model_id}")

    self.active_model = ModelSlotConfig(
        provider_id=provider_id,
        model=model_id,
    )
    self.save_active_model(self.active_model)

    # 自动探测多模态能力（如未知）
    self.maybe_probe_multimodal(provider_id, model_id)
```

**模型激活时序图：**

```
activate_model(provider_id, model_id)
    │
    ├─→ _normalize_provider_id()
    │
    ├─→ get_provider(provider_id)
    │       │
    │       └─→ 返回 Provider 实例
    │
    ├─→ provider.has_model(model_id)
    │       │
    │       └─→ 验证模型存在
    │
    ├─→ save_active_model()
    │       │
    │       └─→ 持久化到磁盘
    │
    └─→ maybe_probe_multimodal()
            │
            └─→ 调度后台探测任务（如能力未知）
```

---

## 3. 模型探测与能力检测

### 3.1 probe_model_multimodal

**源码路径**: `src/qwenpaw/providers/provider_manager.py:1124`

```python
async def probe_model_multimodal(
    self,
    provider_id: str,
    model_id: str,
    image_only: bool = False,
) -> dict:
    """Probe a model's multimodal capabilities and persist the result.

    Args:
        provider_id: Provider identifier.
        model_id: Model identifier.
        image_only: When True, skip the video probe for a faster result.
    """
    provider = self.get_provider(provider_id)
    result = await provider.probe_model_multimodal(
        model_id,
        image_only=image_only,
    )

    # 更新模型的 capability flags
    for model in provider.models + provider.extra_models:
        if model.id == model_id:
            model.supports_image = result.supports_image
            if not image_only:
                model.supports_video = result.supports_video
                model.supports_multimodal = result.supports_multimodal
            model.probe_source = "probed"
            break
```

### 3.2 多模态探测结果

```python
class ProbeResult:
    supports_image: bool       # 是否支持图像
    supports_video: bool       # 是否支持视频
    supports_multimodal: bool  # 是否支持多模态
```

### 3.3 自动探测机制

**源码路径**: `src/qwenpaw/providers/provider_manager.py:1000`

```python
def maybe_probe_multimodal(self, provider_id: str, model_id: str) -> None:
    """Schedule multimodal probing for a Model if capability is unknown."""
    provider = self.get_provider(provider_id)
    # 如果能力未知，自动探测
    for model in provider.models + provider.extra_models:
        if model.id == model_id and model.supports_multimodal is None:
            asyncio.create_task(
                self._auto_probe_multimodal(provider_id, model_id),
            )
            break
```

### 3.4 探测结果缓存

探测结果会缓存到 Provider 配置中，后续使用直接读取缓存，无需重复探测。

---

## 4. 密钥管理

### 4.1 SecretStore 4 层密钥解析

**源码路径**: `src/qwenpaw/security/secret_store.py`

```python
# 4 层密钥解析（优先级从高到低）：
# 1. COPAW_MASTER_KEY / QWENPAW_MASTER_KEY 环境变量
# 2. ~/.qwenpaw/.master_key 文件
# 3. 工作区 .master_key 文件
# 4. 生成新密钥（首次启动）

async def _get_master_key(self) -> bytes:
    """Get or create master key with double-check locking."""
    # 1. Check cache
    if self._master_key:
        return self._master_key

    # 2. Double-check locking
    async with self._lock:
        if self._master_key:
            return self._master_key
        # Try each source in order...
```

### 4.2 Provider 密钥加密

**源码路径**: `src/qwenpaw/providers/provider_manager.py:28`

```python
from ..security.secret_store import (
    PROVIDER_SECRET_FIELDS,    # 需要加密的字段列表
    decrypt_dict_fields,       # 解密字段
    encrypt_dict_fields,       # 加密字段
    is_encrypted,             # 检查是否已加密
)
```

---

## 5. 本地模型管理

**源码路径**: `src/qwenpaw/local_models/manager.py:41`

### 5.1 LocalModelManager

```python
class LocalModelManager:
    """本地模型管理器 Facade"""

    def get_instance() -> "LocalModelManager": ...      # 单例获取
    def get_config() -> LocalModelConfig: ...           # 获取配置
    def set_max_context_length(n: int): ...             # 设置上下文长度
    def set_port(p: int): ...                          # 设置端口
    def start_llamacpp_download(): ...                  # 启动下载
    def setup_server(model_id: str) -> StartServerResponse: ...  # 启动服务
    def shutdown_server(): ...                          # 关闭服务
```

### 5.2 Llama.cpp Server 生命周期

**启动流程：**

```
1. 检查 llama-server 可执行文件存在
2. 验证模型路径有效
3. 解析 GGUF 模型文件和可选 mmproj 文件
4. 若相同模型已在运行 → 直接返回
5. 若不同模型运行 → 先 shutdown_server()
6. 解析端口（自动选择空闲端口）
7. 创建子进程: llama-server --host 127.0.0.1 --port <port> --model <path>
8. 启动异步日志排出任务
9. 轮询 /health 端点等待就绪（最多 120s）
```

**关闭流程：**

```python
# 使用 _server_shutdown_context() 上下文管理器
# 优雅关闭 5s → 强制 kill 3s
```

### 5.3 下载管理

**源码路径**: `src/qwenpaw/local_models/download_manager.py:253`

```python
class ProcessDownloadController:
    """后台进程下载控制器"""

    def start(): ...     # 启动下载线程
    def cancel(): ...   # 优雅/kill 关闭下载进程
    def get_progress() -> DownloadProgress: ...
```

**下载源：**

```python
class DownloadSource(str, Enum):
    HUGGINGFACE = "huggingface"   # HF Hub
    MODELSCOPE = "modelscope"      # ModelScope CN
    AUTO = "auto"                  # 先 HF 后 MS
```

---

## 6. ExpectedCapabilityRegistry 与探测基线

### 6.1 ExpectedCapabilityRegistry

**源码路径**: `src/qwenpaw/providers/capability_baseline.py`

`ExpectedCapabilityRegistry` 提供预定义的模型能力基线数据，在探测不可用（如网络受限、API Key 缺失）时作为 fallback。探测完成后，实际结果与基线进行比对，发现偏差时记录警告：

```python
# provider_manager.py:1167-1189 — 探测结果与基线比对
from .capability_baseline import (
    ExpectedCapabilityRegistry,
    compare_probe_result,
)

registry = ExpectedCapabilityRegistry()
expected = registry.get_expected(provider_id, model_id)
if expected:
    discrepancies = compare_probe_result(
        expected,
        result.supports_image,
        result.supports_video,
    )
    for d in discrepancies:
        logger.warning(
            "Probe discrepancy: %s/%s %s expected=%s actual=%s (%s)",
            d.provider_id, d.model_id, d.field,
            d.expected, d.actual, d.discrepancy_type,
        )
```

**设计意图**：
- 防止 Provider API 返回错误的多模态能力标记
- 在首次探测前提供合理的默认值
- 帮助调试 Provider 侧的能力声明变更

### 6.2 向后兼容迁移

**源码路径**: `src/qwenpaw/providers/provider_manager.py:814`, `1382`

系统从旧版 CoPaw 重命名为 QwenPaw 时，提供了两层兼容迁移：

**1) ID 规范化** (`_normalize_provider_id`, L814)：

```python
@staticmethod
def _normalize_provider_id(provider_id: str) -> str:
    """Normalize provider ID for backward compatibility.
    Maps legacy 'copaw-local' to 'qwenpaw-local'.
    """
    if provider_id == "copaw-local":
        return "qwenpaw-local"
    return provider_id
```

每次 `get_provider()` 和 `activate_model()` 调用时自动执行，确保旧配置文件中的 `copaw-local` 引用透明映射到新的 `qwenpaw-local`。

**2) 配置文件迁移** (`_migrate_copaw_config`, L1382)：

```python
def _migrate_copaw_config(self) -> None:
    """Migrate copaw-local provider config to qwenpaw-local."""
    # 1. 迁移活跃模型配置中的 provider_id
    if self.active_model and self.active_model.provider_id == "copaw-local":
        self.active_model.provider_id = "qwenpaw-local"
        self.save_active_model(self.active_model)

    # 2. 迁移磁盘上的配置文件
    copaw_config_path = self.builtin_path / "copaw-local.json"
    if not copaw_config_path.exists():
        return
    # 加载旧配置 → 应用到新 Provider → 删除旧文件
    old_config = json.load(f)
    provider.extra_models = [ModelInfo.model_validate(m) for m in old_config.get("extra_models", [])]
    self._save_provider(provider, is_builtin=True)
    copaw_config_path.unlink()  # 删除旧配置
```

迁移在 `ProviderManager.__init__()` 中执行一次，确保用户无感知升级。

---

## 7. 内置模型列表

### 7.1 OpenAI 模型

**源码路径**: `src/qwenpaw/providers/provider_manager.py:160`

| 模型 ID | 名称 | 多模态 | 视频 |
|---------|------|--------|------|
| `gpt-5.2` | GPT-5.2 | ✓ | ✓ |
| `gpt-5` | GPT-5 | ✓ | ✓ |
| `gpt-5-mini` | GPT-5 Mini | ✓ | ✓ |
| `gpt-4.1` | GPT-4.1 | ✓ | ✓ |
| `gpt-4o` | GPT-4o | ✓ | ✓ |
| `o3` | o3 | ✓ | - |

### 7.2 Anthropic 模型（动态发现）

**源码路径**: `src/qwenpaw/providers/provider_manager.py:436`

Anthropic Provider **不维护静态模型列表**。源码中 `ANTHROPIC_MODELS: List[ModelInfo] = []` 为空，所有模型通过 `fetch_models()` 调用 Anthropic API (`/v1/models` 端点) 在运行时动态获取。

```python
# provider_manager.py:436 — Anthropic 没有硬编码模型
ANTHROPIC_MODELS: List[ModelInfo] = []

# provider_manager.py:650 — 动态获取模型
PROVIDER_ANTHROPIC = AnthropicProvider(
    provider_id="anthropic",
    name="Anthropic",
    base_url="https://api.anthropic.com/v1",
    api_key_env="ANTHROPIC_API_KEY",
    models=ANTHROPIC_MODELS,  # 空列表，由 fetch_models() 填充
)
```

这意味着用户配置 Anthropic API Key 后，需要调用 `fetch_provider_models("anthropic")` 从远程获取可用模型列表，模型范围随 Anthropic API 更新自动同步。

### 7.3 本地模型推荐

| 内存 | 推荐模型 | 量化 |
|------|----------|------|
| ≤8GB | QwenPaw-Flash-2B | Q4_K_M 或 Q8_0 |
| ≤16GB | QwenPaw-Flash-4B | Q4_K_M |
| >16GB | QwenPaw-Flash-9B | Q4_K_M |

---

## 8. 插件扩展

### 8.1 插件 Provider 注册

**源码路径**: `src/qwenpaw/providers/provider_manager.py:820`

```python
# ProviderManager 支持插件 Provider
self.plugin_providers: Dict[str, Dict] = {}  # 插件 Provider 配置

# 从插件目录加载
self.plugin_path = self.root_path / "plugin"
```

### 8.2 register_plugin_provider() 详解

**源码路径**: `src/qwenpaw/providers/provider_manager.py:1632`

`register_plugin_provider()` 允许插件系统在运行时注册新的 Provider，无需修改内置 Provider 列表：

```python
def register_plugin_provider(
    self, provider_id: str, provider_class,
    label: str, base_url: str, metadata: Dict,
):
    """Register a plugin provider at runtime."""
    # 1. 获取 Provider 类的默认模型列表
    default_models = []
    if hasattr(provider_class, "get_default_models"):
        default_models = provider_class.get_default_models()

    # 2. 创建 ProviderInfo 实例
    provider_info = ProviderInfo(
        id=provider_id, name=label, base_url=base_url,
        models=default_models,
        is_custom=False,  # 插件 Provider 不可删除
        require_api_key=metadata.get("require_api_key", True),
    )

    # 3. 恢复已保存的配置（含加密字段解密）
    saved_config_path = self.plugin_path / f"{provider_id}.json"
    if saved_config_path.exists():
        saved_config = json.load(open(saved_config_path))
        # 解密并应用到 provider_info...
```

**插件 Provider vs 自定义 Provider**：

| 特性 | 插件 Provider | 自定义 Provider |
|------|--------------|----------------|
| 来源 | 插件系统动态注册 | 用户手动创建 |
| 可删除 | 否（类似内置） | 是 |
| 存储 | `plugin/` 目录 | `custom/` 目录 |
| 模型发现 | 支持 | 支持 |

### 8.3 Provider 加载流程

```
1. 扫描 plugin_providers 目录
2. 加载插件 Provider 配置
3. 实例化插件 Provider 类
4. 注册到 plugin_providers
5. get_provider() 优先检查插件 Provider
```

---

## 9. 配置持久化

### 9.1 存储路径

**源码路径**: `src/qwenpaw/providers/provider_manager.py:732`

```python
self.root_path = SECRET_DIR / "providers"
self.builtin_path = self.root_path / "builtin"   # 内置 Provider（只读）
self.custom_path = self.root_path / "custom"    # 自定义 Provider
self.plugin_path = self.root_path / "plugin"    # 插件 Provider
```

### 9.2 磁盘结构

```
~/.qwenpaw/secrets/providers/
├── builtin/           # 内置 Provider 配置（只读）
├── custom/            # 用户自定义 Provider
│   └── my-provider.json
└── plugin/            # 插件 Provider
    └── my-plugin-provider.json
```

---

## 10. 应用场景

### 场景 1: 多模型负载均衡

**问题：** 需要在多个模型之间切换以平衡成本或性能

**解决方案：**
```python
# 配置多个 Provider
providers = ["openai", "anthropic", "deepseek"]

# 轮询或按能力选择
for provider_id in providers:
    provider = provider_manager.get_provider(provider_id)
    if await provider.check_connection():
        model = select_best_model(provider)
        break
```

### 场景 2: 本地模型离线部署

**问题：** 需要在无网络环境下运行

**解决方案：**
```python
# 使用 Ollama 或 LM Studio 本地 Provider
LocalModelManager.setup_server(model_id="llama3.1:8b")

# 配置本地 Provider
provider_config = {
    "id": "local-ollama",
    "base_url": "http://127.0.0.1:11434",
    "is_local": True,
}
```

### 场景 3: 自定义 Provider 接入

**问题：** 需要接入不在内置列表中的模型服务

**解决方案：**
```json
// ~/.qwenpaw/secrets/providers/custom/my-provider.json
{
  "id": "my-provider",
  "name": "My Custom Provider",
  "base_url": "https://api.my-provider.com",
  "api_key": "sk-...",
  "chat_model": "OpenAIChatModel",
  "models": [
    {"id": "my-model-1", "name": "My Model 1"}
  ]
}
```

---

## 11. 最佳实践

### 11.1 Provider 选择指南

| 场景 | 推荐 Provider | 理由 |
|------|---------------|------|
| 通用对话 | OpenAI / Anthropic | 稳定、覆盖广 |
| 代码生成 | Anthropic Claude | 代码能力突出 |
| 中文场景 | DashScope / Kimi | 国内优化 |
| 成本敏感 | DeepSeek / Ollama | 价格低/免费 |
| 隐私敏感 | Ollama 本地 | 数据不出境 |

### 11.2 密钥安全建议

```python
# 1. 使用环境变量而非硬编码
export QWENPAW_MASTER_KEY="your-master-key"

# 2. 定期轮换密钥
# 通过 API 重新加密 Provider 配置

# 3. 容器环境禁用 Keychain
export QWENPAW_RUNNING_IN_CONTAINER=true
```

### 11.3 模型探测优化

```python
# 批量探测时跳过已知模型
for model in models:
    if model.supports_multimodal is not None:
        continue  # 跳过已探测的模型
    await probe_model_multimodal(provider_id, model.id)
```

---

## 12. 常见问题

### Q1: Provider 连接失败

**原因：**
- API 密钥错误或过期
- base_url 配置不正确
- 网络无法访问

**排查步骤：**
```python
# 1. 手动测试连接
provider = provider_manager.get_provider("openai")
ok, msg = await provider.check_connection(timeout=10)
print(f"Connection: {ok}, message: {msg}")

# 2. 检查 base_url
print(provider.base_url)  # 确认 URL 正确

# 3. 验证 API 密钥
print(provider.api_key[:8] + "...")  # 确认密钥存在
```

### Q2: 模型激活失败 ModelNotFoundException

**原因：**
- 模型 ID 不在 Provider 的模型列表中
- Provider 未正确加载

**解决方案：**
```python
# 1. 列出 Provider 所有可用模型
provider = provider_manager.get_provider("openai")
for model in provider.models:
    print(f"{model.id}: {model.name}")

# 2. 添加自定义模型
provider_manager.add_model_to_provider("openai", {
    "id": "gpt-4o-mini",
    "name": "GPT-4o Mini",
})

# 3. 重新获取模型列表
await provider_manager.fetch_provider_models("openai", save=True)
```

### Q3: 多模态探测结果不准确

**原因：**
- 探测图像/视频过小被 Provider 拒绝
- Provider 返回了错误信息

**解决方案：**
```python
# 1. 检查探测图像大小（需 >= 32x32）
# 2. 查看探测日志
import logging
logging.getLogger("providers").setLevel(logging.DEBUG)

# 3. 手动覆盖能力标记
provider_manager.update_model_config(
    "openai", "gpt-4o",
    {"supports_multimodal": True, "supports_video": True}
)
```

### Q4: 自定义 Provider 无法加载

**原因：**
- JSON 格式错误
- 缺少必需字段
- Provider 类不存在

**排查步骤：**
```bash
# 1. 验证 JSON 格式
cat ~/.qwenpaw/secrets/providers/custom/my-provider.json | python -m json.tool

# 2. 检查必需字段
# id, name, base_url, chat_model 必需

# 3. 查看加载错误日志
grep -i "provider" logs/qwenpaw.log
```

---

## 13. 交叉引用

| 相关章节 | 关联内容 |
|----------|----------|
| [85-模型探测与能力检测](85-模型探测与能力检测.md) | 多模态探测原理和 ExpectedCapabilityRegistry |
| [39-密钥存储加密系统](39-密钥存储加密系统.md) | SecretStore 密钥加密机制 |
| [37-配置热重载机制](37-配置热重载机制.md) | Provider 配置热重载 |

---

## 14. 总结

**核心要点：**

1. **Provider 抽象：** 统一接口封装不同模型 API，支持连接检查、模型发现、多模态探测
2. **ProviderManager：** 单例模式管理所有内置和自定义 Provider，支持配置持久化
3. **模型探测：** 首次使用时自动探测多模态能力，结果缓存避免重复探测
4. **密钥管理：** 通过 SecretStore 的 4 层密钥解析和 Fernet 加密保护 API 密钥
5. **本地模型：** LocalModelManager 管理 llama.cpp 服务生命周期
6. **插件扩展：** 支持通过插件目录和 `register_plugin_provider()` 动态扩展 Provider
7. **能力基线：** ExpectedCapabilityRegistry 提供探测 fallback 和偏差检测
8. **向后兼容：** 自动迁移 CoPaw 旧配置到 QwenPaw 新命名

**内置 Provider 覆盖：**
- OpenAI / Anthropic / Google Gemini 等主流商业 API
- Ollama / LM Studio 等本地模型服务
- DashScope / ModelScope / 智谱 等国内平台
- OpenRouter 聚合服务

**最佳实践：**
- 生产环境使用环境变量配置主密钥
- 根据场景选择合适的 Provider（性能/成本/隐私）
- 本地模型优先 Ollama，资源占用更低
- 自定义 Provider 通过 JSON 配置而非代码修改

---

## 15. 关键文件索引

| 组件 | 文件路径 |
|------|----------|
| Provider 基类 | `src/qwenpaw/providers/provider.py:137` |
| ModelInfo | `src/qwenpaw/providers/provider.py:22` |
| ExtendedModelInfo | `src/qwenpaw/providers/provider.py:54` |
| ProviderInfo | `src/qwenpaw/providers/provider.py:70` |
| ProviderManager | `src/qwenpaw/providers/provider_manager.py:720` |
| 本地模型管理 | `src/qwenpaw/local_models/manager.py:41` |
| Llama.cpp 后端 | `src/qwenpaw/local_models/llamacpp.py:43` |
| 下载控制器 | `src/qwenpaw/local_models/download_manager.py:253` |
| SecretStore | `src/qwenpaw/security/secret_store.py` |
| 能力基线注册表 | `src/qwenpaw/providers/capability_baseline.py` |
| 插件 Provider 注册 | `src/qwenpaw/providers/provider_manager.py:1632` |
| CoPaw 迁移 | `src/qwenpaw/providers/provider_manager.py:1382` |
| OpenAI Provider | `src/qwenpaw/providers/openai_provider.py` |
| Ollama Provider | `src/qwenpaw/providers/ollama_provider.py` |
| Anthropic Provider | `src/qwenpaw/providers/anthropic_provider.py` |
| Gemini Provider | `src/qwenpaw/providers/gemini_provider.py` |

---

## 16. OllamaProvider 详解

**源码路径**: `src/qwenpaw/providers/ollama_provider.py`

OllamaProvider 继承自 OpenAIProvider，复用 OpenAI 兼容 API，通过 URL 规范化适配 Ollama 的端点。

### 16.1 类定义

```python
# src/qwenpaw/providers/ollama_provider.py:12
class OllamaProvider(OpenAIProvider):
    """Provider implementation for Ollama local LLM hosting platform."""
```

### 16.2 核心方法

| 方法 | 行号 | 说明 |
|------|------|------|
| `_normalize_base_url()` | 15 | 规范化 base_url（去除 /v1 后缀） |
| `_openai_compatible_base_url()` | 25 | 返回 OpenAI 兼容的 base_url |
| `model_post_init()` | 32 | 初始化，检测 OLLAMA_HOST 环境变量 |
| `update_config()` | 40 | 更新配置时重新规范化 URL |
| `_client()` | 45 | 创建 AsyncOpenAI 客户端 |
| `check_model_connection()` | 50 | 检查特定模型是否可用 |
| `get_chat_model_instance()` | 60 | 获取聊天模型实例 |

### 16.3 URL 规范化

```python
# src/qwenpaw/providers/ollama_provider.py:16
@staticmethod
def _normalize_base_url(base_url: str) -> str:
    """规范化 base_url，去除末尾 /v1

    Ollama 服务器 URL 格式：
    - 本地: http://127.0.0.1:11434
    - 自定义: OLLAMA_HOST 环境变量指定

    OpenAI 兼容 URL 格式：
    - API 端点: http://127.0.0.1:11434/v1/chat/completions

    规范化流程：
    1. 去除末尾斜杠
    2. 如果以 /v1 结尾，去除 /v1（兼容用户误填的 OpenAI 格式）
    """
    normalized_base_url = (base_url or "").rstrip("/")
    if normalized_base_url.endswith("/v1"):
        normalized_base_url = normalized_base_url[:-3].rstrip("/")
    return normalized_base_url

# 示例：
# "http://localhost:11434/v1" → "http://localhost:11434"
# "http://localhost:11434/" → "http://localhost:11434"
# "http://localhost:11434" → "http://localhost:11434"

def _openai_compatible_base_url(self) -> str:
    """返回 OpenAI 兼容的 base_url，加上 /v1"""
    return self._normalize_base_url(self.base_url) + "/v1"
```

**为什么需要双重转换？**

1. 用户可能配置 Ollama URL 为 `http://localhost:11434/v1`（误填 OpenAI 格式）
2. `_normalize_base_url` 去除 `/v1` 得到 Ollama 服务器基础 URL
3. `_openai_compatible_base_url` 重新加上 `/v1` 得到 OpenAI 兼容端点

这样即使用户填错格式，也能正常工作。

### 16.4 客户端创建

```python
# src/qwenpaw/providers/ollama_provider.py:45
def _client(self, timeout: float = 5) -> AsyncOpenAI:
    return AsyncOpenAI(
        base_url=self._openai_compatible_base_url(),  # 自动添加 /v1
        api_key=self.api_key,
        timeout=timeout,
    )
```

### 16.5 模型检查

```python
# src/qwenpaw/providers/ollama_provider.py:51
async def check_model_connection(
    self,
    model_id: str,
    timeout: float = 5,
) -> tuple[bool, str]:
    """检查特定模型是否可达/可用

    流程：
    1. 调用 fetch_models() 获取 Ollama 服务器上所有可用模型
    2. 检查 model_id 是否在列表中
    3. 返回 (True, "") 如果存在，否则 (False, 错误信息)
    """
    models = await self.fetch_models(timeout=timeout)
    if any(model.id == model_id for model in models):
        return True, ""
    return False, f"Model '{model_id}' not found"
```

### 16.6 model_post_init 初始化

```python
# src/qwenpaw/providers/ollama_provider.py:33
def model_post_init(self, __context: Any) -> None:
    """初始化后处理，设置默认 base_url

    优先级：
    1. 已有 base_url（用户配置）
    2. OLLAMA_HOST 环境变量
    3. 默认 http://127.0.0.1:11434
    """
    if not self.base_url:
        self.base_url = (
            os.environ.get("OLLAMA_HOST") or "http://127.0.0.1:11434"
        )
    self.base_url = self._normalize_base_url(self.base_url)
```

### 16.7 获取聊天模型实例

```python
# src/qwenpaw/providers/ollama_provider.py:62
def get_chat_model_instance(self, model_id: str) -> ChatModelBase:
    """返回 Ollama 聊天模型实例

    使用 OpenAIChatModelCompat 兼容层，因为 Ollama 提供 OpenAI 兼容 API。
    """
    from .openai_chat_model_compat import OpenAIChatModelCompat

    return OpenAIChatModelCompat(
        model_name=model_id,
        stream=True,
        api_key=self.api_key,
        stream_tool_parsing=False,
        client_kwargs={"base_url": self._openai_compatible_base_url()},
        generate_kwargs=self.get_effective_generate_kwargs(model_id),
    )
```

### 16.8 Ollama 特性

**Ollama 特点**：
- 本地运行，无需网络
- 自动发现本地模型
- OpenAI 兼容 API (`/v1/chat/completions`)
- 支持多模态模型（如 llava）

**环境变量**：
```bash
OLLAMA_HOST=http://localhost:11434  # 自定义 Ollama 主机
```

**支持的模型格式**：
```bash
# 格式
model_name  # 例如 "llama3.1:8b"

# 多模态模型
llava:7b
llava:13b
```

---

## 来自 Java 的你

### 核心概念对照

| Java | Python / QwenPaw | 说明 |
|------|-------------------|------|
| JPA Provider (Hibernate/EclipseLink) | Model Provider (OpenAI/Ollama) | JPA 用 Provider 抽象不同 ORM 实现，QwenPaw 用 Provider 抽象不同 LLM API |
| `DriverManager` / `DataSource` | `ProviderManager` | Java 用 DriverManager 管理 JDBC 驱动，QwenPaw 用 ProviderManager 管理模型供应者（同样有单例模式） |
| `@Entity` + `@Table` | `ModelInfo` / `ProviderInfo` (Pydantic) | JPA 用注解定义实体映射，QwenPaw 用 Pydantic BaseModel 定义数据模型（含类型验证） |
| Connection Pool (HikariCP) | 连接管理 (`AsyncOpenAI` client) | Java 用连接池管理数据库连接，QwenPaw 用 AsyncOpenAI 客户端管理 API 连接（无池化） |
| Hibernate Dialect | Provider 抽象层 | Hibernate Dialect 适配不同数据库方言，Provider 抽象层适配不同 LLM API 的调用方式 |

### 关键差异

JPA Provider 管理的是 ORM 映射（对象-关系映射），QwenPaw Provider 管理的是 LLM API 调用（模型-请求映射）。Java 开发者需要注意：ProviderManager 的 `activate_model()` 类似于 `DataSource.getConnection()`，但这里不是获取连接而是设置全局活跃模型；`check_connection()` 类似于 JDBC 的连接测试，但返回的是 `(bool, str)` 元组而非抛异常。密钥管理方面，Java 通常用 JCEKS 密钥库，QwenPaw 用 Fernet 对称加密存储在文件系统。

---

## 实战演练

### 基础练习（⭐）
**目标**: 使用 CLI 或 API 列出当前系统所有已注册的 Provider 和可用模型
**提示**: 通过 `GET /api/providers` 端点或直接检查 `ProviderManager` 实例的 `builtin_providers` 和 `custom_providers` 字典
**参考思路**: `ProviderManager` 是全局单例，维护了 `builtin_providers`（24 个内置 Provider）和 `custom_providers`（用户自定义）两个字典。每个 Provider 实例的 `models` 属性包含该 Provider 下可用的 `ModelInfo` 列表。遍历这些字典，打印 Provider ID、名称及其下的模型 ID 列表即可。也可以查看 `~/.qwenpaw/secrets/providers/` 目录结构了解磁盘存储。

### 进阶练习（⭐⭐⭐）
**目标**: 追踪 `activate_model()` 的完整流程，从用户选择到模型实例创建
**提示**: 从 `ProviderManager.activate_model()` 开始，经过 `_normalize_provider_id()` → `get_provider()` → `has_model()` → `save_active_model()` → `maybe_probe_multimodal()`
**参考思路**: `activate_model()` 首先规范化 Provider ID（大小写、空格处理），然后验证 Provider 存在且包含目标模型。通过后创建 `ModelSlotConfig` 并持久化到磁盘（`save_active_model`）。最后调度后台任务探测模型的多模态能力（如未知）。注意 `activate_model` 只设置活跃模型配置，实际的模型实例创建发生在 Agent 初始化时的 `create_model_and_formatter()` 调用中——通过 `Provider.get_chat_model_instance()` 获取。

### 挑战练习（⭐⭐⭐⭐⭐）
**目标**: 实现一个自定义 Provider 类（继承 OpenAIProvider），支持一个新的 API 端点
**提示**: 参照 `OllamaProvider` 的实现模式——继承 `OpenAIProvider`，重写 `_normalize_base_url()`、`_openai_compatible_base_url()` 和 `get_chat_model_instance()`
**参考思路**: (1) 创建新类继承 `OpenAIProvider`，在 `model_post_init` 中设置默认 `base_url`；(2) 重写 `_normalize_base_url()` 处理目标 API 的 URL 格式；(3) 在 `get_chat_model_instance()` 中使用 `OpenAIChatModelCompat` 传入自定义的 `base_url` 和 `generate_kwargs`；(4) 在 `config.json` 的自定义 Provider 中注册，或通过 `ProviderManager.add_custom_provider()` 添加。关键是要确保新端点的请求/响应格式与 OpenAI Chat Completions API 兼容。

---

## 知识检查

1. ProviderManager 采用什么设计模式管理所有 Provider 实例？它如何保证全局唯一性？

2. 当调用 `activate_model()` 激活一个模型时，系统会依次执行哪些步骤？如果模型不在 Provider 的模型列表中会发生什么？

3. OllamaProvider 继承自 OpenAIProvider，它的 `_normalize_base_url` 和 `_openai_compatible_base_url` 两个方法分别解决什么问题？为什么需要双重转换？

---

## 延伸阅读

- [11-Model系统与LLM提供商](11-Model系统与LLM提供商.md) -- Provider 系统的上层调用方，理解模型选择如何传递到 Provider 层
- [85-模型探测与能力检测](85-模型探测与能力检测.md) -- 多模态探测的完整机制，包含探测数据和偏差检测
