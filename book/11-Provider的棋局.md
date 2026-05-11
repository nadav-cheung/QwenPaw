# 第 11 章：Provider 的棋局——策略模式与抽象层

```
卷二：理解设计
[9] 源码地图 -> [10] Agent身世 -> [11] Provider棋局 <- you are here
```

第 6 章我们跟 LLM 调用走了一遍，知道了 Provider 是模型的"通讯录"。这一章我们理解它的设计——为什么用抽象基类？6 种 Provider 实现有什么差异？策略模式怎么让切换模型只改配置不改代码？

---

## 问题

OpenAI 用一种 API 格式，Anthropic 用另一种，Gemini 又是一种。Ollama 和 LM Studio 是本地模型。OpenRouter 是聚合平台。QwenPaw 怎么用一套代码支持所有这些不同的 API？

## 术语其实很简单

> **术语：策略模式（Strategy Pattern）**
> 想象旅行——你可以坐飞机、火车、汽车。目的地一样，但出行策略不同。策略模式就是"定义统一接口，多种实现各自完成"的设计。`Provider` 定义"连接、发现、检查、创建"四个操作，每种 Provider 用自己的方式实现。

> **术语：多态反序列化（Polymorphic Deserialization）**
> 想象快递分拣——看到地址写"北京"走北京通道，写"上海"走上海通道。反序列化时，根据 JSON 里的 `id` 或 `chat_model` 字段选择正确的 Provider 类来构建对象。

## 探索

### Provider 的继承树

```
ProviderInfo (Pydantic BaseModel -- 数据模型)
  |
  +-- Provider (ProviderInfo + ABC -- 策略接口)
        |
        +-- OpenAIProvider       # OpenAI SDK + 兼容端点
        |     |
        |     +-- OllamaProvider  # 本地：继承 OpenAI，改 URL 和检查
        |     +-- LMStudioProvider # 本地：继承 OpenAI，只改检查
        |
        +-- AnthropicProvider    # Anthropic SDK
        +-- GeminiProvider       # Google GenAI SDK
        +-- OpenRouterProvider   # 独立实现，聚合多个上游
```

关键观察：**大部分 Provider 继承 OpenAIProvider**——因为很多服务兼容 OpenAI API（DashScope、DeepSeek、Kimi、SiliconFlow 都是）。只有 Anthropic、Gemini、OpenRouter 需要独立实现。

### 四个抽象方法，六种实现

`Provider` 定义了四个抽象方法。每种 Provider 的实现策略：

| 方法 | OpenAI | Anthropic | Gemini | Ollama |
|---|---|---|---|---|
| `check_connection` | `client.models.list()` | `client.models.list()` | `client.aio.models.list()` | 继承 OpenAI |
| `fetch_models` | `client.models.list()` | `client.models.list()` | 异步迭代 | 继承 OpenAI |
| `check_model_connection` | `chat.completions.create` ping | `messages.create` ping | `generate_content_stream` ping | 检查模型是否在列表中 |
| `get_chat_model_instance` | `OpenAIChatModelCompat` | `AnthropicChatModel` | `GeminiChatModel` | `OpenAIChatModelCompat` |

关键差异在 `check_model_connection`：OpenAI/Anthropic/Gemini 都发一个 ping 消息看模型是否响应，但 Ollama 只检查模型名是否在列表中——因为本地模型不一定能处理任意聊天消息。

### 为什么 Ollama 继承 OpenAI？

Ollama 暴露了 OpenAI 兼容的 `/v1` 端点。`OllamaProvider` 继承 `OpenAIProvider`，只重写了：
- URL 规范化（去掉/加回 `/v1`）
- `check_model_connection`（列表检查代替 ping）
- `stream_tool_parsing=False`（本地模型不支持流式工具解析）

`LMStudioProvider` 更极端——只有 20 行代码，完全继承 OpenAI，只改了 `check_model_connection`。

### OpenRouter——元 Provider

OpenRouter 不是模型服务，是模型服务的聚合器。它的独特之处：
- 模型 ID 用 `provider/model-name` 格式（如 `openai/gpt-4o`）
- 注入 `HTTP-Referer` 和 `X-Title` 头用于应用识别
- 支持 `ExtendedModelInfo`（包含定价、模态等额外信息）
- 提供 `filter_models()` 按提供商、模态、价格过滤

