# 第十二章 Channel 的变装——适配器模式

```
浏览器 ─→ HTTP ─→ Runner ─→ Agent ─→ Prompt ─→ ReAct ─→ LLM ─→ Tool ─→ 响应归途
                                                                      |
                            Channel 在哪里？                           |
                            ┌──────────────────┐                      |
                            │  ChannelManager  │ ←── 管理所有 Channel  |
                            │  ┌────────────┐  │                      |
                            │  │ Console    │  │ ←── 终端              |
                            │  │ Telegram   │  │ ←── 外部平台          |
                            │  │ DingTalk   │  │                      |
                            │  │ Feishu     │  │                      |
                            │  │ Discord    │  │                      |
                            │  │ ...x10     │  │                      |
                            │  └────────────┘  │                      |
                            └──────────────────┘
                                    你在这里
```

## 问题：同一个 Agent 怎么同时接入钉钉、飞书、Telegram、Discord？

你写好了一个 AI Agent。它在终端里跑得很好，能回答问题、调用工具、处理文件。

现在老板说：我们要把它接到钉钉上。下周再接飞书。下个月再接 Telegram。

问题来了。钉钉的消息格式是一个 JSON，里面有 `session_webhook`、`conversationId`、`senderNick`。飞书的消息格式又是另一个 JSON，里面有 `open_id`、`chat_id`、`message_id`。Telegram 的消息是一个 `Update` 对象，里面有 `chat_id`、`from_user`、`message_id`。

每个平台都有自己的一套：

- 消息接收方式（webhook、轮询、长连接）
- 消息格式（JSON 结构各不相同）
- 发送方式（HTTP API、SDK 调用）
- 会话标识（有的用聊天 ID，有的用用户 ID）
- 限制（消息长度、媒体大小、频率限制）

难道你要在 Agent 核心代码里写 15 个 `if platform == "dingtalk": ... elif platform == "feishu": ...`？

当然不是。QwenPaw 的答案是 Channel 系统——一个基于适配器模式的分层设计。

---

## 术语其实很简单

> **术语：适配器模式（Adapter Pattern）**
> 想象你有一个国标插头的充电器，但墙上的插座是美标的。你不需要重做充电器，只需要一个转换头。适配器模式就是这个转换头：它不改变核心功能（充电），只负责把一种接口转换成另一种接口。在 QwenPaw 里，Agent 只认识 `AgentRequest` 和 `AgentResponse`，而每个平台说的是不同的"语言"。Channel 就是翻译官，负责把平台特有的消息翻译成 Agent 认识的格式，再把 Agent 的回复翻译回平台能理解的格式。

> **术语：注册表模式（Registry Pattern）**
> 想象一本电话簿。你需要找"钉钉"的联系方式，翻开电话簿，按名字查到号码就能打过去。注册表模式就是这本电话簿：每个 Channel 在启动时把"我是谁"和"我的类"登记到注册表里。ChannelManager 需要创建某个平台的 Channel 时，查注册表就行，不需要知道具体的类名或文件路径。新增平台时，只要在注册表里加一条记录，其他代码一行都不用改。

---

## 探索：Channel 系统的五层设计

### 第一层：BaseChannel——适配器接口

`BaseChannel` 是所有 Channel 的基类，定义了一个 Channel 必须实现的契约。它位于 `src/qwenpaw/app/channels/base.py`。

这个基类做了两件事。第一，定义了一套所有子类必须遵守的接口。第二，实现了大量通用逻辑（消息渲染、防抖、批量合并、权限检查），让子类只关注平台特有的差异。

先看最核心的接口：

```python
class BaseChannel(ABC):
    channel: ChannelType          # 每个 Channel 有唯一标识

    def build_agent_request_from_native(self, native_payload) -> AgentRequest:
        """把平台原生消息转换为 Agent 能理解的请求"""
        raise NotImplementedError

    async def send(self, to_handle, text, meta=None):
        """把文本发到平台上"""
        raise NotImplementedError

    async def consume_one(self, payload):
        """从队列取一条消息，处理并发送回复"""
        ...

    def resolve_session_id(self, sender_id, channel_meta=None):
        """把平台的用户标识转换为会话 ID"""
        return f"{self.channel}:{sender_id}"
```

四个方法，一个完整的消息生命周期：

