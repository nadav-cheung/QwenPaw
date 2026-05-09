# CLI、配置与安全

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 使用 CLI 命令管理 QwenPaw 应用 2) 理解配置系统的分层结构 3) 掌握基本的安全配置方法 |
| **前置知识** | [02-快速开始](./02-快速开始.md)、[03-项目架构](./03-项目架构.md) |
| **预计时长** | 60 分钟（阅读 35 分钟 + 练习 25 分钟） |
| **难度等级** | ⭐⭐⭐⭐ |
| **核心关键词** | `CLI` `配置管理` `安全` `密钥` `诊断` |

> **一句话概述**：本章讲解 QwenPaw 的命令行界面、配置系统和安全防护机制，帮助你掌握从日常运维到安全加固的完整技能。

---

## 概述

QwenPaw 提供完整的命令行界面、灵活的配置系统和多层次的安全防护机制。本文档详细介绍各模块的实现原理和使用方法。

---

## 1. CLI 系统

### 架构概览

CLI 系统位于 `src/qwenpaw/cli/`，基于 **Click** 框架构建，采用 **LazyGroup** 模式实现命令的延迟加载，提升启动速度。

```
src/qwenpaw/cli/
├── main.py              # CLI 入口点，LazyGroup 命令加载器
├── app_cmd.py           # 应用服务器命令
├── agents_cmd.py        # 多智能体管理
├── channels_cmd.py      # 渠道配置
├── chats_cmd.py         # 聊天会话管理
├── clean_cmd.py         # 清理命令
├── cron_cmd.py          # 定时任务命令
├── daemon_cmd.py        # 守护进程管理
├── desktop_cmd.py       # 桌面模式
├── doctor_cmd.py        # 诊断修复
├── doctor_checks.py     # 诊断检查项
├── doctor_connectivity.py # 连接诊断
├── doctor_fix_runner.py  # 自动修复执行器
├── doctor_registry.py   # 诊断注册表
├── env_cmd.py          # 环境变量命令
├── init_cmd.py          # 初始化向导
├── mission_cmd.py       # Mission 任务命令
├── plugin_commands.py   # 插件管理命令
├── providers_cmd.py     # LLM 提供商配置
├── shutdown_cmd.py      # 关闭命令
├── skills_cmd.py        # 技能管理
├── task_cmd.py          # 任务命令
├── uninstall_cmd.py     # 卸载命令
├── update_cmd.py        # 更新命令
├── acp_cmd.py          # ACP 协议命令
├── auth_cmd.py         # 认证命令
└── utils.py            # 工具函数
```

### 核心组件

#### LazyGroup 命令加载 (`cli/main.py:58-85`)

```python
class LazyGroup(click.Group):
    """支持延迟加载子命令的 Click Group"""

    def __init__(self, *args, lazy_subcommands=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.lazy_subcommands = lazy_subcommands or {}

    def list_commands(self, ctx):
        """返回所有命令名（ eager + lazy ）"""
        base = super().list_commands(ctx)
        return sorted(set(base) | set(self.lazy_subcommands.keys()))

    def get_command(self, ctx, cmd_name):
        """获取命令，按需懒加载"""
        # 先尝试 eager 命令
        cmd = super().get_command(ctx, cmd_name)
        if cmd is not None:
            return cmd
        # 懒加载命令
        if cmd_name in self.lazy_subcommands:
            module_path, attr_name, label = self.lazy_subcommands[cmd_name]
            module = __import__(module_path, fromlist=[attr_name])
            cmd = getattr(module, attr_name)
            self.add_command(cmd, cmd_name)  # 缓存
            return cmd
        return None
```

**懒加载命令注册** (`cli/main.py:83-144`):

```python
@click.group(
    cls=LazyGroup,
    lazy_subcommands={
        "acp": ("qwenpaw.cli.acp_cmd", "acp_cmd", ".acp_cmd"),
        "app": ("qwenpaw.cli.app_cmd", "app_cmd", ".app_cmd"),
        "agents": ("qwenpaw.cli.agents_cmd", "agents_group", ".agents_cmd"),
        "channels": ("qwenpaw.cli.channels_cmd", "channels_group", ".channels_cmd"),
        "chats": ("qwenpaw.cli.chats_cmd", "chats_group", ".chats_cmd"),
        "cron": ("qwenpaw.cli.cron_cmd", "cron_group", ".cron_cmd"),
        "daemon": ("qwenpaw.cli.daemon_cmd", "daemon_group", ".daemon_cmd"),
        "init": ("qwenpaw.cli.init_cmd", "init_cmd", ".init_cmd"),
        "mission": ("qwenpaw.cli.mission_cmd", "mission_group", ".mission_cmd"),
        "models": ("qwenpaw.cli.providers_cmd", "models_group", ".providers_cmd"),
        "skills": ("qwenpaw.cli.skills_cmd", "skills_group", ".skills_cmd"),
        "task": ("qwenpaw.cli.task_cmd", "task_cmd", ".task_cmd"),
        ...
    },
)
```

### 常用命令

#### 应用管理

| 命令 | 源码 | 说明 |
|------|------|------|
| `qwenpaw app` | `cli/app_cmd.py:1` | 启动 FastAPI 服务器 |
| `qwenpaw desktop` | `cli/desktop_cmd.py` | 启动桌面 Webview 模式 |
| `qwenpaw daemon status` | `cli/daemon_cmd.py:1` | 查看守护进程状态 |
| `qwenpaw daemon restart` | `cli/daemon_cmd.py:1` | 重启守护进程 |
| `qwenpaw shutdown` | `cli/shutdown_cmd.py` | 关闭运行中的实例 |

```bash
# 启动 API 服务器
qwenpaw app --host 127.0.0.1 --port 8088 --reload

# 启动桌面模式（自动打开 Webview 窗口）
qwenpaw desktop

# 检查守护进程状态
qwenpaw daemon status

# 重启守护进程
qwenpaw daemon restart
```

#### 智能体管理 (`cli/agents_cmd.py:1`)

| 命令 | 说明 |
|------|------|
| `qwenpaw agents list` | 列出所有智能体 |
| `qwenpaw agents create` | 创建新智能体 |
| `qwenpaw agents chat` | 与另一个代理通信 |
| `qwenpaw agents delete` | 删除代理配置 |

```bash
# 列出所有智能体
qwenpaw agents list

# 创建新智能体
qwenpaw agents create --name my_agent

# 与代理通信
qwenpaw agents chat --from-agent agent1 --to-agent agent2 --text "Hello"
```

#### 渠道管理 (`cli/channels_cmd.py:1`)

| 命令 | 说明 |
|------|------|
| `qwenpaw channels list` | 列出配置的渠道 |
| `qwenpaw channels add` | 添加渠道到配置 |
| `qwenpaw channels config` | 交互式配置渠道参数 |
| `qwenpaw channels install` | 安装自定义渠道到 custom_channels/ |
| `qwenpaw channels send` | 通过渠道发送消息 |

```bash
# 列出所有渠道
qwenpaw channels list

# 添加渠道到配置
qwenpaw channels add telegram

# 交互式配置渠道
qwenpaw channels config

# 安装自定义渠道
qwenpaw channels install mychannel --from-path ./my-channel
```

#### 技能管理

```bash
# 列出所有技能
qwenpaw skills list

# 查看技能详情
qwenpaw skills info pdf

# 配置技能参数
qwenpaw skills config
```

技能在创建智能体时通过 `--skill` 参数安装：
```bash
qwenpaw agents create --name my_agent --skill pdf --skill browser_visible
```

#### 提供商配置

```bash
# 列出配置的 LLM 提供商
qwenpaw models list

# 配置提供商
qwenpaw models config
```

#### 诊断工具

```bash
# 运行诊断检查
qwenpaw doctor

# 自动修复问题
qwenpaw doctor --fix
```

#### 初始化

```bash
# 交互式初始化向导
qwenpaw init
```

---

### 1.3 核心命令实现详解

### 1.3.1 app 命令 — 启动 FastAPI 服务器

**源码路径**: `src/qwenpaw/cli/app_cmd.py:17-91`

```python
@click.command("app")
@click.option("--host", default="127.0.0.1", help="Bind host")
@click.option("--port", default=8088, type=int, help="Bind port")
@click.option("--reload", is_flag=True, help="Enable auto-reload (dev only)")
@click.option("--log-level", default="info", help="Log level")
@click.option("--hide-access-paths", multiple=True,
    default=("/console/push-messages",), help="隐藏访问日志路径")
def app_cmd(host, port, reload, log_level, hide_access_paths):
    """Run QwenPaw FastAPI app."""

    # 持久化最后使用的 host/port
    write_last_api(host, port)

    # 设置日志级别
    os.environ[LOG_LEVEL_ENV] = log_level
    setup_logger(log_level)

    # 隐藏敏感路径的访问日志
    if hide_access_paths:
        logging.getLogger("uvicorn.access").addFilter(
            SuppressPathAccessLogFilter(hide_access_paths)
        )

    uvicorn.run(
        "qwenpaw.app._app:app",
        host=host,
        port=port,
        reload=reload,
        workers=1,  # 始终使用单 worker
        log_level=log_level,
    )
```

**关键设计**:
- `--workers` 参数已废弃，始终使用单 worker 保证稳定性
- `--reload` 模式下设置 `QWENPAW_RELOAD_MODE=1` 环境变量，启用 Windows 兼容的 ThreadPool
- 启动前通过 `write_last_api()` 保存 host/port，供其他命令复用

### 1.3.2 plugin install 命令 — 插件安装

**源码路径**: `src/qwenpaw/cli/plugin_commands.py:73-218`

```python
@plugin.command()
@click.argument("source")
@click.option("--force", is_flag=True, help="强制重装")
def install(source: str, force: bool):
    """从本地路径或 URL 安装插件"""
    # 1. 检查 QwenPaw 未运行
    _check_qwenpaw_not_running()

    # 2. 判断是 URL 还是本地路径
    is_url = source.startswith(("http://", "https://"))
    if is_url:
        source_path, temp_dir = _download_plugin_from_url(source)
    else:
        source_path = Path(source).resolve()

    # 3. 验证 plugin.json 存在
    manifest_path = source_path / "plugin.json"

    # 4. 解析 manifest 获取 plugin_id
    with open(manifest_path) as f:
        manifest = json.load(f)
    plugin_id = manifest["id"]

    # 5. 目标目录: ~/.qwenpaw/plugins/<plugin_id>
    target_dir = get_plugins_dir() / plugin_id

    # 6. 如果已存在且 --force，删除旧版本
    if target_dir.exists() and force:
        shutil.rmtree(target_dir)

    # 7. 复制插件文件
    shutil.copytree(source_path, target_dir)

    # 8. 安装依赖 (pip install -r requirements.txt)
    requirements_file = target_dir / "requirements.txt"
    if requirements_file.exists():
        subprocess.run([
            sys.executable, "-m", "pip", "install",
            "-r", str(requirements_file)
        ], check=True)
```

**安全特性 — Zip Slip 攻击防护** (`plugin_commands.py:43-57`):

```python
def _safe_extract_zip(zip_ref, extract_path):
    """防止 Zip Slip 攻击：确保解压路径不超出目标目录"""
    for member in zip_ref.namelist():
        member_path = (extract_path / member).resolve()
        if not str(member_path).startswith(str(extract_path.resolve())):
            raise ValueError(f"Zip Slip detected: {member}")
    zip_ref.extractall(extract_path)
```

**Zip Slip 防护原理**: 攻击者可能在 ZIP 文件中注入 `../../../etc/passwd` 等路径遍历文件名，解压时可能覆盖系统文件。上述检查确保所有解压路径都在目标目录内。

### 1.3.3 plugin validate 命令 — 插件验证

**源码路径**: `src/qwenpaw/cli/plugin_commands.py:330-383`

```python
@plugin.command()
@click.argument("path")
def validate(path: str):
    """验证插件结构"""
    plugin_path = Path(path).resolve()

    # 检查 plugin.json 存在
    manifest_path = plugin_path / "plugin.json"

    with open(manifest_path) as f:
        manifest = json.load(f)

    # 验证必需字段
    required_fields = ["id", "name", "version"]
    for field in required_fields:
        if field not in manifest:
            click.echo(f"Missing required field: {field}", err=True)
            return

    # 检查入口点文件存在
    entry = manifest.get("entry", {})
    backend_entry = entry.get("backend")
    if backend_entry:
        backend_path = plugin_path / backend_entry
        if not backend_path.exists():
            click.echo(f"Backend entry not found: {backend_entry}", err=True)
            return

    click.echo("Plugin validation passed")
```

### 1.3.4 LazyGroup 懒加载机制详解

**源码路径**: `src/qwenpaw/cli/main.py:34-59`

```python
class LazyGroup(click.Group):
    """支持延迟加载子命令的 Click Group"""

    def __init__(self, *args, lazy_subcommands=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.lazy_subcommands = lazy_subcommands or {}

    def list_commands(self, ctx):
        """返回所有命令名（eager + lazy）"""
        base = super().list_commands(ctx)
        return sorted(set(base) | set(self.lazy_subcommands.keys()))

    def get_command(self, ctx, cmd_name):
        """获取命令，按需懒加载"""
        # 1. 先尝试 eager 命令
        cmd = super().get_command(ctx, cmd_name)
        if cmd is not None:
            return cmd

        # 2. 懒加载命令
        if cmd_name in self.lazy_subcommands:
            module_path, attr_name, label = self.lazy_subcommands[cmd_name]
            _t = time.perf_counter()
            module = __import__(module_path, fromlist=[attr_name])
            cmd = getattr(module, attr_name)
            _record(label, time.perf_counter() - _t)  # 记录加载时间
            self.add_command(cmd, cmd_name)  # 缓存到 Group
            return cmd
        return None
```