### generate_kwargs 的两级合并

每个 Provider 有 `generate_kwargs`（所有模型共享），每个 ModelInfo 也有自己的 `generate_kwargs`（特定模型覆盖）。`get_effective_generate_kwargs()` 用深度合并：

```python
def get_effective_generate_kwargs(self, model_id):
    for model in self.models + self.extra_models:
        if model.id == model_id and model.generate_kwargs:
            return self._deep_merge(
                self.generate_kwargs,       # Provider 级别
                model.generate_kwargs,       # 模型级别覆盖
            )
    return dict(self.generate_kwargs)  # 没有覆盖，返回副本
```

Ollama 和 LMStudio 设置 `generate_kwargs={"max_tokens": None}`——本地模型通常没有 Token 限制。

### 多态反序列化——从 JSON 到正确的类

`_provider_from_data()` 根据数据选择正确的 Provider 类：

```python
def _provider_from_data(self, data):
    if data["id"] == "openrouter":    return OpenRouterProvider.model_validate(data)
    if data["id"] == "anthropic" or chat_model == "AnthropicChatModel":
        return AnthropicProvider.model_validate(data)
    if data["id"] == "gemini" or chat_model == "GeminiChatModel":
        return GeminiProvider.model_validate(data)
    if data["id"] == "ollama":        return OllamaProvider.model_validate(data)
    return OpenAIProvider.model_validate(data)  # 默认
```

这确保了从磁盘加载配置时，每种 Provider 都被反序列化为正确的类型。

## 实验

在源码中对比不同 Provider 的实现：

1. 打开 `src/qwenpaw/providers/openai_provider.py`，搜索 `get_chat_model_instance`
2. 打开 `src/qwenpaw/providers/anthropic_provider.py`，搜索 `get_chat_model_instance`
3. 打开 `src/qwenpaw/providers/lmstudio_provider.py`，看它有多简单
4. 打开 `src/qwenpaw/providers/provider_manager.py`，搜索 `_provider_from_data`

预期结果：OpenAI 和 Anthropic 的 `get_chat_model_instance` 返回不同的模型类；LMStudioProvider 只有 20 行代码。

## 工程权衡

### 为什么用继承而非为每个 Provider 写独立类？

Ollama 和 LMStudio 兼容 OpenAI API——如果为它们写独立实现，大部分代码是重复的。继承 `OpenAIProvider` 只需重写差异部分。代价是继承树变深了，但省了大量重复代码。

### 为什么 OpenRouter 不继承 OpenAI？

OpenRouter 虽然底层用 OpenAI 兼容 API，但它的模型发现、过滤、定价信息等逻辑完全不同。强行继承 `OpenAIProvider` 会导致大量重写，不如独立实现更清晰。

## 常见误区

> **误区：新增 Provider 需要改很多地方？**
>
> 如果新 Provider 兼容 OpenAI API，只需要在 `provider_manager.py` 里加一个 `OpenAIProvider(...)` 实例。如果不兼容，需要新建一个 Provider 类，实现四个抽象方法，然后在 `_provider_from_data()` 里加一个路由分支。不管哪种情况，Agent 的代码完全不用改——策略模式隔离了变化。

## 动手环节

**任务**：对比 OpenAI 和 Gemini 的 `check_model_connection` 实现。

**步骤**：
1. 打开 `src/qwenpaw/providers/openai_provider.py`，搜索 `check_model_connection`
2. 打开 `src/qwenpaw/providers/gemini_provider.py`，搜索 `check_model_connection`
3. 对比两者的 API 调用方式

**预期输出**：OpenAI 用 `chat.completions.create` 发 ping；Gemini 用 `generate_content_stream` 发 ping。

**自检**：
- [ ] 理解了 Provider 继承树和四种抽象方法
- [ ] 知道 Ollama/LMStudio 继承 OpenAI 因为 API 兼容
- [ ] 知道 `_provider_from_data()` 做多态反序列化

---

Provider 的策略模式清楚了。下一章我们看 Channel 的变装——17 个聊天平台怎么通过适配器模式共享同一套 Agent 逻辑？