1. **消息进来**：平台消息到达，`build_agent_request_from_native()` 把它翻译成 `AgentRequest`
2. **找到会话**：`resolve_session_id()` 把平台的用户/聊天标识映射到统一的会话 ID
3. **处理消息**：`consume_one()` 把 `AgentRequest` 交给 Agent 处理
4. **发送回复**：`send()` 把 Agent 的回复翻译回平台格式并发出去

整个适配器的核心就是一个"翻译层"——把外部世界的多样性，消化在这一组方法里。

### 第二层：ConsoleChannel——最简单的适配器

理解一个设计模式，最好从最简单的实现开始。`ConsoleChannel` 在 `src/qwenpaw/app/channels/console/channel.py`，它只做一件事：把 Agent 的回复打印到终端。

看它怎么实现 `build_agent_request_from_native()`：

```python
def build_agent_request_from_native(self, native_payload):
    payload = native_payload if isinstance(native_payload, dict) else {}
    channel_id = payload.get("channel_id") or self.channel
    sender_id = payload.get("sender_id") or ""
    content_parts = payload.get("content_parts") or []
    content_parts = self._resolve_console_upload_refs(content_parts)
    meta = payload.get("meta") or {}
    session_id = self.resolve_session_id(sender_id, meta)
    request = self.build_agent_request_from_user_content(
        channel_id=channel_id,
        sender_id=sender_id,
        session_id=session_id,
        content_parts=content_parts,
        channel_meta=meta,
    )
    request.channel_meta = meta
    return request
```

它的"原生消息"就是一个简单的字典：`{"sender_id": "user1", "content_parts": [...], "meta": {...}}`。不需要处理 webhook、不需要解析加密签名、不需要下载远程文件——从字典里取值，拼成 `AgentRequest`，就完了。

发送更简单：

```python
async def send(self, to_handle, text, meta=None):
    if not self.enabled:
        return
    self._safe_print(f"Bot -> {to_handle}\n{text}\n")
```

`print()` 就是它的"发送 API"。终端没有消息长度限制，没有频率限制，不需要 HTML 格式化。

ConsoleChannel 告诉我们一个重要的事实：**一个 Channel 的最小实现只需要两个方法**——`build_agent_request_from_native()` 和 `send()`。其他所有逻辑都由基类处理。

### 第三层：TelegramChannel——真实世界的适配器

现在看一个真正复杂的适配器。`TelegramChannel` 在 `src/qwenpaw/app/channels/telegram/channel.py`，它要处理 Telegram Bot API 的所有复杂性。

先看消息接收。Telegram 不像终端那样由用户直接输入——它通过轮询（polling）从 Telegram 服务器拉取消息。`TelegramChannel` 在 `_build_application()` 里设置了一个消息处理器：

```
Telegram 服务器
    │
    │  Update 消息（包含 text, photo, document, video...）
    │
    ▼
handle_message()
    │
    ├─ _build_content_parts_from_message()
    │      │
    │      ├─ 解析 text（去掉 @mention）
    │      ├─ 下载 photo → 本地文件 → ImageContent
    │      ├─ 下载 document → 本地文件 → FileContent
    │      ├─ 下载 video → 本地文件 → VideoContent
    │      └─ 下载 audio → 本地文件 → AudioContent
    │
    ├─ _message_meta()
    │      └─ 提取 chat_id, user_id, is_group, message_id
    │
    ├─ _check_allowlist()  → 权限检查
    ├─ _check_group_mention() → 群聊 @机器人检查
    │
    └─ self._enqueue(native)  → 放入队列等待处理
```

注意 `native` 的结构：

```python
native = {
    "channel_id": self.channel,       # "telegram"
    "sender_id": sender_id,           # Telegram 用户 ID
    "content_parts": content_parts,   # [TextContent, ImageContent, ...]
    "meta": meta,                     # {chat_id, user_id, is_group, ...}
}
```

这和 ConsoleChannel 的 `native` 结构一模一样。**不同的平台消息，在进入队列之前，已经被各自的 Channel 转换成了统一的结构。**

然后看 `build_agent_request_from_native()`：

```python
def build_agent_request_from_native(self, native_payload):
    payload = native_payload if isinstance(native_payload, dict) else {}
    channel_id = payload.get("channel_id") or self.channel
    sender_id = payload.get("sender_id") or ""
    content_parts = payload.get("content_parts") or []
    meta = payload.get("meta") or {}
    session_id = self.resolve_session_id(sender_id, meta)
    user_id = str(meta.get("user_id") or sender_id)
    request = self.build_agent_request_from_user_content(...)
    request.user_id = user_id
    request.channel_meta = meta
    return request
```