**懒加载命令注册** (`cli/main.py:95-140`):

```python
lazy_subcommands={
    "acp": ("qwenpaw.cli.acp_cmd", "acp_cmd", ".acp_cmd"),
    "app": ("qwenpaw.cli.app_cmd", "app_cmd", ".app_cmd"),
    "agents": ("qwenpaw.cli.agents_cmd", "agents_group", ".agents_cmd"),
    "channels": ("qwenpaw.cli.channels_cmd", "channels_group", ".channels_cmd"),
    "cron": ("qwenpaw.cli.cron_cmd", "cron_group", ".cron_cmd"),
    "daemon": ("qwenpaw.cli.daemon_cmd", "daemon_group", ".daemon_cmd"),
    "init": ("qwenpaw.cli.init_cmd", "init_cmd", ".init_cmd"),
    "plugin": ("qwenpaw.cli.plugin_commands", "plugin", ".plugin_commands"),
    ...
}
```

**懒加载流程图**:

```
qwenpaw cron list
         │
         ▼
LazyGroup.get_command("cron")
         │
         ├─► super().get_command("cron") → None (eager 中没有)
         │
         ▼
"cron" in lazy_subcommands → True
         │
         ▼
__import__("qwenpaw.cli.cron_cmd", fromlist=["cron_group"])
         │
         ▼
getattr(module, "cron_group")
         │
         ▼
self.add_command(cmd, "cron")  // 缓存
         │
         ▼
返回 cron_group 命令
```

**懒加载优势**:
- 启动速度：未使用的命令模块不加载，节省内存和启动时间
- `time.perf_counter()` 记录加载时间，便于诊断性能问题
- 命令加载后缓存到 Group，后续调用直接返回

---

## 2. 配置系统

### 配置结构

配置文件位于 `WORKING_DIR/config.json`（通常为 `~/.qwenpaw/config.json`）。

```
~/.qwenpaw/
├── config.json          # 主配置文件
├── .master_key         # 加密密钥
└── channels/           # 渠道配置
```

### 配置模型

配置系统基于 **Pydantic** 模型实现，提供类型安全和自动验证。

#### 根配置模型

```python
# src/qwenpaw/config/config.py

class Config(BaseModel):
    """根配置模型"""

    # 版本标识
    version: str = "1.0"

    # 渠道配置
    channels: ChannelConfig

    # MCP 配置
    mcp: MCPConfig

    # 工具配置
    tools: ToolsConfig

    # 智能体配置
    agents: AgentsConfig

    # 安全配置
    security: SecurityConfig

    # ACP 协议配置
    acp: ACPConfig

    # 嵌入模型配置
    embedding: EmbeddingConfig

    # 上下文压缩配置
    context_compact: ContextCompactConfig
```

#### 渠道配置

```python
class ChannelConfig(BaseModel):
    """支持的渠道配置"""

    imessage: Optional[IMessageChannelConfig]
    discord: Optional[DiscordChannelConfig]
    telegram: Optional[TelegramChannelConfig]
    dingtalk: Optional[DingTalkChannelConfig]
    feishu: Optional[FeishuChannelConfig]
    qq: Optional[QQChannelConfig]
    mattermost: Optional[MattermostChannelConfig]
    mqtt: Optional[MQTTChannelConfig]
    console: Optional[ConsoleConfig]
    matrix: Optional[MatrixChannelConfig]
    voice: Optional[VoiceChannelConfig]
    wecom: Optional[WecomChannelConfig]
    xiaoyi: Optional[XiaoYiChannelConfig]
    weixin: Optional[WeixinChannelConfig]
    onebot: Optional[OneBotChannelConfig]
```

#### 智能体配置

```python
#### AgentsConfig 智能体配置

```python
class AgentsConfig(BaseModel):
    """多智能体配置"""

    active_agent: str = "default"              # 当前活跃智能体 ID
    agent_order: List[str] = ["default"]       # 智能体加载顺序
    profiles: Dict[str, AgentProfileRef] = {}  # 智能体配置引用
    running: AgentsRunningConfig               # 运行时配置
    language: str = "zh"                       # 默认语言
```

#### AgentProfileConfig 智能体配置 (config.py 第859-926行)

```python
class AgentProfileConfig(BaseModel):
    """单个智能体完整配置"""

    id: str                                    # 唯一智能体 ID
    name: str                                  # 人类可读名称
    description: str = ""                      # 智能体描述
    workspace_dir: str = ""                     # 工作区目录
    template_id: Optional[str] = None         # 创建时使用的模板
    channels: Optional[ChannelConfig] = None  # 渠道配置
    mcp: Optional[MCPConfig] = None            # MCP 客户端配置
    heartbeat: Optional[HeartbeatConfig] = None # 心跳配置
    running: AgentsRunningConfig               # 运行时配置
    llm_routing: AgentsLLMRoutingConfig       # LLM 路由设置
    active_model: Optional[ModelSlotConfig] = None  # 活跃模型配置
    language: str = "zh"                       # 语言设置
    system_prompt_files: List[str] = ["AGENTS.md", "SOUL.md", "PROFILE.md"]
    tools: Optional[ToolsConfig] = None         # 工具配置
    security: Optional[SecurityConfig] = None   # 安全配置
    acp: Optional[ACPConfig] = None            # ACP 配置
```

#### AgentsRunningConfig 运行时配置 (config.py 第647-811行)

```python
class AgentsRunningConfig(BaseModel):
    """运行时行为配置"""

    # 迭代控制
    max_iters: int = 100                       # 最大推理-行动迭代次数
    auto_continue_on_text_only: bool = False   # 纯文本回复时自动继续

    # LLM 重试配置
    llm_retry_enabled: bool = True            # 启用 LLM 重试
    llm_max_retries: int = 3                  # 最大重试次数
    llm_backoff_base: float = 1.0              # 指数退避基础值
    llm_backoff_cap: float = 10.0             # 指数退避上限

    # LLM 并发控制
    llm_max_concurrent: int = 10               # 最大并发 LLM 调用
    llm_max_qpm: int = 600                    # 每分钟最大请求
    llm_rate_limit_pause: float = 5.0          # 速率限制暂停时间
    llm_rate_limit_jitter: float = 1.0         # 速率限制抖动
    llm_acquire_timeout: float = 300.0         # 获取超时(秒)

    # 上下文管理
    max_input_length: int = 128*1024           # 最大输入长度
    history_max_length: int = 10000            # 历史最大长度

    # 子配置
    context_compact: ContextCompactConfig      # 上下文压缩配置
    tool_result_compact: ToolResultCompactConfig  # 工具结果压缩
    memory_summary: MemorySummaryConfig        # 记忆摘要配置
    embedding_config: EmbeddingConfig          # Embedding 配置

    # 记忆管理器
    memory_manager_backend: Literal["remelight"] = "remelight"

    # 计算属性
    @property
    def memory_compact_reserve(self) -> int: ...   # 记忆压缩保留大小
    @property
    def memory_compact_threshold(self) -> int: ...  # 记忆压缩阈值

    # 验证方法
    def validate_llm_retry_backoff(self) -> None: ...
```

**计算属性详解** (第799-811行):

| 属性 | 公式 | 说明 |
|------|------|------|
| `memory_compact_reserve` | `max_input_length * memory_reserve_ratio` | 上下文保留阈值 |
| `memory_compact_threshold` | `max_input_length * memory_compact_ratio` | 压缩触发阈值 |

**ContextCompactConfig** (config.py 第474-526行):

```python
class ContextCompactConfig(BaseModel):
    token_count_model: str = "default"         # Token 计数模型
    token_count_use_mirror: bool = False       # 使用 HF 镜像
    token_count_estimate_divisor: float = 4.0  # Token 估算除数
    context_compact_enabled: bool = True        # 启用自动压缩
    memory_compact_ratio: float = 0.75          # 压缩触发阈值 (75%)
    memory_reserve_ratio: float = 0.1          # 上下文保留阈值 (10%)
    compact_with_thinking_block: bool = True    # 压缩时包含思考块
```

#### 安全配置

```python
class SecurityConfig(BaseModel):
    """安全配置"""

    tool_guard: ToolGuardConfig = ToolGuardConfig()
    file_guard: FileGuardConfig = FileGuardConfig()
    skill_scanner: SkillScannerConfig = SkillScannerConfig()

class ToolGuardConfig(BaseModel):
    """工具调用守卫配置"""

    enabled: bool = True
    denied_tools: List[str] = []
    scope: List[str] = ["bash", "read", "write", "edit"]
```

### 配置加载

**源码路径**: `src/qwenpaw/config/utils.py`

**`load_config` 函数** (第491-530行):

```python
def load_config(config_path: Optional[Path] = None) -> Config:
    """加载配置文件。如果文件不存在，返回默认 Config。"""
    if config_path is None:
        config_path = get_config_path()  # WORKING_DIR / "config.json"
    
    if not config_path.is_file():
        return Config()
    
    data = _read_config_data(config_path)
    if data is None:
        return Config()
    
    data = _normalize_working_dir_bound_paths(data)
    
    # 验证配置
    try:
        return Config.model_validate(data)
    except ValidationError as exc:
        # 尝试修复常见错误
        for err in exc.errors():
            loc = list(err.get("loc", []))
            if loc and _remove_bad_field(data, loc):
                fixed_any = True
        if not fixed_any:
            _backup_config_file(config_path, "validation error")
            return Config()
```

**`_read_config_data` 函数** (第456-488行):

```python
def _read_config_data(config_path: Path) -> Optional[dict]:
    """读取并解析配置文件。
    
    使用 json_repair 处理常见语法问题（尾随逗号、引号缺失、注释、BOM 等）。"""
    try:
        with open(config_path, "r", encoding="utf-8") as file:
            raw = file.read()
    except UnicodeDecodeError:
        _backup_config_file(config_path, "encoding error")
        return None

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        data = repair_json(raw, return_objects=True)  # 自动修复 JSON
        if not isinstance(data, dict):
            _backup_config_file(config_path, "JSON syntax error, repair failed")
            return None
