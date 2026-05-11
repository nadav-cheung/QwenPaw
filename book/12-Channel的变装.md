# 第 12 章：Channel 的变装——适配器模式

```
卷二：理解设计
[9] 源码地图 -> [10] Agent身世 -> [11] Provider棋局 -> [12] Channel变装 <- you are here
```

第 2 章我们跟 HTTP 请求从 FastAPI 走到了 Runner。但 QwenPaw 不只服务浏览器——钉钉、飞书、微信、Telegram、Discord……17 个聊天平台都要接入。这一章我们看 BaseChannel 适配器模式：怎么用一套接口适配 17 个完全不同的平台 API？

---

## 问题

钉钉用 Stream 推送，飞书用事件订阅，微信用 XML 回调，Telegram 用 Bot API。每个平台的认证方式、消息格式、发送接口都不一样。QwenPaw 怎么做到 Agent 代码完全不改，就能接入新平台？

## 术语其实很简单

> **术语：适配器模式（Adapter Pattern）**
> 想象旅行充电器——中国的插头去欧洲要加个转换头。适配器模式就是"定义统一接口，各自转换"——BaseChannel 定义 `send()`、`start()`、`stop()`，每个渠道写自己的转换逻辑，把平台 API 适配成统一接口。

> **术语：ProcessHandler（处理器）**
> 想象一个通用插座——不管你插什么设备，都走同一条线路。`ProcessHandler` 是一个 `Callable`——每个 Channel 拿到它就能调用 Runner 处理请求，不需要知道 Runner 的内部实现。

## 探索

### 17 个渠道的家族树

```
BaseChannel (ABC -- 适配器基类)
  |
  +-- ConsoleChannel     # Web 控制台（最简单，~600 行）
  +-- DingTalkChannel    # 钉钉（最复杂，3625 行）
  +-- FeishuChannel      # 飞书/Lark（2267 行）
  +-- WeComChannel       # 企业微信
  +-- WeixinChannel      # 微信公众号
  +-- TelegramChannel    # Telegram Bot
  +-- DiscordChannel     # Discord Bot
  +-- QQChannel          # QQ
  +-- OneBotChannel      # OneBot 协议
  +-- MatrixChannel      # Matrix 协议
  +-- MattermostChannel  # Mattermost
  +-- iMessageChannel    # Apple iMessage
  +-- MQTTChannel        # MQTT 消息
  +-- VoiceChannel       # 语音/电话
  +-- XiaoYiChannel      # 小翼
```

关键观察：**所有渠道都直接继承 BaseChannel，没有中间层**。因为每个平台的差异太大，中间层反而增加复杂度。

### 六个核心方法——Channel 的统一契约

`BaseChannel` 定义了 6 个核心方法，每个渠道必须实现：

| 方法 | 职责 | 为什么是抽象的 |
|---|---|---|
| `from_config` | 从配置创建 Channel 实例 | 每个平台的配置字段不同 |
| `build_agent_request_from_native` | 平台消息 → AgentRequest | 每个平台的消息格式不同 |
| `start` | 启动 Channel | 每个平台的连接方式不同 |
| `stop` | 停止 Channel | 清理逻辑不同 |
| `send` | 发送文字消息 | 每个平台的发送 API 不同 |
| `send_content_parts` | 发送富文本（文字+图片+文件） | 每个平台的多媒体支持不同 |

另外有多个"有默认实现"的可选方法——渠道只需重写自己需要的：

```python
class BaseChannel(ABC):
    # 可选方法（有默认实现）
    def resolve_session_id(self, sender, meta):
        return f"{self.channel}:{sender}"  # 默认：渠道名+发送者

    def send_media(self, to_handle, media_url, ...):
        pass  # 默认空操作，不支持多媒体的渠道直接忽略

    def health_check(self):
        return {"status": "ok"}  # 默认健康检查
```

### ProcessHandler——Channel 和 Runner 之间的桥梁

Channel 不直接调用 Runner。它通过构造函数注入的 `ProcessHandler` 桥接：

```python
ProcessHandler = Callable[[AgentRequest], AsyncIterator[Event]]
```

每个 Channel 在 `from_config` 时接收这个 `process` 可调用对象。当收到用户消息时，Channel 调用：

```python
# base.py _run_process_loop 核心逻辑
async def _run_process_loop(self, request):
    async for event in self._process(request):  # _process 就是 ProcessHandler
        if event.type == "message_completed":
            await self.on_event_message_completed(event)
        elif event.type == "response":
            await self.on_event_response(event)
```

Channel 只管"收消息→转发→发回复"，不关心 Runner 内部怎么处理。Runner 只管"收请求→调 Agent→返回事件"，不关心消息来自哪个平台。

### ConsoleChannel——最简单的适配器

ConsoleChannel 只有约 600 行代码。它的 `send` 方法直接打印到标准输出：

```python
class ConsoleChannel(BaseChannel):
    channel = "console"

    async def send(self, to_handle, text, meta=None):
        # 1. 打印到终端
        print(text)
        # 2. 推送到前端 store（通过 SSE）
        self._push_store.put(text)
```

为什么这么简单？因为 Web 控制台不需要对接第三方 API——浏览器和服务器之间用 SSE 直连（第 8 章讲过），Channel 只是个"打印+推送"的中转站。

### DingTalkChannel——最复杂的适配器

钉钉渠道有 3625 行代码，是最复杂的 Channel。复杂性来自钉钉平台的多重机制：

**消息接收**：钉钉用 Stream 模式推送消息（长连接）。`DingTalkChannel` 在后台线程运行 Stream 客户端：