和 ConsoleChannel 的几乎一样。**这就是适配器模式的威力：复杂的平台差异（下载文件、解析消息实体、轮询连接）被消化在 `native` 构建阶段，后续流程完全统一。**

再看发送。Telegram 的 `send()` 要处理消息长度限制（4096 字符）、HTML 格式化、代理、失败重试：

```python
async def send(self, to_handle, text, meta=None):
    chat_id = meta.get("chat_id") or to_handle
    self._stop_typing(chat_id)
    chunks = self._chunk_text(text)       # 拆成长度合规的片段
    for chunk in chunks:
        html_chunk = markdown_to_telegram_html(chunk)
        try:
            await bot.send_message(chat_id=chat_id, text=html_chunk,
                                   parse_mode=ParseMode.HTML)
        except BadRequest:
            plain_chunk = html.unescape(re.sub(r"<[^>]+>", "", html_chunk))
            await bot.send_message(chat_id=chat_id, text=plain_chunk)
```

对比 ConsoleChannel 的 `send()`，差异一目了然：

| | ConsoleChannel | TelegramChannel |
|---|---|---|
| 目标 | 终端 stdout | Telegram Bot API |
| 消息限制 | 无 | 4096 字符/条 |
| 格式化 | 纯文本 | HTML（失败时降级为纯文本） |
| 发送方式 | `print()` | `bot.send_message()` |
| 媒体处理 | 打印 URL | 下载/上传文件 |
| 额外功能 | 无 | 打字指示器、自动重连 |

**接口相同（`send()`），实现天差地别。** 这正是适配器模式的核心。

### 第四层：消息格式转换——双向翻译

Channel 作为一个"翻译层"，它的核心工作是在两种格式之间来回转换。理解这个双向翻译，就理解了整个 Channel 系统。

```
外部平台                         Channel 翻译层                      Agent 内部
─────────                       ──────────────                    ──────────

Telegram Update                                                  AgentRequest
  ├─ message.text ──────→ TextContent ──────→ Message.content ──→ input[0]
  ├─ message.photo ─────→ 下载文件 ──────→ ImageContent ──────→ input[0]
  ├─ message.document ──→ 下载文件 ──────→ FileContent ───────→ input[0]
  └─ chat.id ───────────→ meta ──────→ channel_meta ─────────→ channel_meta

AgentResponse
  ├─ output[-1].content ──→ TextContent ──→ HTML 格式化 ──────→ bot.send_message()
  ├─ output[-1].content ──→ ImageContent ─→ 上传文件 ────────→ bot.send_photo()
  └─ output[-1].content ──→ FileContent ──→ 上传文件 ────────→ bot.send_document()
```

进来的方向（平台 → Agent）：

1. **平台原生格式**：每个平台有自己的消息结构（Telegram 的 `Update`、钉钉的 webhook JSON、终端的字典）
2. **Content Parts**：Channel 把原生消息解析成统一的内容类型列表：`TextContent`、`ImageContent`、`FileContent` 等
3. **AgentRequest**：通过 `build_agent_request_from_user_content()` 把内容列表包装成 Agent 能处理的请求

出去的方向（Agent → 平台）：

1. **AgentResponse**：Agent 输出 `AgentResponse`，里面有 `Message` 列表
2. **Content Parts**：通过 `_message_to_content_parts()` 从 `Message` 中提取内容列表
3. **平台原生格式**：Channel 把内容列表转换成平台能接受的格式（HTML 文本、文件上传等），调用平台 API 发送

这个双向翻译的设计，让 Agent 完全不需要知道自己运行在哪个平台上。

### 第五层：ChannelManager——注册表和路由

有了 15 种 Channel 实现，谁来管理它们？答案是 `ChannelManager`，位于 `src/qwenpaw/app/channels/manager.py`。

```
                         ChannelManager
                         ┌─────────────────────────────────┐
                         │                                 │
    配置文件 ──→ from_config() ──→ channels: [BaseChannel] │
                         │         ├─ ConsoleChannel       │
                         │         ├─ TelegramChannel      │
                         │         ├─ DingTalkChannel      │
                         │         └─ ...                  │
                         │                                 │
    消息到达 ──→ enqueue(channel_id, payload)              │
                         │         │                       │
                         │         ▼                       │
                         │  UnifiedQueueManager            │
                         │    ├─ 按 (channel, session,     │
                         │    │  priority) 分队列          │
                         │    └─ 消费者循环                 │
                         │         │                       │
                         │         ▼                       │
                         │  channel.consume_one(payload)   │
                         │                                 │
                         └─────────────────────────────────┘
```