```

**Agent 配置加载** (config.py 第1508-1553行):

```python
def load_agent_config(agent_id: str) -> AgentProfileConfig:
    """从 workspace/agent.json 加载智能体完整配置"""
    config = load_config()

    if agent_id not in config.agents.profiles:
        raise ConfigurationException(
            config_key="agent",
            message=f"Agent '{agent_id}' not found in config",
        )

    agent_ref = config.agents.profiles[agent_id]
    workspace_dir = Path(agent_ref.workspace_dir).expanduser()
    agent_config_path = workspace_dir / "agent.json"

    if not agent_config_path.exists():
        fallback_config = build_fallback_agent_profile_config(agent_id, config)
        save_agent_config(agent_id, fallback_config)
        return fallback_config

    with open(agent_config_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    data = _normalize_working_dir_bound_paths(data)
    return AgentProfileConfig(**data)
```

**严格验证** (第533-570行):

```python
def strict_validate_config_file(config_path: Optional[Path] = None) -> tuple[bool, str]:
    """严格验证配置文件（不自动修复）"""
    if not config_path.is_file():
        return True, f"(no file) defaults — {config_path}"

    data = _read_config_data(config_path)
    if data is None:
        return False, f"unreadable or invalid JSON — {config_path}"

    try:
        Config.model_validate(data)
    except ValidationError as exc:
        lines = [f"{config_path}:"]
        for err in exc.errors():
            loc = ".".join(str(x) for x in err.get("loc", ()))
            msg = err.get("msg", "")
            lines.append(f"  {loc}: {msg}")
        return False, "\n".join(lines)
    return True, str(config_path)
```

### 配置迁移

配置系统支持从旧路径迁移：

```python
def _normalize_working_dir_bound_paths():
    """将旧版 ~/.copaw 路径迁移到当前 WORKING_DIR"""
    # 自动检测并迁移配置文件
```

### 配置上下文

提供线程安全的上下文变量：

```python
# src/qwenpaw/config/context.py

from contextvars import ContextVar

# 当前工作目录（每个智能体独立）
current_workspace_dir: ContextVar[str] = ContextVar("current_workspace_dir")

# 截断限制
current_recent_max_bytes: ContextVar[int] = ContextVar("current_recent_max_bytes")
```

---

## 3. 安全模块

安全模块位于 `src/qwenpaw/security/`，提供三层安全防护：

```
src/qwenpaw/security/
├── secret_store.py        # 敏感信息加密存储
├── tool_guard/            # 工具调用安全扫描
│   ├── engine.py          # ToolGuardEngine 核心
│   ├── models.py          # 扫描结果模型
│   └── guardians/         # 各类型守卫实现
└── skill_scanner/         # 技能安全扫描
    ├── scanner.py         # 扫描器核心
    ├── scan_policy.py     # 扫描策略
    └── rules/              # 安全规则定义
```

### 3.1 SecretStore 密钥加密存储

**源码路径**: `src/qwenpaw/security/secret_store.py`

**核心常量** (第33-37行):

```python
_ENC_PREFIX = "ENC:"           # 加密值前缀
_KEYRING_SERVICE = "qwenpaw"   # OS Keychain 服务名
_LEGACY_SERVICE = "copaw"     # 兼容旧版服务名
_KEYRING_ACCOUNT = "master_key"  # Keychain 账户名
```

**Fernet 加密机制**:

| 函数 | 行号 | 功能 |
|------|------|------|
| `encrypt()` | 162-169 | 加密，返回 `ENC:<base64-ciphertext>` |
| `decrypt()` | 171-187 | 解密，自动识别前缀 |
| `is_encrypted()` | 192-193 | 检查是否已加密 |
| `_get_fernet()` | 196-205 | 获取缓存的 Fernet 实例 |

```python
def encrypt(plaintext: str) -> str:
    """加密敏感数据，返回格式: ENC:<base64-ciphertext>"""
    fernet = _get_fernet()
    encrypted = fernet.encrypt(plaintext.encode())
    return f"ENC:{base64.b64encode(encrypted).decode()}"

def decrypt(value: str) -> str:
    """解密：自动识别 ENC: 前缀，未加密值直接返回"""
    if not is_encrypted(value):
        return value  # graceful degradation
    fernet = _get_fernet()
    encrypted_bytes = base64.b64decode(value[4:])
    return fernet.decrypt(encrypted_bytes).decode()

def is_encrypted(value: str) -> bool:
    """检查是否已加密"""
    return isinstance(value, str) and value.startswith("ENC:")
```

**主密钥管理**:

| 函数 | 行号 | 功能 |
|------|------|------|
| `_get_master_key()` | 130-156 | 双重检查锁定获取主密钥 |
| `_generate_master_key()` | 126 | 生成 32 字节随机密钥 |
| `_should_skip_keyring()` | 68-82 | 判断是否跳过 OS Keychain |
| `_try_keyring_get()` | 87-101 | 从 Keychain 获取密钥 |
| `_try_keyring_set()` | 106-117 | 存入 Keychain |
| `_master_key_file()` | 122-123 | 获取密钥文件路径 |
| `reload_master_key_from_disk()` | 215-249 | 从磁盘重新加载密钥 |

**密钥获取优先级** (`_get_master_key()`):

```
1. 进程内缓存 (_cached_master_key) — 快速路径
2. OS Keychain (keyring 库) — 持久化存储
3. 本地文件 SECRET_DIR/.master_key — 兜底
4. 生成新密钥 — 从未存在
```

**Keychain 跳过条件** (`_should_skip_keyring()`):

```python
def _should_skip_keyring() -> bool:
    """以下环境跳过 OS Keychain:"""
    return (
        os.environ.get("QWENPAW_RUNNING_IN_CONTAINER") or  # Docker
        (platform.system() == "Linux" and (
            os.environ.get("CI") or  # CI 环境
            not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY")  # headless
        ))
    )
```

**密钥轮换机制**:

```python
def reload_master_key_from_disk() -> None:
    """从磁盘重新加载主密钥（用于备份恢复后）"""
    # 1. 使进程内缓存失效
    global _cached_master_key, _cached_fernet
    _cached_master_key = None
    _cached_fernet = None

    # 2. 从 SECRET_DIR/.master_key 读取
    # 3. 同步到 OS Keychain
```

**主密钥冲突处理** (`restore_helpers.py:108-156`):

备份恢复时如果检测到主密钥不同，会自动备份当前密钥：

**handle_master_key_conflict()** (`restore_helpers.py:108-156`):

```python
def handle_master_key_conflict(
    zf: zipfile.ZipFile,
    bak_dir: Path | None = None,
) -> Path | None:
    """当备份的密钥与当前不同时，备份当前主密钥。

    如果备份包含的 .master_key 与当前磁盘上的不同，
    则将现有密钥复制到
    BACKUP_DIR/_pre_restore_keys/<UTC-timestamp>.master_key.bak，
    以便需要时仍能用旧密钥解密之前加密的凭证。

    备份文件故意写在 SECRET_DIR 外，
    以免被后续的 extract_to_tmp + commit_tmp 影响。"""
    master_key_zip_entry = f"{PREFIX_SECRETS}{_MASTER_KEY}"
    current_master_key = SECRET_DIR / _MASTER_KEY

    if not (
        current_master_key.is_file() and master_key_zip_entry in zf.namelist()
    ):
        return None

    with zf.open(master_key_zip_entry) as f:
        backup_mk_bytes = f.read()
    with open(current_master_key, "rb") as f:
        current_mk_bytes = f.read()

    if backup_mk_bytes == current_mk_bytes:
        return None  # 密钥相同，无需处理

    # 备份当前密钥
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    bak = bak_dir / f"{ts}.master_key.bak"
    bak_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(current_master_key, bak)
    return bak
```

**密钥冲突处理流程**:

```
检测到备份中的 .master_key 与当前不同
         │
         ▼
备份当前密钥到 BACKUP_DIR/_pre_restore_keys/<timestamp>.master_key.bak
         │
         ▼
用备份中的密钥替换当前密钥
         │
         ▼
恢复后自动同步到 OS Keychain
```

**完整密钥生命周期流程**:

```
_get_master_key() 调用
         │
         ▼
   ┌─────────────────┐
   │ _cached_master_key │───存在?──是──► 返回缓存密钥 (快速路径)
   │    是否为 None?  │
   └────────┬─────────┘
            │ 否
            ▼
   ┌─────────────────┐
   │  获取锁          │
   └────────┬─────────┘
            ▼
   ┌─────────────────────────┐
   │ _cached_master_key      │───存在?──是──► 返回缓存密钥
   │    是否为 None? (二次检查) │         (另一线程已初始化)
   └────────┬────────────────┘
            │ 否
            ▼
   ┌───────────────────────────────────┐
   │ _try_keyring_get()                │───成功?──是──► 使用 keyring 值
   │ (keyring + 旧版 copaw 支持)       │
   └───────────────┬───────────────────┘
                    │ 否 / 跳过 (容器/CI)
                    ▼
   ┌───────────────────────────────────┐
   │ _read_key_file()                  │───成功?──是──► 提升到 keyring
   │ (.master_key, 0o600 权限)        │                  _try_keyring_set()
   └───────────────┬───────────────────┘
                    │ 否
                    ▼
   ┌───────────────────────────────────┐
   │ _generate_master_key()            │ secrets.token_hex(32)
   │ (创建新的 32 字节密钥)            │
   └───────────────┬───────────────────┘
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
   _try_keyring_set()   _write_key_file()
          │                   │
          └─────────┬─────────┘
                    ▼
           缓存密钥并返回
```

**双重检查锁定模式** (`_get_master_key()`, 第154-188行):

```python
def _get_master_key() -> bytes:
    # 快速路径：进程内缓存
    if _cached_master_key is not None:
        return _cached_master_key

    with _master_key_lock:  # 加锁
        if _cached_master_key is not None:  # 双重检查
            return _cached_master_key
        # ... 初始化逻辑
```

**reload_master_key_from_disk()** (secret_store.py 第249-289行):

恢复后重新加载密钥到进程:

```python
def reload_master_key_from_disk() -> None:
    """使进程内缓存失效并重新同步 OS Keyring。

    在备份恢复替换 SECRET_DIR/.master_key 后调用，
    以便运行中的进程和 OS Keyring 都能使用恢复的新密钥。"""
    global _cached_master_key, _cached_fernet
    try:
        with _master_key_lock:
            _cached_master_key = None
            _cached_fernet = None

            key_hex = _read_key_file()
            if not key_hex:
                logger.warning("reload_master_key_from_disk: .master_key 文件未找到")
                return

            _try_keyring_set(key_hex)  # 同步 keyring
            logger.info("reload_master_key_from_disk: 缓存已失效，keyring 已更新")
    except Exception:
        logger.warning("reload_master_key_from_disk: 意外错误", exc_info=True)
```

**文件权限**:
- `.master_key` 文件: `0o600` (仅所有者读写)
- `SECRET_DIR` 目录: `0o700` (仅所有者读写执行)

**Keyring 跳过条件** `_should_skip_keyring()` (第49-68行):

在以下环境跳过 OS Keyring，直接使用文件存储：

| 条件 | 说明 |
|------|------|
| `QWENPAW_RUNNING_IN_CONTAINER=true` | 容器环境 |
| Linux 无 DISPLAY/WAYLAND | 无头服务器 |
| `CI=true` | CI/CD 环境 |

**迁移机制** (自动从明文迁移):

```python
# 首次访问时检测明文字段，自动加密
if has_plaintext:
    _rewrite_encrypted(path, decrypted)  # 写回加密版本

# _maybe_migrate_plaintext() 检查任一字段是否为明文
# 如果是，返回 True 触发重写
```

**字典字段加密** (第267-296行):

```python
PROVIDER_SECRET_FIELDS: frozenset[str] = frozenset({"api_key"})
AUTH_SECRET_FIELDS: frozenset[str] = frozenset({"jwt_secret"})

def encrypt_dict_fields(data: dict, secret_fields: frozenset[str]) -> dict:
    """加密字典中指定的敏感字段"""
    for field in secret_fields:
        if field in data and data[field] and not is_encrypted(data[field]):
            data[field] = encrypt(data[field])

def decrypt_dict_fields(data: dict, secret_fields: frozenset[str]) -> dict:
    """解密字典中指定的敏感字段"""
    for field in secret_fields:
        if field in data and is_encrypted(data[field]):
            data[field] = decrypt(data[field])
```

**使用场景**:

| 文件 | 加密字段 |
|------|---------|
| `src/qwenpaw/envs/store.py` | 环境变量 `envs.json` |
| `src/qwenpaw/app/auth.py` | `jwt_secret` |
| `src/qwenpaw/providers/provider_manager.py` | `api_key` |
| `src/qwenpaw/backup/_ops/restore.py` | 调用 `reload_master_key_from_disk()` |

### 3.2 ToolGuardEngine 核心引擎

**源码路径**: `src/qwenpaw/security/tool_guard/engine.py`

**`ToolGuardEngine` 类** (第44-165行):

```python
class ToolGuardEngine:
    """单例编排器，运行所有注册的守卫"""

    def __init__(self, guardians: list[BaseToolGuardian] | None = None) -> None:
        self._guardians: list[BaseToolGuardian] = [
            FilePathToolGuardian(),      # 路径守卫（always_run=True）
            RuleBasedToolGuardian(),     # 规则守卫
            ShellEvasionGuardian(),      # 混淆检测
        ]

    def guard(
        self,
        tool_name: str,
        params: Any,
        *,
        only_always_run: bool = False,
    ) -> ToolGuardResult:
        """守卫工具调用的参数"""

    def is_denied(self, tool_name: str) -> bool:
        """检查工具是否在拒绝列表"""

    def is_guarded(self, tool_name: str) -> bool:
        """检查工具是否在守卫范围内"""

    def reload_rules(self) -> None:
        """重新加载守卫规则"""
```

**守卫注册** (第89行):

```python
def register_guardian(self, guardian: BaseToolGuardian) -> None:
    """注册额外的守卫"""
    self._guardians.append(guardian)
```

### 3.3 Guard 数据模型

**源码路径**: `src/qwenpaw/security/tool_guard/models.py`

**`GuardSeverity` 枚举** (第31行):

```python
class GuardSeverity(StrEnum):
    CRITICAL = "critical"  # 立即阻止
    HIGH = "high"          # 需要确认
    MEDIUM = "medium"      # 警告
    LOW = "low"            # 提示
    INFO = "info"          # 信息
    SAFE = "safe"          # 安全
```

**`GuardThreatCategory` 枚举** (第45行):

```python
class GuardThreatCategory(StrEnum):
    COMMAND_INJECTION = "command_injection"        # 命令注入
    DATA_EXFILTRATION = "data_exfiltration"      # 数据泄露
    PATH_TRAVERSAL = "path_traversal"          # 路径遍历
    SENSITIVE_FILE_ACCESS = "sensitive_file_access"  # 敏感文件访问
    NETWORK_ABUSE = "network_abuse"            # 网络滥用
    CREDENTIAL_EXPOSURE = "credential_exposure"  # 凭证暴露
    RESOURCE_ABUSE = "resource_abuse"          # 资源滥用
    PROMPT_INJECTION = "prompt_injection"      # 提示注入
    CODE_EXECUTION = "code_execution"          # 代码执行
    PRIVILEGE_ESCALATION = "privilege_escalation"  # 权限提升
```

**`GuardFinding` 数据结构** (第72行):

```python
@dataclass
class GuardFinding:
    id: str                    # 唯一标识
    rule_id: str              # 触发规则ID
    category: GuardThreatCategory
    severity: GuardSeverity
    title: str                # 发现标题
    description: str          # 详细描述
    tool_name: str            # 工具名
    param_name: str          # 参数名
    matched_value: str        # 匹配的值
    snippet: str             # 代码片段
    remediation: str         # 修复建议
    metadata: dict = field(default_factory=dict)
```

**`ToolGuardResult` 聚合结果** (第106行):

```python
@dataclass
class ToolGuardResult:
    findings: list[GuardFinding]

    @property
    def is_safe(self) -> bool: ...
    @property
    def max_severity(self) -> GuardSeverity | None: ...
    @property
    def findings_count(self) -> int: ...

    def get_findings_by_severity(self, severity: GuardSeverity) -> list[GuardFinding]: ...
    def get_findings_by_category(self, category: GuardThreatCategory) -> list[GuardFinding]: ...
```

### 3.4 三大守卫实现

#### FilePathToolGuardian - 敏感文件守卫

**源码路径**: `src/qwenpaw/security/tool_guard/guardians/file_guardian.py`

```python
class FilePathToolGuardian(BaseToolGuardian):
    """基于路径的敏感文件守卫（always_run=True）"""

    def guard(self, tool_name: str, params: Any) -> list[GuardFinding]:
        """检测对敏感路径的访问"""
        # Shell 命令：从 token 中提取路径（使用 shlex.split）
        # 已知文件工具：检查 file_path、path 等特定参数
        # 其他工具：扫描字符串参数中"看起来像路径"的值

    # 默认保护路径：
    # - ~/.qwenpaw/.secret/
    # - ~/.copaw.secret/（兼容旧版）
```

#### RuleBasedToolGuardian - 规则守卫

**源码路径**: `src/qwenpaw/security/tool_guard/guardians/rule_guardian.py`

**`GuardRule` 规则类** (第169行):

```python
@dataclass
class GuardRule:
    id: str
    tools: list[str]           # 适用的工具列表
    params: list[str]          # 适用的参数名
    category: GuardThreatCategory
    severity: GuardSeverity
    patterns: list[re.Pattern]  # 预编译的正则
    exclude_patterns: list[re.Pattern]
    description: str
    remediation: str

    def applies_to_tool(self, tool_name: str) -> bool: ...
    def applies_to_param(self, param_name: str) -> bool: ...
    def match(self, value: str) -> bool: ...
```

**`rm` 命令特殊处理** (第360-420行):
- 检查删除目标是否在工作区外
- 生成中英文详细警告

#### ShellEvasionGuardian - 混淆检测守卫

**源码路径**: `src/qwenpaw/security/tool_guard/guardians/shell_evasion_guardian.py`

**核心逻辑** (第241-289行):

```python
class ShellEvasionGuardian(BaseToolGuardian):
    """检测命令混淆/逃避技术"""

    def guard(self, tool_name: str, params: dict[str, Any]) -> list[GuardFinding]:
        if tool_name != "execute_shell_command":
            return []
        # 运行 7 项检查，收集所有 findings
        return (
            self._check_command_substitution(command) +
            self._check_obfuscated_flags(command) +
            self._check_backslash_escaped_whitespace(command) +
            self._check_backslash_escaped_operators(command) +
            self._check_newlines(command) +
            self._check_comment_quote_desync(command) +
            self._check_quoted_newline(command)
        )
```

**7 项检测函数** (`shell_evasion_guardian.py` 第384-391行):

| 检测函数 | 行号 | 检测内容 | 示例 |
|---------|------|---------|------|
| `_check_command_substitution()` | 106-144 | 反引号、`$()`、`<()`、`>()、`$[]` | `` `ls` ``, `$(whoami)`, `<(cmd)` |
| `_check_obfuscated_flags()` | 147-199 | ANSI-C `$'...'`, locale `$"..."`, 空 flag | `$'echo \x61'` |
| `_check_backslash_escaped_whitespace()` | 202-222 | 反斜杠逃逸空白符 `\ `、`\t`、`\n` | `echo\ hello` |
| `_check_backslash_escaped_operators()` | 225-257 | 反斜杠逃逸操作符 `\；`、`\|`、`\&` | `ls \; rm -rf` |
| `_check_newlines()` | 260-299 | 隐藏新行 `\n`、回车 `\r`、分号分隔 | `echo "a\nb"` |
| `_check_comment_quote_desync()` | 312-340 | `#` 注释内引号导致状态机去同步 | `echo "done" # comment"` |
| `_check_quoted_newline()` | 343-374 | 引号内新行后跟 `#` 注释的攻击 | `"a\nb" # comment` |

**检测执行顺序** (第384-391行):

```python
_CHECKS: tuple[_ShellCheckFn, ...] = (
    _check_command_substitution,
    _check_obfuscated_flags,
    _check_backslash_escaped_whitespace,
    _check_backslash_escaped_operators,
    _check_newlines,
    _check_comment_quote_desync,
    _check_quoted_newline,
)
```

**`_QuoteState` 类** (第55-75行) - 字符级引号状态机:

```python
class _QuoteState:
    """Tracks shell quoting context character-by-character."""
    __slots__ = ("in_single", "in_double", "escaped")

    def update(self, char: str) -> None:
        """处理每个字符并更新状态"""

    def is_outside_quotes(self) -> bool:
        """当前位置是否在引号外部"""
```

**关键方法**:

| 方法 | 行号 | 功能 |
|------|------|------|
| `_extract_outside_single_quotes()` | 80-94 | 移除单引号内容，保留双引号内容（双引号内仍展开变量替换） |

**Shell 命令解析辅助函数** (`shell_evasion_guardian.py` 第92-103行):

```python
def _extract_paths_from_shell_command(command: str) -> list[str]:
    """从 shell 命令中提取路径 token"""
    # 使用 shlex.split() 进行 token 化
    # 处理重定向操作符: >, >>, 1>, 2>, <, <<, <<<
    # 处理附着重定向: >out.txt, 2>err.log
    # 通过 _looks_like_path_token() 启发式判断路径 token
```

**`log_findings()` 工具函数** (`utils.py` 第130-150行):

```python
def log_findings(findings: list[GuardFinding]) -> None:
    """将安全发现记录到日志"""
    for f in findings:
        logger.log(
            level=severity_to_log_level(f.severity),
            msg=f"[{f.guardian}] {f.category.value}: {f.title}",
            extra={"findings": f.to_dict()},
        )
```

### 3.4.6 `_extract_rm_targets()` rm 目标提取

**源码**: `rule_guardian.py` 第113-169行

此函数专门处理危险的 `rm` 命令，提取实际删除目标：

```python
def _extract_rm_targets(command: str) -> list[str]:
    """从 rm 命令中提取要删除的文件/目录路径"""
    # 处理转义模式: \\rm, \/bin/rm, $(which rm)
    # 处理命令替换: $(echo foo), `echo bar`
    # 处理通配符: *.txt, **/*.log
    # 返回实际的文件路径列表
```

**检测逻辑**:
1. 解析命令参数，分离选项和路径
2. 跳过选项（如 `-rf`, `-r`, `-f`）
3. 识别真实路径（排除命令名、选项等）
4. 返回有效路径列表供后续检查

### 3.4.7 守卫单例管理

**`get_guard_engine()`** (`engine.py` 第188-200行):

```python
_GUARD_ENGINE: ToolGuardEngine | None = None
_GUARD_ENGINE_LOCK = asyncio.Lock()

def get_guard_engine() -> ToolGuardEngine:
    """获取 ToolGuardEngine 单例（线程安全）"""
    global _GUARD_ENGINE
    if _GUARD_ENGINE is None:
        async with _GUARD_ENGINE_LOCK:
            if _GUARD_ENGINE is None:
                _GUARD_ENGINE = ToolGuardEngine()
    return _GUARD_ENGINE
```

**特点**:
- 双重检查锁定（Double-Checked Locking）模式
- 线程安全初始化
- 全局单例，节省资源

### 3.4.1 危险命令 YAML 规则

**规则文件**: `src/qwenpaw/security/tool_guard/rules/dangerous_shell_commands.yaml`

**完整规则表**:

| 规则 ID | 严重度 | 类别 | 检测内容 |
|---------|--------|------|----------|
| `TOOL_CMD_DANGEROUS_RM` | HIGH | command_injection | `rm -rf`, `del`, `Remove-Item` |
| `TOOL_CMD_DANGEROUS_MV` | HIGH | command_injection | `mv` 移动/重命名外部文件 |
| `TOOL_CMD_FS_DESTRUCTION` | CRITICAL | command_injection | `mkfs`, `mke2fs`, `dd of=/dev/*` |
| `TOOL_CMD_DOS_FORK_BOMB` | CRITICAL | resource_abuse | `:(){ :|:& };:`, `kill -9 -1` |
| `TOOL_CMD_PIPE_TO_SHELL` | CRITICAL | code_execution | `curl\|bash`, `wget\|bash` |
| `TOOL_CMD_REVERSE_SHELL` | CRITICAL | network_abuse | `/dev/tcp`, `nc -e`, `socat` |
| `TOOL_CMD_SYSTEM_TAMPERING` | HIGH | sensitive_file_access | `crontab -e`, `authorized_keys`, `/etc/sudoers` |
| `TOOL_CMD_UNSAFE_PERMISSIONS` | HIGH | privilege_escalation | `chmod 777`, `chattr +i` |
| `TOOL_CMD_OBFUSCATED_EXEC` | HIGH | code_execution | `base64 -d \| bash`, `openssl enc -aes` |
| `TOOL_CMD_SYSTEM_REBOOT` | CRITICAL | resource_abuse | `reboot`, `shutdown -h now` |
| `TOOL_CMD_SERVICE_RESTART` | HIGH | resource_abuse | `systemctl restart`, `service ... restart` |
| `TOOL_CMD_PROCESS_KILL` | HIGH | resource_abuse | `pkill -9`, `killall`, `taskkill /f` |
| `TOOL_CMD_PRIVILEGE_ESCALATION` | CRITICAL | privilege_escalation | `sudo su`, `su -`, `doas`, `pkexec` |
| `TOOL_CMD_IFS_INJECTION` | HIGH | code_execution | `$IFS` 变量注入 |
| `TOOL_CMD_CONTROL_CHARS` | CRITICAL | code_execution | 控制字符 0x00-0x08 |
| `TOOL_CMD_UNICODE_WHITESPACE` | HIGH | code_execution | Unicode NBSP (0xCA), ideographic space |
| `TOOL_CMD_PROC_ENVIRON` | HIGH | sensitive_file_access | `/proc/*/environ` 读取 |
| `TOOL_CMD_JQ_SYSTEM` | HIGH | code_execution | `jq` 的 `system()` 函数 |
| `TOOL_CMD_JQ_FILE_FLAGS` | HIGH | code_execution | `jq -f`, `--slurpfile`, `-L` 标志 |
| `TOOL_CMD_ZSH_DANGEROUS` | HIGH | code_execution | `zmodload`, `emulate -c`, `zf_*` 文件操作 |

**`rm` 命令特殊处理** (`rule_guardian.py` 第113-137行):

```python
def _check_rm_targets_outside_workspace(
    command: str,
) -> tuple[bool, list[str]]:
    """检查 rm 命令是否针对工作区外的文件"""
    # 解析 rm 命令参数
    # 检查每个目标路径是否在 WORKING_DIR 外
    # 返回 (是否有外部目标, 外部路径列表)
```

### 规则匹配引擎详解

**规则加载流程** (`rule_guardian.py` 第225-275行):

```python
def load_rules_from_yaml(yaml_path: Path) -> list[GuardRule]:
    """从单个 YAML 文件加载规则"""

def load_rules_from_directory(rules_dir: Path, rule_files: list[str]) -> list[GuardRule]:
    """从目录加载多个 YAML 文件规则"""
```

**默认规则文件** (第35-39行):

```python
_DEFAULT_RULES_DIR = Path(__file__).resolve().parent.parent / "rules"
_DEFAULT_RULE_FILES: list[str] = [
    "dangerous_shell_commands.yaml",
]
```

**`GuardRule.match()` 匹配逻辑** (第207-221行):

```python
def match(self, value: str) -> tuple[re.Match[str] | None, str | None]:
    # 第一步：检查排除模式
    if any(ep.search(value) for ep in self.compiled_exclude_patterns):
        return None, None

    # 第二步：遍历所有模式，搜索匹配
    for pattern in self.compiled_patterns:
        m = pattern.search(value)  # 使用 search() 而非 match()
        if m:
            return m, pattern.pattern
    return None, None
```

**匹配关键特性**:

| 特性 | 说明 |
|------|------|
| 排除模式优先 | `exclude_patterns` 命中的规则直接跳过 |
| `re.search()` | 在字符串任意位置匹配，不只是开头 |
| 大小写不敏感 | 所有模式编译时带 `re.IGNORECASE` |
| 返回结构 | `(match对象, 模式字符串)` 便于调试 |

**`RuleBasedToolGuardian.guard()` 完整流程** (第360-418行):

```python
def guard(self, tool_name: str, params: dict[str, Any]) -> list[GuardFinding]:
    # 1. 过滤适用于该工具的规则
    applicable_rules = [r for r in self.rules if r.applies_to_tool(tool_name)]

    # 2. 遍历每个参数
    for param_name, param_value in params.items():
        value_str = str(param_value)

        # 3. 检查参数适用的规则
        for rule in applicable_rules:
            if not rule.applies_to_param(param_name):
                continue

            # 4. 执行匹配
            match_obj, pattern_str = rule.match(value_str)

            # 5. 特殊处理 rm 命令
            if rule.id == "TOOL_CMD_DANGEROUS_RM":
                is_dangerous, outside_paths = _check_rm_targets_outside_workspace(value_str)
                if is_dangerous:
                    # 生成警告，包含外部路径详情
```

### 规则 YAML 格式详解

**完整 YAML 结构** (第7-17行):

```yaml
- id: RULE_ID                      # 唯一规则标识符
  tools: [execute_shell_command]  # 目标工具列表（空=所有工具）
  params: [command]                # 目标参数列表（空=所有参数）
  category: command_injection      # 威胁类别枚举
  severity: HIGH                   # 严重等级: CRITICAL/HIGH/MEDIUM/LOW/INFO
  patterns:                       # 正则表达式列表
    - "regex_pattern_1"
    - "regex_pattern_2"
  exclude_patterns:               # 排除模式（匹配则跳过）
    - "^\\s*#"
  description: "人类可读描述"
  remediation: "建议修复方案"
```

**规则优先级**:
1. `exclude_patterns` > `patterns` (排除优先)
2. 同一规则内多模式为 OR 关系
3. 不同规则为独立检查，结果聚合

### 三大守卫协同机制

**守卫对比表**:

| 守卫 | 监控工具 | 检测方式 | 威胁类型 |
|------|----------|----------|----------|
| `FilePathToolGuardian` | 文件操作工具 (read_file, write_file等) | 路径规范化 + 保护区匹配 | 敏感文件访问 |
| `RuleBasedToolGuardian` | execute_shell_command | 正则模式匹配 | 命令注入、危险命令 |
| `ShellEvasionGuardian` | execute_shell_command | 状态机 + 混淆检测 | 命令混淆/逃避 |

**`ToolGuardEngine` 编排** (`engine.py` 第82-103行):

```python
# 默认三大守卫
_DEFAULT_GUARDIANS: tuple[type[BaseToolGuardian], ...] = (
    FilePathToolGuardian,     # 文件路径守卫
    RuleBasedToolGuardian,     # 规则守卫
    ShellEvasionGuardian,     # 混淆检测守卫
)
```

### 3.4.2 ToolGuardResult 聚合结果

**`ToolGuardResult`** (`models.py` 第93-137行):

```python
@dataclass
class ToolGuardResult:
    tool_name: str
    params: dict[str, Any]
    findings: list[GuardFinding] = field(default_factory=list)
    guard_duration_seconds: float = 0.0
    guardians_used: list[str] = field(default_factory=list)
    guardians_failed: list[dict[str, str]] = field(default_factory=list)
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    @property
    def is_safe(self) -> bool:
        """无 CRITICAL 或 HIGH 级别发现"""
        return not any(
            f.severity in (GuardSeverity.CRITICAL, GuardSeverity.HIGH)
            for f in self.findings
        )

    @property
    def max_severity(self) -> GuardSeverity | None:
        """返回最高严重等级"""
```

**GuardFinding 完整结构** (`models.py` 第60-87行):

```python
@dataclass
class GuardFinding:
    id: str                    # 唯一标识 (UUID)
    rule_id: str              # 触发规则ID
    category: GuardThreatCategory  # 威胁类别
    severity: GuardSeverity   # 严重等级
    title: str                # 发现标题
    description: str          # 详细描述
    tool_name: str            # 工具名
    param_name: str | None = None  # 参数名
    matched_value: str | None = None  # 匹配的值
    matched_pattern: str | None = None  # 匹配的正则
    snippet: str | None = None  # 代码片段
    remediation: str | None = None  # 修复建议
    guardian: str | None = None  # 来源守卫
    metadata: dict[str, Any] = field(default_factory=dict)  # 元数据
```

### 3.4.3 守卫启用优先级

**`_guard_enabled()` 函数** (`engine.py` 第36-51行):

```
优先级: 环境变量 > config.json > 默认 (True)
```

```python
def _guard_enabled() -> bool:
    """决定是否启用工具守卫"""
    # 1. 检查 QWENPAW_TOOL_GUARD_ENABLED 环境变量
    # 2. 检查 config.json security.tool_guard.enabled
    # 3. 返回默认值 True
```

**`resolve_guarded_tools()` (`utils.py` 第45-72行):

```python
def resolve_guarded_tools(
    user_defined: set[str] | None,
    config_guard: Any,
) -> set[str] | None:
    """解析守卫工具集合

    优先级:
    1. user_defined (构造函数提供)
    2. QWENPAW_TOOL_GUARD_TOOLS 环境变量
    3. config.json security.tool_guard.scope
    4. 内置高风险默认集合
    """

### 3.4.4 ToolGuard 完整工作流程

**工具调用拦截流程** (`engine.py` 第189-215行):

```
ToolGuardEngine.guard(tool_name, params)
         │
         ├─► is_guarded(tool_name)? ──No──► return ToolGuardResult(is_safe=True)
         │
         ├─► 遍历所有 guardians:
         │         │
         │         ├─► FilePathToolGuardian (always_run=True)
         │         │         ├─► 敏感路径检查
         │         │         └─► findings + governance
         │         │
         │         ├─► RuleBasedToolGuardian
         │         │         ├─► 规则匹配 (17条 YAML 规则)
         │         │         ├─► rm 特殊处理
         │         │         └─► findings + governance
         │         │
         │         └─► ShellEvasionGuardian (仅 execute_shell_command)
         │                   └─► 7项混淆检测
         │
         └─► 聚合所有 findings → ToolGuardResult
                   │
                   ├─► is_safe=True → 放行
                   ├─► CRITICAL/HIGH → 阻止 + 抛异常
                   └─► MEDIUM/LOW → 记录 + 返回
```

**治理行动 (Governance Actions)** (`models.py` 第137-180行):

| 行动 | 触发条件 | 行为 |
|------|---------|------|
| `BLOCK` | CRITICAL 级别 | 立即阻止工具调用，抛出 `ToolGuardBlock` 异常 |
| `ESCALATE` | HIGH 级别 + 用户未确认 | 暂停执行，等待用户审批 (Approval) |
| `WARN` | MEDIUM 级别 | 记录警告，继续执行 |
| `LOG` | LOW/INFO 级别 | 仅记录日志 |

**BaseToolGuardian 基类** (`guardians/base.py` 第16-52行):

```python
class BaseToolGuardian(ABC, Generic[P]):
    """所有守卫的基类"""

    @property
    @abstractmethod
    def name(self) -> str:
        """守卫名称"""

    @property
    def always_run(self) -> bool:
        """是否在快速路径也运行（默认 False）"""
        return False

    @abstractmethod
    def guard(self, tool_name: str, params: P) -> list[GuardFinding]:
        """执行守卫检查"""

    def governance_action(
        self, finding: GuardFinding
    ) -> GovernanceAction | None:
        """判断治理行动（可重写）"""
        return finding.severity.to_governance_action()
```

**GuardSeverity 到 GovernanceAction 映射** (`models.py` 第180-195行):

```python
CRITICAL → BLOCK
HIGH     → ESCALATE (需用户确认)
MEDIUM   → WARN
LOW/INFO → LOG
SAFE     → (无行动)
```

### 3.4.5 集成点

**ToolGuard 在 AgentRunner 中的集成** (`runner.py` 第480-510行):

```
query_handler()
    │
    ├─► 解析工具调用: tool_name, params
    │
    ├─► ToolGuardEngine.guard(tool_name, params)
    │         │
    │         ├─► BLOCK → 抛出 ToolGuardBlock
    │         │
    │         ├─► ESCALATE → 暂停，等待 Approval
    │         │         ├─► create_pending() → 推送消息给用户
    │         │         └─► future.await() → 等待用户审批
    │         │
    │         └─► WARN/LOG → 继续执行
    │
    └─► 执行工具调用
```

**环境变量配置**:

| 环境变量 | 功能 | 默认值 |
|---------|------|--------|
| `QWENPAW_TOOL_GUARD_ENABLED` | 启用/禁用守卫 | `true` |
| `QWENPAW_TOOL_GUARD_TOOLS` | 守卫工具范围 | 高风险工具 |
| `QWENPAW_TOOL_GUARD_RULES_DIR` | 自定义规则目录 | 内置规则 |

**配置文件路径** (`config.py`):

```python
security:
  tool_guard:
    enabled: true           # 启用开关
    scope: ["execute_shell_command", "write_file", ...]  # 守卫范围
    rules_dir: null        # 自定义规则目录
    approval_required: true  # HIGH 级别是否需要审批
```

### 3.5 审批系统 (Approval)

#### 3.5.1 概述

**源码路径**: `src/qwenpaw/app/approvals/`

当 ToolGuard 发现问题但需要用户确认时，进入审批流程。审批系统负责：
- 管理待审批请求的生命周期
- 与用户交互获取审批决定
- 防止审批结果被滥用

```
src/qwenpaw/app/approvals/
├── __init__.py           # 模块导出
└── service.py            # ApprovalService 核心服务
```

#### 3.5.2 ApprovalDecision 枚举

**源码**: `src/qwenpaw/security/tool_guard/approval.py` 第9-14行

```python
class ApprovalDecision(str, Enum):
    APPROVED = "approved"   # 用户批准
    DENIED = "denied"      # 用户拒绝
    TIMEOUT = "timeout"    # 超时未响应
```

#### 3.5.3 PendingApproval 数据模型

**源码**: `src/qwenpaw/app/approvals/service.py` 第45-56行

```python
@dataclass
class PendingApproval:
    """待审批记录"""
    request_id: str                    # 唯一标识 (UUID)
    session_id: str                    # 会话 ID
    user_id: str                       # 用户 ID
    channel: str                       # 渠道标识
    tool_name: str                     # 工具名称
    created_at: float                  # 创建时间戳
    future: asyncio.Future[ApprovalDecision]  # 异步 Future
    status: str = "pending"            # 状态
    resolved_at: float | None = None   # 解决时间戳
    result_summary: str = ""           # 安全发现摘要 (markdown)
    findings_count: int = 0            # 发现数量
    extra: dict[str, Any] = field(default_factory=dict)  # 额外数据
```

**状态流转**:

| 状态 | 流转至 | 触发条件 |
|------|--------|----------|
| `pending` | `approved` | 用户执行 `/daemon approve` |
| `pending` | `denied` | 用户拒绝审批请求 |
| `pending` | `timeout` | GC 清理超时记录 |
| `pending` | `superseded` | 工具调用被重放 |
| `approved` | (删除) | `consume_approval()` 被调用 |

#### 3.5.4 ApprovalService 核心服务

**源码**: `src/qwenpaw/app/approvals/service.py` 第63-293行

**核心方法表**:

| 方法 | 行号 | 功能 |
|------|------|------|
| `set_channel_manager()` | 73 | 注入渠道管理器用于推送通知 |
| `create_pending()` | 79-105 | 创建待审批记录 |
| `resolve_request()` | 107-125 | 解决审批请求（设置 Future 结果） |
| `get_request()` | 127-133 | 获取请求（待处理或已完成） |
| `get_pending_by_session()` | 135-149 | 获取会话的下一个待审批 |
| `get_all_pending_by_session()` | 151-161 | 获取会话所有待审批 |
| `cancel_stale_pending_for_tool_call()` | 163-194 | 取消重复的待审批 |
| `consume_approval()` | 196-229 | 检查并消费一次性审批 |
| `get_approval_service()` | 287-293 | 单例访问器 |

#### 3.5.5 审批创建流程

**`create_pending()`** (第79-105行):

```
create_pending(session_id, user_id, channel, tool_name, result)
         │
         ├─► 生成 request_id (UUID)
         │
         ├─► 创建 PendingApproval 记录
         │         │
         │         ├─► format_findings_summary(result) → result_summary
         │         │
         │         └─► asyncio.create_future() → future
         │
         ├─► 加锁写入 self._pending
         │
         ├─► GC 清理过期记录
         │
         └─► 返回 PendingApproval
```

#### 3.5.6 参数验证机制

**`consume_approval()`** (第196-229行) 防止审批结果滥用：

```
consume_approval(session_id, tool_name, tool_params)
         │
         ├─► 查找已批准的记录
         │
         ├─► tool_params 是否提供？
         │         │
         │         ├─► 是：对比存储的 tool_call.input
         │         │         │
         │         │         ├─► 不匹配 → 删除记录，返回 False
         │         │         │
         │         │         └─► 匹配 → 删除记录，返回 True
         │         │
         │         └─► 否：删除记录，返回 True
         │
         └─► 返回是否成功消费
```

**攻击场景防护**:
- 用户批准了 `rm foo.txt`
- 攻击者尝试执行 `rm -rf /`
- `consume_approval()` 检测到参数不匹配
- 审批被拒绝，工具被阻止

#### 3.5.7 垃圾回收机制

**GC 常量** (第28-35行):

| 常量 | 值 | 说明 |
|------|-----|------|
| `_GC_PENDING_MAX_AGE_SECONDS` | 1800s (30分钟) | 待处理记录最大存活时间 |
| `_GC_MAX_PENDING` | 200 | 待处理记录最大数量 |
| `_GC_MAX_AGE_SECONDS` | 3600s (1小时) | 已完成记录最大存活时间 |
| `_GC_MAX_COMPLETED` | 500 | 已完成记录最大数量 |

**GC 流程**:
```
PendingApproval 创建/解决
         │
         ├─► _gc_pending_locked()
         │         │
         │         ├─► 清理超时的待处理记录
         │         │         │
         │         │         └─► future.set_result(TIMEOUT)
         │         │
         │         └─► 清理超出数量限制的记录
         │
         └─► _gc_completed_locked()
                   │
                   └─► 清理超时的已完成记录
```

#### 3.5.8 ToolGuard 完整审批流程

```
ToolGuardEngine.guard(tool_name, params)
         │
         ├── is_denied() → True? ──Yes──> 返回 auto_denied
         │
         ├── is_guarded() → True?
         │     ├── yes + preapproved? ──Yes──> 执行
         │     └── yes + not preapproved
         │           │
         │           └── 运行所有守卫 → 有 findings?
         │                 ├── yes → ApprovalService.create_pending()
         │                 │              │
         │                 │              └─► 等待用户审批 (future.await)
         │                 │
         │                 └── no → 执行
         │
         └── only_always_run=True?
               └── FilePathToolGuardian (always_run=True) 始终运行

用户审批:
         │
         └─► /daemon approve
                   │
                   └─► ApprovalService.resolve_request(request_id, decision)
                             │
                             └─► future.set_result(decision)
```

#### 3.5.9 发现摘要格式化

**源码**: `src/qwenpaw/security/tool_guard/approval.py` 第22-40行

```python
def format_findings_summary(result: "ToolGuardResult", *, max_items: int = 3) -> str:
    """将发现列表格式化为 markdown 摘要"""
    lines = ["## Security Findings\n"]
    for f in result.findings[:max_items]:
        severity_icon = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡"}.get(f.severity, "⚪️")
        lines.append(f"{severity_icon} **{f.severity}**: {f.title}")
        lines.append(f"   - {f.description}")
        lines.append(f"   - Remediation: {f.remediation}")
    if result.findings_count > max_items:
        lines.append(f"... and {result.findings_count - max_items} more finding(s) omitted")
    return "\n".join(lines)
```

#### 3.5.10 完整守卫决策流程

```
ToolGuardEngine.guard(tool_name, params)
    │
    ├── is_denied() → True? ──Yes──> 返回 auto_denied
    │
    ├── is_guarded() → True?
    │     ├── yes + preapproved? ──Yes──> 执行
    │     └── yes + not preapproved
    │           │
    │           └── 运行所有守卫 → 有 findings?
    │                 ├── yes → SuspendedPermission (等待用户审批)
    │                 └── no → 执行
    │
    └── only_always_run=True?
          └── FilePathToolGuardian (always_run=True) 始终运行
```

#### 3.5.11 兄弟工具调用重放系统

当一个工具调用需要审批时，同一助手消息中的其他工具调用会被存储并重放：

**`_extract_sibling_tool_calls()`** (tool_guard_mixin.py 第116-128行):
```python
def _extract_sibling_tool_calls(self, msgs: list) -> list[dict]:
    """从上一条助手消息中提取所有 tool_use 块"""
    # 查找最后一条助手消息
    # 提取所有 tool_use 类型的 content blocks
```

**重放队列机制**:
```
用户批准工具调用
         │
         ├─► 工具调用执行
         │
         ├─► _tool_guard_replay_queue 队列
         │         │
         │         ├─► _filter_pending_replay_queue() 过滤已执行的
         │         │
         │         └─► _emit_next_replay_tool_call() 发射下一个
         │
         └─► cancel_stale_pending_for_tool_call() 取消旧记录
                   │
                   └─► status → "superseded"
```

#### 3.5.12 ToolGuardMixin 集成 (tool_guard_mixin.py)

**MRO 继承顺序**:
```
QwenPawAgent → ToolGuardMixin → agentscope.agent.ReActAgent
```

**`_acting()` 拦截流程** (第291-344行):

```python
async def _acting(self, tool_call: dict[str, Any]) -> Any:
    # 1. 检查 headless 模式标志
    if ctx.get("_headless_tool_guard", "true").lower() == "false":
        return await super()._acting(tool_call)  # Mission Mode 绕过

    # 2. 获取守卫锁（防止并行工具调用竞态）
    async with self._tool_guard_lock:
        # 3. 执行守卫决策
        action = await self._decide_guard_action(tool_call)

    # 4. 在锁外执行守卫操作（允许并行执行）
    if action:
        return await self._execute_guard_action(action, tool_call)

    # 5. 无守卫决策 → 执行工具
    return await super()._acting(tool_call)
```

**`_decide_guard_action()` 决策树** (第346-400行):

```
工具名称在 denied_tools 中?
         │
    Yes ─┴─> 返回 _GuardAction("auto_denied")
         │
         No
         │
         ▼
检查预批准 (consume_approval)
         │
    Yes ─┴─> 返回 _GuardAction("preapproved")
         │
         No
         │
         ▼
运行所有守卫规则
         │
         ▼
findings > 0 且 should_require_approval()?
         │
    Yes ─┴─> 返回 _GuardAction("needs_approval")
         │
         No
         │
         ▼
返回 None（无守卫决策，继续执行）
```

**`_acting_with_approval()` 审批等待流程** (第531-656行):

```python
async def _acting_with_approval(self, tool_call, pending: PendingApproval):
    # 1. 从原始助手消息提取思考块
    thinking_blocks = _extract_thinking_blocks(original_msg)

    # 2. 提取兄弟工具调用
    sibling_tool_calls = _extract_sibling_tool_calls(msgs)

    # 3. 取消同一 tool_call_id 的旧待审批记录
    svc.cancel_stale_pending_for_tool_call(session_id, tool_call_id)

    # 4. 创建待审批记录
    pending = await svc.create_pending(...)

    # 5. 格式化拒绝消息给用户
    denial_msg = _format_denial_message(pending, findings)

    # 6. 等待用户审批 (future.await)
    decision = await pending.future

    # 7. 根据决定处理
    if decision == APPROVED:
        # 执行工具调用
        # 重放兄弟工具调用
    else:
        # 返回拒绝消息
```

#### 3.5.13 安全考虑

**参数不匹配防护** (service.py 第241-259行):

```python
async def consume_approval(self, session_id, tool_name, tool_params=None):
    # ...
    if tool_params is not None:
        approved_call = completed.extra.get("tool_call", {})
        approved_params = approved_call.get("input", {})

        # 防止: 批准了 rm foo.txt 但执行了 rm -rf /
        if approved_params != tool_params:
            logger.warning(
                "Tool guard: params mismatch for '%s' (session %s)",
                tool_name,
                session_id[:8],
            )
            del self._completed[key]
            return False
```

**会话隔离**:
- 每个审批绑定到 `session_id`
- 审批只能被同一会话消费
- FIFO 顺序防止竞态条件

**拒绝标记清理** (runner.py 第765-873行):
```python
TOOL_GUARD_DENIED_MARK = "tool_guard_denied"
# 拒绝后清理会话记忆中标记的消息
```

### 3.6 技能安全扫描 (Skill Scanner)

#### 扫描流程

```
扫描请求 → PatternAnalyzer → 规则匹配 → ScanResult
                ↓
            白名单检查
                ↓
            阻塞/警告/放行
```

#### 扫描策略

```python
class ScanPolicy(Enum):
    """扫描策略"""

    BLOCK = "block"    # 阻止不安全的技能
    WARN = "warn"      # 仅记录警告（默认）
    OFF = "off"        # 禁用扫描

class SkillScannerConfig(BaseModel):
    """技能扫描配置"""

    enabled: bool = True
    policy: ScanPolicy = ScanPolicy.WARN
    blocked_skills: List[str] = []
    whitelist: List[str] = []
```

#### 扫描结果模型

```python
@dataclass
class Finding:
    """扫描发现"""

    rule_id: str
    severity: str  # critical, high, medium, low
    message: str
    file_path: Optional[str] = None
    line_number: Optional[int] = None

@dataclass
class ScanResult:
    """扫描结果"""

    skill_name: str
    status: str  # safe, warning, blocked
    findings: List[Finding]
    scan_time: datetime
```

#### 扫描 API

```python
def scan_skill_directory(skill_dir: str) -> ScanResult:
    """扫描技能目录"""
    scanner = SkillScanner()
    return scanner.scan(skill_dir)

def is_skill_whitelisted(skill_name: str) -> bool:
    """检查技能是否在白名单"""
    return skill_name in config.security.skill_scanner.whitelist

def get_blocked_history() -> List[str]:
    """获取被阻止的技能历史"""
    return list(_blocked_history.keys())
```

#### 安全规则示例

```python
# rules/dangerous_patterns.py

DANGEROUS_PATTERNS = [
    {
        "id": "os_system_call",
        "pattern": r"os\.system\s*\(",
        "severity": "high",
        "message": "检测到 os.system() 调用，可能存在命令注入风险"
    },
    {
        "id": "eval_usage",
        "pattern": r"\beval\s*\(",
        "severity": "critical",
        "message": "检测到 eval() 使用，可能执行任意代码"
    },
    {
        "id": "subprocess_shell",
        "pattern": r"subprocess\.run\(.*shell\s*=\s*True",
        "severity": "high",
        "message": "subprocess shell=True 可能导致命令注入"
    },
    {
        "id": "secret_exfiltration",
        "pattern": r"os\.environ\[.*SECRET|API_KEY.*\]",
        "severity": "critical",
        "message": "检测到环境变量密钥访问，可能存在数据泄露"
    },
]
```

---

## 4. EnvStore 环境变量存储

**源码路径**: `src/qwenpaw/envs/store.py`

### 两层持久化策略 (store.py:10-18)

```
┌─────────────────────────────────────────────┐
│              EnvStore 双层存储                │
├─────────────────────────────────────────────┤
│                                             │
│  envs.json (持久化)                          │
│  └─► 进程重启后保留                          │
│  └─► 加密存储 (ENC: 前缀)                   │
│                                             │
│  os.environ (进程内)                        │
│  └─► 注入当前 Python 进程                    │
│  └─► 供 os.getenv() 和子进程使用            │
│                                             │
└─────────────────────────────────────────────┘
```

### 核心 API

| 函数 | 行号 | 功能 |
|------|------|------|
| `load_envs()` | 93 | 加载并透明解密环境变量 |
| `save_envs()` | 137 | 写入加密环境变量并同步到 os.environ |
| `set_env_var()` | 152 | 设置单个环境变量 |
| `delete_env_var()` | 159 | 删除单个环境变量 |
| `load_envs_into_environ()` | 165 | 应用安全环境变量到 os.environ |

### 安全特性

| 特性 | 行号 | 说明 |
|------|------|------|
| 引导密钥保护 | 67-72 | `QWENPAW_WORKING_DIR` 等不注入 environ |
| 文件权限 | 44, 145 | `0o600` 保护 envs.json |
| 父目录权限 | 38-45 | `_prepare_secret_parent()` 确保 `0o700` |
| 遗留迁移 | 50-79 | 检测明文并重新加密 |

---

### 4.1 认证系统 (Auth)

**源码路径**: `src/qwenpaw/app/auth.py`

### 核心常量 (第42-68行)

```python
AUTH_FILE = SECRET_DIR / "auth.json"  # 认证数据存储路径
TOKEN_EXPIRY_SECONDS = 7 * 24 * 3600  # 默认7天
TOKEN_EXPIRY_MAX = 100 * 365 * 24 * 3600  # "永久"令牌最大100年

_PUBLIC_PATHS = frozenset({
    "/api/auth/login",
    "/api/auth/status",
    "/api/auth/register",
    ...
})
```

### 公开路径

无需认证的路径：

| 路径 | 说明 |
|------|------|
| `/api/auth/login` | 登录 |
| `/api/auth/register` | 注册 |
| `/api/auth/status` | 认证状态 |
| `/api/version` | 版本信息 |
| `/api/plugins` | 插件列表 |
| `/assets/*` | 静态资源 |

### 密码处理 (第93-108行)

```python
def _hash_password(password: str, salt: Optional[str] = None) -> tuple[str, str]:
    """使用加盐 SHA-256 哈希密码"""
    if salt is None:
        salt = secrets.token_hex(16)
    h = hashlib.sha256((salt + password).encode("utf-8")).hexdigest()
    return h, salt

def verify_password(password: str, stored_hash: str, salt: str) -> bool:
    """使用 timing-safe 比较验证密码"""
    h, _ = _hash_password(password, salt)
    return hmac.compare_digest(h, stored_hash)
```

**安全特性**:
- 加盐 SHA-256 哈希
- `hmac.compare_digest` 防止时序攻击
- 无外部依赖（仅标准库）

### JWT 令牌 (第115-163行)

**令牌格式**: `{payload_b64}.{hmac_hex_signature}`

```python
def create_token(username: str, expiry_seconds: Optional[int] = None) -> str:
    """创建 HMAC 签名的令牌"""
    # payload = json.dumps({"sub": username, "exp": timestamp, "iat": timestamp, "jti": token_id})
    # signature = HMAC-SHA256(secret, payload_b64)
```

**Payload 结构**:

| 字段 | 说明 |
|------|------|
| `sub` | 用户名 |
| `exp` | 过期时间戳 |
| `iat` | 签发时间戳 |
| `jti` | 唯一令牌 ID（用于撤销） |

### 令牌验证 (第166-198行)

```python
def verify_token(token: str) -> Optional[str]:
    """验证令牌，有效则返回用户名"""
    # 1. 分割令牌，验证 HMAC 签名
    # 2. 检查过期 (exp < time.time())
    # 3. 检查撤销列表 (jti 查找)
    # 返回 payload.get("sub") 成功
```

### 令牌撤销 (第261-327行)

**单个撤销** (`revoke_token`):
1. 解析令牌提取 `jti` 和 `exp`
2. 添加到 `revoked_tokens_meta` 字典 (O(1) 查找)
3. 定期清理过期条目

**全部撤销** (`revoke_all_tokens`):
1. 生成新的 JWT 密钥
2. 清空撤销列表
3. 所有现有令牌立即失效

### AuthMiddleware (第567-636行)

```python
class AuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        # 1. _should_skip_auth() 检查:
        #    - 认证未启用
        #    - 无注册用户
        #    - OPTIONS 请求
        #    - 公开路径/前缀
        #    - 非 /api/ 路由
        #    - 本地地址 (127.0.0.1, ::1)
        # 2. _extract_token() 从 Authorization: Bearer <token> 提取
        # 3. verify_token() 验证
```

### 认证流程

```
请求 → AuthMiddleware.dispatch()
    │
    ├─► _should_skip_auth() → True → 直接放行 (公开路径)
    │
    ├─► _extract_token() 提取令牌
    │
    ├─► verify_token() 验证
    │     │
    │     ├─► HMAC 签名有效?
    │     ├─► 令牌未过期 (exp < time.time())?
    │     └─► 令牌未撤销 (jti 不在列表)?
    │
    ├─► 有效 → request.state.user = username → call_next()
    │
    └─► 无效 → 401 Response {"detail": "Invalid or expired token"}
```

### REST API 端点 (`routers/auth.py`)

| 端点 | 行号 | 方法 | 说明 |
|------|------|------|------|
| `/auth/login` | 49 | POST | 用户名/密码认证 |
| `/auth/register` | 68 | POST | 注册用户 |
| `/auth/status` | 106 | GET | 检查认证状态 |
| `/auth/verify` | 115 | GET | 验证令牌有效性 |
| `/auth/update-profile` | 145 | POST | 更新用户名/密码 |
| `/auth/revoke-token` | 206 | POST | 撤销指定令牌 |
| `/auth/revoke-all-tokens` | 254 | POST | 撤销所有令牌 |

### 环境变量

| 变量 | 说明 |
|------|------|
| `QWENPAW_AUTH_ENABLED` | 启用认证 (`true`, `1`, `yes`) |
| `QWENPAW_AUTH_USERNAME` | 自动注册管理员用户名 |
| `QWENPAW_AUTH_PASSWORD` | 自动注册管理员密码 |

### 安全设计要点

1. **无 PyJWT 依赖** - 使用自定义 HMAC-SHA256 实现
2. **时序安全比较** - `hmac.compare_digest()` 全程使用
3. **单用户设计** - 只允许注册一个账户
4. **令牌 ID (jti)** - 支持单个令牌撤销
5. **密钥加密** - JWT 密钥加密存储在 `auth.json`
6. **自动清理** - 过期条目自动从撤销列表移除
7. **本地绕过** - CLI 本地运行无需认证

---

## 5. Backup 备份系统

**源码路径**: `src/qwenpaw/backup/`

### 备份模块结构

```
backup/
├── models.py              # BackupScope, BackupMeta 数据模型
├── orchestration.py       # 恢复编排
├── _ops/
│   ├── create.py         # 备份创建流 (SSE 流式)
│   ├── create_helpers.py # 打包辅助
│   ├── restore.py        # 备份恢复核心
│   ├── restore_helpers.py # 恢复辅助
│   └── storage.py        # 存储管理 (list/delete/export/import)
└── _utils/
    ├── constants.py      # 路径前缀、备份 ID 验证
    ├── meta.py           # 元数据生成和读取
    └── safe_swap.py      # 原子目录交换
```

### REST API 端点 (routers/backup.py)

| 方法 | 端点 | 函数 | 说明 |
|------|------|------|------|
| `POST` | `/backups/stream` | `create_backup_stream` | 创建备份 (SSE 流式进度) |
| `GET` | `/backups` | `list_backups` | 列出所有备份 |
| `POST` | `/backups/delete` | `delete_backups` | 删除备份 |
| `POST` | `/backups/import` | `import_backup` | 导入备份 zip |
| `GET` | `/backups/{backup_id}` | `get_backup` | 获取备份详情 |
| `POST` | `/backups/{backup_id}/restore` | `restore_backup` | 恢复备份 |
| `GET` | `/backups/{backup_id}/export` | `export_backup` | 导出备份 zip |

### SSE 进度事件类型 (create.py:28)

| 事件 | 字段 | 说明 |
|------|------|------|
| `start` | `total_agents`, `percent=0` | 开始 |
| `agent` | `agent_id`, `index`, `total`, `percent` | 每个 Agent 处理进度 |
| `saving` | `percent=90` | 保存元数据 |
| `done` | `meta`, `percent=100` | 完成 |
| `error` | `message` | 错误 |

### 核心数据模型表 (models.py)

| 模型 | 行号 | 字段 |
|------|------|------|
| `BackupScope` | 9 | `include_agents`, `include_global_config`, `include_secrets`, `include_skill_pool` |
| `BackupMeta` | 23 | `id`, `name`, `description`, `created_at`, `version`, `scope`, `agent_count`, `qwenpaw_version` |
| `CreateBackupRequest` | 51 | `name`, `description`, `scope`, `agents` |
| `RestoreBackupRequest` | 61 | `include_agents`, `agent_ids`, `include_global_config`, `include_secrets`, `include_skill_pool`, `mode` |
| `BackupDetail` | 105 | 继承 BackupMeta + `workspace_stats` |

### BackupScope 备份范围 (models.py:14)

```python
class BackupScope:
    include_agents: bool           # 包含 Agent 工作区
    include_global_config: bool     # 包含全局 config.json
    include_secrets: bool          # 包含 secrets 目录
    include_skill_pool: bool       # 包含 skill pool 目录
```

### 创建流程 (create.py:30-167)

```
create_stream(req)
    │
    ├─► 创建 BackupMeta
    │
    ├─► _compute_initial_agents() 验证 Agent 存在性
    │
    ├─► 进度回调:
    │     start → agent (每个) → saving → done/error
    │
    ├─► 后台线程执行压缩
    │
    └─► 临时文件 .tmp，成功后原子替换 .zip
```

### 恢复流程 (restore.py:186-260)

**两阶段恢复协议**:
```
Phase 1: 提取到 .restore_tmp 临时目录
Phase 2: 原子交换 old → .restore_old, tmp → dst
Phase 3: 删除 .restore_old
```

**Config 合并策略**:
| 模式 | 策略 |
|------|------|
| `full` | 完整替换 config.json |
| `custom` | backup 顶层 keys 获胜，`agents.profiles` 只覆盖 restore_aids |

### 原子目录交换 (safe_swap.py:9-23)

**三阶段协议**:
```
1. 提取到 .restore_tmp
2. 原子交换: old → .restore_old, tmp → dst
3. 删除 .restore_old
```

**安全特性**:
- 崩溃恢复：检测并清理遗留临时目录
- Zip Slip 防护：验证解压路径不超出目标基准目录
- 线程安全：每个目标路径有独立的 threading.Lock

### 并发控制 (orchestration.py:40)

```
恢复编排流程:
    │
    ├─► 停止受影响的 Agent (含文件句柄)
    │
    ├─► 执行 restore
    │     │
    │     └─► _stage_secrets() → handle_master_key_conflict()
    │     │
    │     └─► extract_to_tmp() → 提取到 .restore_tmp
    │     │
    │     └─► commit_tmp() → 原子交换
    │
    └─► finally: 重启已停止的 Agent

恢复后密钥重载 (orchestration.py:339-340):
    │
    └─► if SECRET_DIR in committed:
              reload_master_key_from_disk()
                    │
                    ▼
         清除 _cached_master_key, _cached_fernet = None
                    │
                    ▼
         从 .master_key 文件读取新密钥
                    │
                    ▼
         _try_keyring_set(new_key)  (同步 keyring)
```

### Zip 路径前缀 (constants.py:16-19)

| 前缀 | 内容 |
|------|------|
| `data/workspaces/` | Agent 工作区 |
| `data/secrets/` | 密钥目录 |
| `data/skill_pool/` | Skill 池 |
| `data/config.json` | 全局配置 |

### Master Key 冲突处理 (restore_helpers.py:87)

```
备份前:
    └─► 备份当前 master key 到 BACKUP_DIR/_pre_restore_keys/

恢复时:
    └─► handle_master_key_conflict() 处理密钥冲突
```

**冲突处理流程** (restore_helpers.py:108-156):

```
检测到备份 .master_key 与当前不同
         │
         ▼
备份当前密钥到 BACKUP_DIR/_pre_restore_keys/<UTC-timestamp>.master_key.bak
         │
         ▼
用备份中的密钥替换当前密钥
         │
         ▼
备份存在 BACKUP_DIR 外（不被 atomic swap 影响）
```

### 崩溃恢复场景 (safe_swap.py:65-143)

| 场景 | 检测条件 | 恢复动作 |
|------|----------|----------|
| 场景1 | `.restore_old` 存在, base_dir 不存在 | 重命名 old → base 恢复 |
| 场景2 | `.restore_tmp` 存在, base_dir 存在 | 删除不完整的 tmp |
| 场景3 | `.restore_old` 存在, base_dir 存在 | 删除多余的 old |

### 回滚机制 (_swap_directories)

```python
def _swap_directories(dst, tmp_dst, old_dst):
    if dst.exists():
        dst.rename(old_dst)  # 保存原始到 .restore_old
    try:
        tmp_dst.rename(dst)  # Linux: 原子重命名
    except OSError:
        # 回滚：恢复原始
        if renamed_to_old and old_dst.exists() and not dst.exists():
            old_dst.rename(dst)
        raise
```

### 进度事件格式 (create.py:31-37)

```python
{"type": "start",     "total_agents": N, "percent": 0}
{"type": "agent",     "agent_id": str, "index": int, "total": int, "percent": int}
{"type": "saving",    "percent": 90}
{"type": "done",      "meta": dict, "percent": 100}
{"type": "error",     "message": str}
```

### 存储操作 (storage.py)

| 操作 | 函数 | 说明 |
|------|------|------|
| 列表 | `_list_sync()` | 读取 BACKUP_DIR 中每个 .zip 的 meta.json |
| 详情 | `_detail_sync()` | 额外计算每个工作区的文件数和大小 |
| 删除 | `_delete_sync()` | 直接 `zp.unlink()` |
| 导出 | `_export_sync()` | 返回路径和名称 |
| 导入 | `_import_sync()` | 验证 zip 结构，检查 ID 冲突 |

---

## 6. 部署模式

### 模式概览

| 模式 | 命令 | 适用场景 |
|------|------|----------|
| API 服务器 | `qwenpaw app` | 生产环境、远程访问 |
| 桌面 Webview | `qwenpaw desktop` | 本地开发、单用户 |
| 守护进程 | `qwenpaw daemon` | 后台运行、服务管理 |

### 4.1 API 服务器模式

#### 启动命令

```bash
qwenpaw app --host 127.0.0.1 --port 8088
```

#### 架构

```
┌─────────────────────────────────────┐
│           FastAPI Server            │
│              (Uvicorn)              │
├─────────────────────────────────────┤
│ Middleware:                         │
│   - AgentContextMiddleware          │
│   - AuthMiddleware                  │
│   - CORSMiddleware (可选)           │
├─────────────────────────────────────┤
│ Lifespan Manager:                   │
│   - 启动阶段：初始化智能体、插件     │
│   - 关闭阶段：清理资源、保存状态     │
└─────────────────────────────────────┘
```

#### 两阶段启动

```
阶段1: 快速同步启动 (<100ms)
├── 加载轻量级组件
├── 初始化中间件
└── 服务器开始接受请求

阶段2: 后台初始化
├── 加载智能体
├── 初始化插件
├── 配置 LLM 提供商
└── 连接消息渠道
```

#### 启动参数

```python
# app_cmd.py

@click.command()
@click.option("--host", default="127.0.0.1", help="监听地址")
@click.option("--port", default=8088, help="监听端口")
@click.option("--workers", default=1, help="工作进程数（已废弃，始终为1）")
def app(host, port, workers):
    """启动 FastAPI 应用服务器"""
    uvicorn.run(
        "qwenpaw.app._app:app",
        host=host,
        port=port,
        workers=1,  # 强制单进程
    )
```

### 4.2 桌面 Webview 模式

**源码路径**: `src/qwenpaw/cli/desktop_cmd.py`

#### 启动命令

```bash
qwenpaw desktop
```

#### 特性

- 自动选择可用端口
- 打开原生 Webview 窗口
- 阻塞等待窗口关闭
- 窗口关闭后自动清理后端进程

#### 核心组件

**WebViewAPI** (`desktop_cmd.py:29-36`) - 暴露给 Webview 的 JavaScript API：

```python
class WebViewAPI:
    """API exposed to the webview for handling external links."""

    def open_external_link(self, url: str) -> None:
        """Open URL in system's default browser."""
        if not url.startswith(("http://", "https://")):
            return
        webview.open(url)
```

**端口选择** (`desktop_cmd.py:39-44`)：

```python
def _find_free_port(host: str = "127.0.0.1") -> int:
    """Bind to port 0 and return the OS-assigned free port."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((host, 0))
        sock.listen(1)
        return sock.getsockname()[1]
```

**HTTP 就绪检测** (`desktop_cmd.py:47-58`)：

```python
def _wait_for_http(host: str, port: int, timeout_sec: float = 300.0) -> bool:
    """Return True when something accepts TCP on host:port."""
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(2.0)
                s.connect((host, port))
                return True
        except (OSError, socket.error):
            time.sleep(1)
    return False
```

**Windows 子进程输出处理** (`desktop_cmd.py:61-79`)：

```python
def _stream_reader(in_stream, out_stream) -> None:
    """Read from in_stream line by line and write to out_stream.

    Used on Windows to prevent subprocess buffer blocking. Runs in a
    background thread to continuously drain the subprocess output.
    """
```

#### 完整启动流程 (`desktop_cmd.py:99-269`)

```
1. setup_logger(log_level)  配置日志
           │
2. _find_free_port(host)  获取空闲端口
           │
3. subprocess.Popen 启动 qwenpaw app 后端进程
           │
           ├─► Windows: 启动 stdout/stderr 排水线程
           │
4. _wait_for_http()  等待 HTTP 服务就绪 (最多300秒)
           │
           ├─► 超时: 输出错误信息，等待进程退出
           │
5. webview.create_window()  创建桌面窗口
           │     title: "QwenPaw Desktop"
           │     url: http://127.0.0.1:{port}
           │     width: 1280, height: 800
           │     text_select: True
           │     js_api: WebViewAPI (open_external_link)
           │
6. webview.start()  阻塞直到用户关闭窗口
           │
7. proc.terminate()  窗口关闭后清理后端进程
           │
           ├─► 5秒超时后 force kill
           │
8. 检查 exit code，非正常退出则报错
```

#### 窗口关闭清理 (`desktop_cmd.py:207-236`)

```python
if proc and proc.poll() is None:  # 进程仍在运行
    proc.terminate()
    try:
        proc.wait(timeout=5.0)  # 等待5秒
    except subprocess.TimeoutExpired:
        proc.kill()  # 超时则强制终止
        proc.wait()
```

#### 命令行参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--host` | `127.0.0.1` | 服务绑定地址 |
| `--log-level` | `info` | 日志级别 (critical/error/warning/info/debug/trace) |

#### 双进程架构

Desktop 模式采用双进程架构：

```
┌─────────────────────────────────────────────────────┐
│ 主进程 (qwenpaw desktop)                            │
│  - 创建子进程启动 qwenpaw app 后端                 │
│  - 使用 pywebview 创建原生窗口                     │
│  - 等待窗口关闭后清理子进程                       │
└─────────────────────────────────────────────────────┘
                      │
                      │ subprocess.Popen
                      ▼
┌─────────────────────────────────────────────────────┐
│ 子进程 (qwenpaw app)                               │
│  - Uvicorn 运行 FastAPI 应用                       │
│  - 端口由 OS 通过绑定端口 0 分配                  │
│  - 提供 Web API 和静态文件服务                     │
└─────────────────────────────────────────────────────┘
```

#### 进程清理竞态处理 (`desktop_cmd.py:207-240`)

```python
# 处理 poll() 和 terminate() 之间的竞态条件
if proc and proc.poll() is None:
    proc.terminate()
    try:
        proc.wait(timeout=5.0)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
except ProcessLookupError:
    pass  # 进程已在 terminate 前退出
except OSError:
    pass  # 资源已被清理
```

**端口自动选择** (`desktop_cmd.py:39-44`):

```python
def _find_free_port(host: str = "127.0.0.1") -> int:
    """通过绑定端口 0 请求 OS 自动分配空闲端口"""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((host, 0))
        sock.listen(1)
        return sock.getsockname()[1]
```

**后端就绪检测** (`desktop_cmd.py:47-58`):

```python
def _wait_for_http(host: str, port: int, timeout_sec: float = 300.0) -> bool:
    """轮询直到后端服务就绪（默认5分钟超时）"""
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(2.0)
                s.connect((host, port))
                return True
        except OSError:
            time.sleep(1)
    return False
```

**Windows 子进程管道处理** (`desktop_cmd.py:61-79`):

```python
def _stream_reader(in_stream, out_stream) -> None:
    """后台线程持续排空子进程输出管道（Windows 专用）"""
    # 防止 Windows 上子进程管道缓冲区填满导致死锁
    try:
        for line in iter(in_stream.readline, ""):
            if not line:
                break
            out_stream.write(line)
            out_stream.flush()
    except Exception:
        pass
    finally:
        in_stream.close()
```

**完整启动流程**:

```
1. _find_free_port() ──► OS 自动分配端口
2. subprocess.Popen(["qwenpaw app", ...])
   ├── Windows: stdout/stderr=PIPE + 启动 _stream_reader 线程
   └── Unix: stdout/stderr=sys.stdout
3. _wait_for_http(host, port, 300s) ──► 轮询后端就绪
4. webview.create_window() ──► 创建原生窗口
   └── title: "QwenPaw Desktop", size: 1280x800
5. webview.start() ──► 阻塞直到用户关闭窗口
6. finally: proc.terminate() ──► 5秒等待 ──► proc.kill()
```

### 4.3 守护进程模式

#### 守护进程命令

```bash
# 查看状态
qwenpaw daemon status

# 重启守护进程
qwenpaw daemon restart

# 重载配置
qwenpaw daemon reload-config

# 查看版本
qwenpaw daemon version

# 查看日志
qwenpaw daemon logs
```

#### 守护进程架构

```
┌──────────────────────────────────────┐
│         QwenPaw Daemon               │
├──────────────────────────────────────┤
│ PID 文件: ~/.qwenpaw/daemon.pid      │
│ 日志文件: ~/.qwenpaw/logs/daemon.log │
├──────────────────────────────────────┤
│ 管理接口:                             │
│   - status: 运行状态                 │
│   - restart: 重启服务                 │
│   - reload: 重载配置                 │
│   - version: 版本信息                │
│   - logs: 日志查看                   │
└──────────────────────────────────────┘
```

### 4.4 生产部署建议

#### 环境变量配置

```bash
# 必需配置
export QWENPAW_WORKING_DIR=~/.qwenpaw
export QWENPAW_LOG_LEVEL=INFO

# 安全配置
export QWENPAW_TOOL_GUARD_ENABLED=true
export QWENPAW_JWT_SECRET=your-secret-key

# 性能配置
export QWENPAW_MAX_ITERS=100
export QWENPAW_CONCURRENCY=5
```

#### 反向代理配置 (Nginx)

```nginx
server {
    listen 443 ssl;
    server_name qwenpaw.example.com;

    location / {
        proxy_pass http://127.0.0.1:8088;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

#### Docker 部署

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY . /app
RUN pip install qwenpaw

EXPOSE 8088
CMD ["qwenpaw", "app", "--host", "0.0.0.0", "--port", "8088"]
```

---

## 如果你来自 Java...

### CLI 框架对比

| Python Click | Java Picocli | 说明 |
|-------------|--------------|------|
| `@click.command()` | `@Command` | 命令定义装饰器 |
| `@click.option()` | `@Option` | 选项参数 |
| `@click.argument()` | `@Arguments` | 位置参数 |
| `click.Group` | `Runnable` / `@Command` | 命令组 |
| `LazyGroup` | 手动 `addSubcommand()` 延迟加载 | 懒加载子命令 |

### 代码对比

**Python Click 定义命令：**
```python
@click.command()
@click.option("--host", default="127.0.0.1", help="Bind host")
@click.option("--port", default=8088, type=int, help="Bind port")
@click.option("--reload", is_flag=True, help="Enable auto-reload")
def app_cmd(host, port, reload):
    """Run QwenPaw FastAPI app."""
    uvicorn.run("qwenpaw.app._app:app", host=host, port=port, reload=reload)
```

**Java Picocli 定义命令：**
```java
@Command(name = "app", description = "Run QwenPaw FastAPI app")
public class AppCommand implements Runnable {
    @Option(names = {"-h", "--host"}, defaultValue = "127.0.0.1")
    private String host;

    @Option(names = {"-p", "--port"}, defaultValue = "8088")
    private int port;

    @Option(names = {"-r", "--reload"})
    private boolean reload;

    @Override
    public void run() {
        // 启动应用
    }
}
```

**Click LazyGroup vs Picocli 子命令加载：**

Click LazyGroup 在需要时才导入子命令模块：
```python
class LazyGroup(click.Group):
    def get_command(self, ctx, cmd_name):
        if cmd_name in self.lazy_subcommands:
            module = __import__(module_path, fromlist=[attr_name])
            cmd = getattr(module, attr_name)
            self.add_command(cmd, cmd_name)  # 缓存已加载命令
            return cmd
        return None
```

Picocli 可通过 `CommandSpec` 动态添加子命令：
```java
@Command(name = "main")
public class MainCommand implements Runnable {
    @Spec
    private Model.CommandSpec spec;

    public void run() {
        spec.addSubcommand("app", new AppCommand());
        spec.addSubcommand("agent", new AgentCommand());
    }
}
```

### 插件系统对比

| QwenPaw 插件 | Java SPI 机制 | 说明 |
|--------------|--------------|------|
| `plugin.json` | `META-INF/services` | 插件元数据 |
| `PluginApi` | `ServiceLoader.load(Interface)` | 插件接口 |
| `register_startup_hook()` | `@PostConstruct` | 初始化回调 |
| `register_shutdown_hook()` | `@PreDestroy` | 销毁回调 |

**QwenPaw 插件结构：**
```python
# plugin.json
{"id": "my_plugin", "entry": {"backend": "plugin.py"}}

# plugin.py
class MyPlugin:
    async def register(self, api: PluginApi):
        api.register_startup_hook(callback=self.on_startup)
```

**Java SPI 插件结构：**
```
META-INF/services/com.example.Plugin
  └── com.example.impl.MyPlugin

public class MyPlugin implements Plugin {
    @Override
    public void init() { /* 初始化 */ }
}