```python
async def start(self):
    # 启动后台线程接收钉钉 Stream 消息
    self._stream_thread = threading.Thread(
        target=self._run_stream_forever, daemon=True
    )
    self._stream_thread.start()
```

**消息发送**：钉钉有多种发送通道，`send_content_parts` 实现了完整的降级策略：

```python
async def send_content_parts(self, to_handle, parts, meta=None):
    # 1. 尝试 session_webhook 发送（最快）
    try:
        await self._send_via_session_webhook(to_handle, text)
    except WebhookExpired:
        # 2. 降级到 Open API 发送
        await self._try_open_api_fallback(to_handle, text)
    # 3. 多媒体单独发送
    for media in media_parts:
        await self._send_media_part_via_webhook(media)
```

**Webhook 持久化**：钉钉的 session_webhook 有时效性。`DingTalkChannel` 把 webhook 存到磁盘，重启后能恢复发送能力：

```python
def _save_session_webhook(self, conversation_id, webhook):
    # 持久化到文件，重启后可恢复
    path = self._webhook_path / f"{conversation_id}.json"
    path.write_text(json.dumps({"url": webhook, "expires": ...}))
```

### ChannelManager——17 个渠道的调度员

`ChannelManager` 管理所有渠道的生命周期：

```python
class ChannelManager:
    async def start_all(self):
        # 1. 创建统一队列管理器
        self._queue_mgr = UnifiedQueueManager()
        # 2. 为每个 Channel 设置入队回调
        for ch in self.channels:
            ch.set_enqueue(self.enqueue)
        # 3. 启动每个 Channel
        for ch in self.channels:
            await ch.start()

    async def stop_all(self):
        # 反向停止
        for ch in self.channels:
            await ch.stop()
```

消息路由流程：

```
平台推送消息 -> Channel.enqueue(channel_id, payload)
                    |
                    v
            ChannelManager._enqueue_one()
                    |
                    v
            统一队列（按 sender 分组）
                    |
                    v
            _consume_queue() 批量消费
                    |
                    v
            Channel.consume_one() -> build_request -> _process -> send_response
```

批量消费支持"合并"——用户快速连发多条消息时，`merge_native_items()` 把多条消息合成一个请求，避免 Agent 处理多次碎片消息。

### 新增渠道的步骤

适配器模式的威力：新增一个聊天平台只需要：

1. 在 `app/channels/<platform>/` 下创建 `channel.py`
2. 继承 `BaseChannel`，实现 6 个核心方法
3. 在 `ChannelManager` 注册新渠道

Agent 的代码完全不用改——它只认识 `AgentRequest` 和 `Event`，不关心消息来自哪个平台。

## 实验

对比 ConsoleChannel 和 DingTalkChannel 的实现复杂度：

1. 打开 `src/qwenpaw/app/channels/console/channel.py`，搜索 `class ConsoleChannel`
2. 打开 `src/qwenpaw/app/channels/dingtalk/channel.py`，搜索 `class DingTalkChannel`
3. 打开 `src/qwenpaw/app/channels/base.py`，搜索 `class BaseChannel`
4. 对比两者的 `send_content_parts` 方法

预期结果：ConsoleChannel 的 `send` 只有几行；DingTalkChannel 有完整的降级策略和 Webhook 管理。

## 工程权衡

### 为什么不用中间层（如 `HTTPChannel`、`StreamChannel`）？

钉钉同时用 Stream（接收）和 HTTP（发送），飞书用事件订阅+卡片回调，微信只用 HTTP。每个平台的"接收+发送"组合都不同，强行抽象中间层会导致更多特殊情况处理。扁平继承更简单——每个渠道直接继承 BaseChannel，只写自己需要的逻辑。

### 为什么 ProcessHandler 是 Callable 而不是 Runner 对象？

解耦。Channel 不需要知道 Runner 的类型、方法或内部状态——它只需要一个"可调用"的东西。这让 Channel 可以在测试时注入 mock ProcessHandler，也可以在不启动 Runner 的情况下测试 Channel 的消息解析逻辑。

## 常见误区

> **误区：每个渠道都要从头写几千行代码？**
>
> 不需要。`BaseChannel` 提供了大量默认实现——消息解析、队列管理、批量合并、事件分发、健康检查。ConsoleChannel 只有 600 行就实现了完整的渠道功能。只有钉钉、飞书这样 API 复杂的平台才需要几千行。大部分渠道在 500-1000 行之间。

## 动手环节

**任务**：阅读 BaseChannel 的核心方法和 ConsoleChannel 的完整实现。

**步骤**：
1. 打开 `src/qwenpaw/app/channels/base.py`，搜索 `_run_process_loop`
2. 打开 `src/qwenpaw/app/channels/console/channel.py`，阅读完整文件
3. 打开 `src/qwenpaw/app/channels/manager.py`，搜索 `start_all`

**预期输出**：
- `_run_process_loop` 展示了 Channel 如何消费 ProcessHandler 的事件
- ConsoleChannel 展示了最简单的 Channel 实现
- `start_all` 展示了 ChannelManager 如何管理多个渠道

**自检**：
- [ ] 理解了 BaseChannel 的 6 个核心方法
- [ ] 知道 ProcessHandler 是 Channel 和 Runner 之间的桥梁
- [ ] 知道新增渠道只需实现 BaseChannel，Agent 代码不用改

---

Channel 的适配器模式清楚了。下一章我们看 Security 的围栏——工具调用的安全检查是怎么做的？Guardian 系统怎么检测危险的 Shell 命令？密钥是怎么加密存储的？