ChannelManager 的职责：

1. **创建 Channel**：根据配置文件，从注册表中查找对应的 Channel 类，创建实例
2. **管理队列**：每个 Channel 有自己的消息队列，由 `UnifiedQueueManager` 统一管理
3. **消息路由**：当消息到达时，根据 `channel_id` 找到对应的 Channel，放入队列
4. **生命周期管理**：启动、停止、重启、健康检查

注册表本身在 `src/qwenpaw/app/channels/registry.py`：

```python
_BUILTIN_SPECS = {
    "imessage":   (".imessage",  "IMessageChannel"),
    "discord":    (".discord_",  "DiscordChannel"),
    "dingtalk":   (".dingtalk",  "DingTalkChannel"),
    "feishu":     (".feishu",    "FeishuChannel"),
    "qq":         (".qq",        "QQChannel"),
    "telegram":   (".telegram",  "TelegramChannel"),
    "console":    (".console",   "ConsoleChannel"),
    # ... 还有更多
}
```

一个字典，把平台的字符串标识映射到模块名和类名。`get_channel_registry()` 加载所有内置 Channel，再加上从 `custom_channels/` 目录发现的用户自定义 Channel。

#### 内置 Channel 速查表

| Channel 标识 | 类名 | 消息接收方式 | 特色能力 |
|-------------|------|------------|---------|
| `console` | ConsoleChannel | HTTP 路由 | 最简实现，200 行 |
| `telegram` | TelegramChannel | 长轮询 | 打字指示器、HTML 格式化、自动重连 |
| `dingtalk` | DingTalkChannel | Webhook | OAuth 回调、会话 Webhook |
| `feishu` | FeishuChannel | Webhook | 事件订阅、卡片消息 |
| `discord` | DiscordChannel | Gateway WebSocket | 富文本 Embed、Slash 命令 |
| `qq` | QQChannel | WebSocket | QQ 频道协议适配 |
| `imessage` | IMessageChannel | 本地数据库 | macOS iMessage 桥接 |
| `wechat_mp` | WechatMPChannel | Webhook | 微信公众号消息 |
| `slack` | SlackChannel | WebSocket | Block Kit 格式化 |
| `http_api` | HttpApiChannel | HTTP POST | 通用 REST 接入 |
| `mqtt` | MqttChannel | MQTT 订阅 | IoT 场景、低带宽 |
| `grpc` | GrpcChannel | gRPC 流 | 高性能 RPC 场景 |

（实际内置数量更多，以上为主要的 12 种。）

每个 Channel 在注册后还需要 `from_config()` 工厂方法创建实例。以 Telegram 为例，配置中写了 `channels.telegram.enabled = true` 时，ChannelManager 做的就是：

1. 从注册表查到 `"telegram"` 对应 `TelegramChannel` 类
2. 调用 `TelegramChannel.from_config(process, config)` 创建实例
3. 把实例加入 `self.channels` 列表
4. 调用 `start()` 启动 Telegram 的轮询

**新增一个平台，整个过程就是：写一个继承 `BaseChannel` 的类，在注册表里加一行。** ChannelManager 不需要改，Agent 不需要改，Runner 不需要改。

### 自定义渠道发现

注册表不仅包含内置渠道，还支持用户自定义渠道。`_discover_custom_channels()`（registry.py 第 85 行）从 `custom_channels/` 目录自动发现并加载自定义渠道类：

```python
def _discover_custom_channels() -> dict[str, type[BaseChannel]]:
    for path in sorted(CUSTOM_CHANNELS_DIR.iterdir()):
        # 加载 .py 文件或带 __init__.py 的目录
        mod = importlib.import_module(name)
        # 查找 BaseChannel 子类，以 channel 属性为键注册
```

自定义渠道模块还可以通过 `register_app_routes(app)` 函数注册额外的 FastAPI HTTP 路由（如 webhook 端点），系统会自动调用并验证路由前缀。

### 命令优先级路由：CommandRegistry

ChannelManager 内部有一个 `CommandRegistry`（`channels/command_registry.py`），它管理命令到优先级的映射，用于 `UnifiedQueueManager` 的优先级队列路由：