ServiceLoader<Plugin> loader = ServiceLoader.load(Plugin.class);
for (Plugin plugin : loader) {
    plugin.init();
}
```

### 配置系统对比

| QwenPaw | Java Spring | 说明 |
|---------|-------------|------|
| `config.json` | `application.yml` / `application.properties` | 主配置文件 |
| `constant.py` 常量 | `@ConfigurationProperties` | 配置绑定 |
| 环境变量覆盖 | `export SPRING_CONFIG_IMPORT` | 环境变量 |
| Secret Store | Spring Vault / CredHub | 敏感信息存储 |

---

## 7. 最佳实践

### CLI 使用

1. **使用诊断工具排查问题**
   ```bash
   qwenpaw doctor --fix  # 自动修复常见问题
   ```

2. **通过环境变量临时覆盖配置**
   ```bash
   QWENPAW_LOG_LEVEL=DEBUG qwenpaw app
   ```

### 配置管理

1. **使用 Secret Store 保护敏感信息**
   - API 密钥自动加密存储
   - 敏感配置不应明文写入 config.json

2. **多环境配置**
   ```bash
   QWENPAW_CONFIG=/path/to/prod.json qwenpaw app
   ```

### 安全加固

1. **启用 Tool Guard**
   ```json
   {
     "security": {
       "tool_guard": {
         "enabled": true,
         "scope": ["bash", "read", "write", "edit"]
       }
     }
   }
   ```

2. **定期运行技能扫描**
   ```python
   from qwenpaw.security.skill_scanner import scan_skill_directory
   result = scan_skill_directory("/path/to/skill")
   ```

3. **限制敏感工具访问**
   ```json
   {
     "security": {
       "tool_guard": {
         "denied_tools": ["debug_py", "delete_all"]
       }
     }
   }
   ```

---

## 练习题

### 基础练习

1. **CLI 基础**：运行 `qwenpaw --help` 和 `qwenpaw app --help`，观察输出
2. **配置查看**：运行 `qwenpaw doctor` 查看系统诊断
3. **日志观察**：启动应用后查看日志文件内容

### 进阶练习

4. **自定义命令**：参考现有 CLI 命令，创建一个简单的 `qwenpaw hello` 命令
5. **配置加密**：使用 `encrypt_dict_fields()` 加密敏感配置
6. **安全扫描**：对自定义技能运行 `qwenpaw skills scan` 观察结果

### 高级练习

7. **LazyGroup 分析**：阅读 `LazyGroup` 源码，绘制懒加载流程图
8. **ToolGuard 扩展**：实现一个自定义的 ToolGuardian，限制特定文件访问
9. **插件系统**：创建一个完整的 QwenPaw 插件，包含 `plugin.json` 和后端入口

### 参考答案

<details>
<summary>点击展开答案</summary>

**练习 1 & 2：**
```bash
qwenpaw --help
qwenpaw app --help
qwenpaw doctor
```

**练习 3：**
```bash
tail -f ~/.qwenpaw/qwenpaw.log
```

**练习 4：**
在 `cli/` 下创建 `hello_cmd.py`：
```python
import click

@click.command("hello")
@click.argument("name", default="World")
def hello_cmd(name):
    click.echo(f"Hello, {name}!")
```
然后在 `main.py` 的 `lazy_subcommands` 中注册。

**练习 5：**
```python
from qwenpaw.security.secret_store import encrypt_dict_fields
encrypted = encrypt_dict_fields({"api_key": "secret"}, ["api_key"])
```

**练习 6：**
```bash
qwenpaw skills scan ./my_skill
```

**练习 7：**
懒加载流程：
```
get_command("skills")
  → LazyGroup.get_command()
  → __import__("qwenpaw.cli.skills_cmd")
  → add_command() 缓存
  → 返回命令
```

**练习 8：**
```python
class BlockPathGuardian(BaseToolGuardian):
    async def check(self, tool_call) -> bool:
        return "/etc/passwd" not in str(tool_call.args)
```

**练习 9：**
```
my-plugin/
├── plugin.json        # 元数据
├── backend/
│   ├── __init__.py
│   └── main.py        # 入口点
└── requirements.txt
```

</details>

---

## 知识检查

1. **概念题**：LazyGroup 的延迟加载机制有什么好处？如果所有命令都在启动时一次性加载，会有什么问题？

2. **判断题**：SecretStore 在容器和 CI 环境中仍然会尝试使用 OS Keychain 存储主密钥。这个说法对吗？为什么？

3. **场景题**：假设你需要在生产环境中部署 QwenPaw，如何确保 API 密钥等敏感配置不会被明文存储？请描述你会使用的安全机制和配置步骤。

---

## 延伸阅读

| 方向 | 章节 | 说明 |
|------|------|------|
| 安全系统详解 | [19-安全系统详解](./19-安全系统详解.md) | 安全架构设计、威胁模型与防护策略 |
| CLI 命令详解 | [69-CLI命令系统详解](./69-CLI命令系统详解.md) | 全面掌握所有 CLI 命令的用法与扩展方式 |
| 配置系统详解 | [20-配置系统详解](./20-配置系统详解.md) | 配置加载、验证、迁移和热重载机制 |
| 下一章 | [11-Model系统与LLM提供商](./11-Model系统与LLM提供商.md) | 继续学习 |