```python
class CommandRegistry:
    _priority_names = {
        "critical": 0,   # 紧急控制命令（如 /stop）
        "high": 10,      # 高优先级（如 /daemon status）
        "normal": 20,    # 普通消息（默认）
        "low": 30,       # 低优先级批处理
    }
```

当消息到达时，ChannelManager 用 `_command_registry.get_priority_level(query)` 查询优先级，然后路由到 UnifiedQueueManager 的对应优先级队列。`is_control_command()` 方法还用于判断消息是否为控制命令——控制命令可以绕过 TaskTracker 的防重入检查，确保 `/stop` 等紧急操作始终能立即执行。

---

## 实验：对比两个 Channel 的 process 路径

让我们追踪同一条消息在 ConsoleChannel 和 TelegramChannel 中的完整旅程，看看它们的相同与不同。

### ConsoleChannel 的路径

```
用户在终端输入 "你好"
    │
    ▼
POST /console/chat → AgentApp 路由
    │
    ▼
构建 native = {
    "channel_id": "console",
    "sender_id": "user",
    "content_parts": [TextContent(text="你好")],
    "meta": {"session_id": "console:user"}
}
    │
    ▼
stream_one(native)              ← ConsoleChannel 自己的流式处理
    │
    ├─ build_agent_request_from_native(native)
    │       → AgentRequest(session_id="console:user", ...)
    │
    ├─ self._process(request)   ← 调用 Agent 处理
    │       → Event 流
    │
    ├─ event.output → _message_to_content_parts()
    │       → [TextContent(text="你好！有什么...")]
    │
    └─ _print_parts(parts)      ← 打印到终端
```

### TelegramChannel 的路径

```
Telegram 服务器推送 Update
    │
    ▼
handle_message()                ← 轮询回调
    │
    ├─ _build_content_parts_from_message(update)
    │       → 解析文本、下载图片、提取元数据
    │
    ├─ _check_allowlist()       ← 权限检查
    ├─ _check_group_mention()   ← 群聊 @机器人检查
    │
    └─ self._enqueue(native)    ← 放入 ChannelManager 的队列
            │
            ▼
        consume_one(native)      ← 从队列取出
            │
            ├─ build_agent_request_from_native(native)
            │       → AgentRequest(session_id="telegram:123456", ...)
            │
            ├─ self._process(request)
            │       → Event 流
            │
            ├─ event → _message_to_content_parts()
            │       → [TextContent(text="你好！有什么...")]
            │
            └─ send_content_parts(to_handle, parts)
                    │
                    ├─ TextContent → markdown_to_telegram_html()
                    │       → bot.send_message(chat_id, html_text)
                    │
                    └─ ImageContent → _send_media_value()
                            → bot.send_photo(chat_id, file)
```

### 共性与差异

**完全相同的部分**：
- `build_agent_request_from_native()` 的逻辑几乎一模一样
- `_process(request)` 调用完全相同——都是把 `AgentRequest` 交给同一个 Agent
- `_message_to_content_parts()` 从 Event 提取内容的逻辑继承自基类
- 权限检查、防抖、批量合并等通用逻辑都在基类中

**截然不同的部分**：
- **消息接收**：Console 由 HTTP 路由触发，Telegram 由轮询回调触发
- **媒体处理**：Console 直接引用 URL，Telegram 需要先下载到本地再重新上传
- **发送方式**：Console 打印到终端，Telegram 调用 Bot API
- **格式化**：Console 纯文本，Telegram HTML（含降级）
- **额外状态**：Telegram 维护打字指示器、重连逻辑、消息分片

**关键洞察**：相同部分占代码量的 70% 以上，由 `BaseChannel` 提供。不同部分占不到 30%，由子类实现。这就是适配器模式带来的代码复用——不是完美复用，但对于 15+ 种平台来说，这个复用率已经极其有价值。

---

## 工程权衡：抽象的代价与回报

Channel 系统的设计并非没有代价。让我们诚实地审视这些权衡。

### 抽象的代价

**基类的复杂度。** `BaseChannel` 有 1300 多行代码。它包含了防抖逻辑（处理"图片先到、文字后到"的场景）、消息合并（处理"连续发送多条消息"的场景）、渲染器（控制工具消息、思考过程的显示）、权限检查（白名单、群聊策略）、以及 TaskTracker 集成。

一个子类的开发者，需要理解这套基类才能正确地实现自己的 Channel。这不是一个轻松的任务。当你看到 `_apply_no_text_debounce()`、`merge_native_items()`、`_consume_one_request()` 这些方法时，你需要理解它们的调用顺序和协作关系。

**间接层带来的调试困难。** 当 Telegram 的消息处理出 bug 时，你需要在轮询回调、消息解析、队列系统、基类消费循环、事件处理之间来回跳转。问题可能在任何一层。

**性能开销。** 每条消息都要经过"原生格式 → 中间字典 → AgentRequest"的转换。对于高频场景（比如 MQTT 或 WebSocket），这个转换开销并非免费。

### 抽象的回报

**一个平台，一个类。** 接入新平台时，你只需要写一个继承 `BaseChannel` 的类，实现 3-5 个方法。不需要改 Agent 代码，不需要改 Runner 代码，不需要改 HTTP 路由。

**一致的测试和运维接口。** 所有 Channel 都有 `health_check()`、`start()`、`stop()`、`clone()` 方法。ChannelManager 可以用同一套逻辑管理所有平台——统一重启、统一健康检查、统一队列管理。

**渐进式复杂度。** ConsoleChannel 只有 200 行有效代码。TelegramChannel 大约 800 行。DingTalkChannel 因为需要处理 webhook 回调和 OAuth，可能更复杂。但不管多复杂，它们的"对外接口"都是一样的——对 ChannelManager 来说，它们都是 `BaseChannel`。

### 这个抽象值得吗？

如果你只需要支持一个平台，不值得。直接写 `if platform == "telegram": ...` 更简单、更快、更容易理解。

但 QwenPaw 支持 15 个以上的平台。如果不用适配器模式，每新增一个平台，你需要在消息接收、格式转换、发送逻辑的每个分支点加一个 `elif`。15 个平台意味着 15 路分支，每一路都有自己的一套格式和 API。维护这种代码的成本，远远高于理解一个 1300 行的基类。

**适配器模式不是免费的午餐，但它是一顿值得付费的午餐。** 尤其是当平台数量超过 5 个的时候。

---

## 动手：对比两个 Channel 实现

这个练习帮你验证本文学到的知识。你需要对比 ConsoleChannel 和 TelegramChannel 的源码。

### 步骤一：找到源码文件

打开以下两个文件：

- `src/qwenpaw/app/channels/console/channel.py` —— ConsoleChannel
- `src/qwenpaw/app/channels/telegram/channel.py` —— TelegramChannel

### 步骤二：对比 build_agent_request_from_native()

在两个文件中搜索 `def build_agent_request_from_native`，回答以下问题：

1. 它们都从 `native_payload` 里提取了哪些相同的字段？（提示：`channel_id`、`sender_id`、`content_parts`、`meta`）
2. TelegramChannel 多提取了什么字段？（提示：`user_id`）
3. 它们都调用了基类的哪个方法来构建最终的 `AgentRequest`？（提示：`build_agent_request_from_user_content()`）

### 步骤三：对比 send()

在两个文件中搜索 `async def send(`，回答：

1. ConsoleChannel 的 `send()` 有几行有效代码？TelegramChannel 的呢？
2. TelegramChannel 为什么要 `_chunk_text(text)`？ConsoleChannel 需要吗？为什么？
3. TelegramChannel 的 `send()` 有几种失败处理？ConsoleChannel 有吗？

### 步骤四：对比 resolve_session_id()

在两个文件中搜索 `def resolve_session_id`，回答：

1. ConsoleChannel 的会话 ID 格式是什么？（提示：看它怎么处理 `meta` 中的 `session_id`）
2. TelegramChannel 的会话 ID 格式是什么？（提示：`telegram:{chat_id}`）
3. 为什么 Telegram 用 `chat_id` 而不是 `user_id` 作为会话标识？（提示：群聊场景）

### 步骤五：找出 ConsoleChannel 没有但 TelegramChannel 有的功能

浏览 TelegramChannel 的完整代码，找出至少三个 ConsoleChannel 不需要处理的问题：

1. TelegramChannel 怎么处理"正在输入"的指示器？（搜索 `_start_typing` 和 `_stop_typing`）
2. TelegramChannel 怎么处理连接断开？（搜索 `_run_polling` 和 `_RECONNECT`）
3. TelegramChannel 怎么处理消息中的 @机器人 提及？（搜索 `is_bot_mentioned`）

通过这个对比，你会清楚地看到：**适配器模式的精髓在于，接口相同、实现各异，而基类吸收了绝大部分共性。**
