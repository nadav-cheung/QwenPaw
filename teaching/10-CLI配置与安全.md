# CLI、配置与安全

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
├── desktop_cmd.py       # 桌面模式
├── doctor_cmd.py        # 诊断修复
├── init_cmd.py          # 初始化向导
├── providers_cmd.py     # LLM 提供商配置
├── skills_cmd.py        # 技能管理
└── ...
```

### 核心组件

#### LazyGroup 命令加载

```python
# main.py 核心结构
class LazyGroup(click.Group):
    """支持延迟加载子命令的 Click Group"""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.lazy_subcommands = {}

    def add_lazy_subcommand(self, name, module_path, attr_name, help_text):
        """注册延迟加载的命令"""
        self.lazy_subcommands[name] = (module_path, attr_name, help_text)

    def resolve_command(self, ctx, args):
        # 动态解析并加载子命令
        ...
```

### 常用命令

#### 应用管理

| 命令 | 说明 |
|------|------|
| `qwenpaw app` | 启动 FastAPI 服务器 |
| `qwenpaw desktop` | 启动桌面 Webview 模式 |
| `qwenpaw daemon status` | 查看守护进程状态 |
| `qwenpaw daemon restart` | 重启守护进程 |
| `qwenpaw shutdown` | 关闭运行中的实例 |

```bash
# 启动 API 服务器
qwenpaw app --host 127.0.0.1 --port 8088

# 启动桌面模式（自动打开 Webview 窗口）
qwenpaw desktop

# 检查守护进程状态
qwenpaw daemon status

# 重启守护进程
qwenpaw daemon restart
```

#### 智能体管理

| 命令 | 说明 |
|------|------|
| `qwenpaw agents list` | 列出所有智能体 |
| `qwenpaw agents create` | 创建新智能体 |
| `qwenpaw agents configure` | 配置智能体 |

```bash
# 列出所有智能体
qwenpaw agents list

# 创建新智能体
qwenpaw agents create --name my_agent --type assistant
```

#### 渠道管理

| 命令 | 说明 |
|------|------|
| `qwenpaw channels list` | 列出配置的渠道 |
| `qwenpaw channels configure` | 配置渠道 |
| `qwenpaw channels install` | 安装渠道依赖 |

```bash
# 列出所有渠道
qwenpaw channels list

# 配置新渠道
qwenpaw channels configure telegram

# 安装渠道依赖
qwenpaw channels install discord
```

#### 技能管理

```bash
# 列出所有技能
qwenpaw skills list

# 安装技能
qwenpaw skills install my_skill

# 启用/禁用技能
qwenpaw skills enable my_skill
qwenpaw skills disable my_skill

# 卸载技能
qwenpaw skills uninstall my_skill
```

#### 提供商配置

```bash
# 列出配置的 LLM 提供商
qwenpaw providers list

# 添加提供商
qwenpaw providers add openai --api-key xxx

# 配置提供商
qwenpaw providers configure anthropic
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
    console: Optional[ConsoleChannelConfig]
    matrix: Optional[MatrixChannelConfig]
    voice: Optional[VoiceChannelConfig]
    wecom: Optional[WeComChannelConfig]
    xiaoyi: Optional[XiaoYiChannelConfig]
    wechat: Optional[WeChatChannelConfig]
    onebot: Optional[OneBotChannelConfig]
```

#### 智能体配置

```python
class AgentsConfig(BaseModel):
    """多智能体配置"""

    profiles: Dict[str, AgentProfileConfig] = {}
    running: AgentsRunningConfig = AgentsRunningConfig()

class AgentProfileConfig(BaseModel):
    """单个智能体配置"""

    name: str
    model: str
    provider: str
    temperature: float = 0.7
    max_tokens: int = 4096
    system_prompt: Optional[str] = None
    skills: List[str] = []
    tools: List[str] = []

class AgentsRunningConfig(BaseModel):
    """运行时行为配置"""

    max_iters: int = 100
    retry: bool = True
    retry_limit: int = 3
    backoff: float = 1.0
    concurrency: int = 5
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

```python
# src/qwenpaw/config/utils.py

def load_config(config_path: str) -> Config:
    """加载并验证配置文件"""
    with open(config_path, 'r') as f:
        data = json.load(f)
    return Config(**data)

def save_config(config: Config, config_path: str) -> None:
    """保存配置到文件"""
    with open(config_path, 'w') as f:
        json.dump(config.model_dump(), f, indent=2)

def get_config_path() -> str:
    """获取配置路径"""
    return os.path.join(WORKING_DIR, "config.json")
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

### 3.1 敏感信息存储 (Secret Store)

#### 加密机制

使用 **Fernet** 对称加密（AES-128-CBC + HMAC-SHA256）保护敏感配置。

```python
# secret_store.py

class SecretStore:
    """敏感信息加密存储"""

    def encrypt(self, plaintext: str) -> str:
        """加密敏感数据"""
        encrypted = self.fernet.encrypt(plaintext.encode())
        return f"ENC:{base64.b64encode(encrypted).decode()}"

    def decrypt(self, value: str) -> str:
        """解密敏感数据（支持未加密值透明返回）"""
        if not self.is_encrypted(value):
            return value
        # 解密逻辑...
        return decrypted

    def is_encrypted(self, value: str) -> bool:
        """检查值是否已加密"""
        return value.startswith("ENC:")
```

#### 密钥管理

主密钥存储优先级：
1. **OS Keychain** - 通过 `keyring` 库访问系统密钥链
2. **本地文件** - `SECRET_DIR/.master_key`（权限 `0o600`）

```python
def _get_master_key():
    """获取主密钥（优先从 Keychain）"""
    # 1. 尝试从 Keychain 获取
    key = keyring.get_password("qwenpaw", "master_key")
    if key:
        return key

    # 2. 从本地文件获取
    key_file = os.path.join(SECRET_DIR, ".master_key")
    if os.path.exists(key_file):
        with open(key_file, 'r') as f:
            return f.read().strip()

    # 3. 生成新密钥
    key = secrets.token_hex(32)
    keyring.set_password("qwenpaw", "master_key", key)
    return key
```

#### 受保护字段

以下配置字段会自动加密：
- `api_key` - 提供商 API 密钥
- `jwt_secret` - 认证 JWT 密钥

### 3.2 工具调用守卫 (Tool Guard)

#### 架构

```
ToolGuardEngine
├── FilePathToolGuardian     # 文件路径保护
├── RuleBasedToolGuardian    # 规则匹配保护
└── ShellEvasionGuardian     # Shell 逃逸检测
```

#### 核心引擎

```python
class ToolGuardEngine:
    """工具调用安全扫描引擎"""

    def __init__(self, config: ToolGuardConfig):
        self.guardians = [
            FilePathToolGuardian(config.file_guard),
            RuleBasedToolGuardian(),
            ShellEvasionGuardian(),
        ]

    def guard(self, tool_name: str, params: Dict[str, Any]) -> ToolGuardResult:
        """扫描工具调用参数，返回扫描结果"""
        findings = []

        for guardian in self.guardians:
            result = guardian.check(tool_name, params)
            if result:
                findings.append(result)

        return ToolGuardResult(findings=findings)

    def is_denied(self, tool_name: str) -> bool:
        """检查工具是否被无条件拒绝"""
        return tool_name in self.config.denied_tools

    def is_guarded(self, tool_name: str) -> bool:
        """检查工具是否在保护范围内"""
        return tool_name in self.config.scope
```

#### 文件路径守卫

检测对敏感文件的访问尝试：

```python
class FilePathToolGuardian:
    """文件路径访问保护"""

    SENSITIVE_PATHS = [
        "~/.ssh/",
        "~/.aws/",
        "~/.config/gcloud",
        "/etc/passwd",
        "/etc/shadow",
        ".env",
        ".git/config",
    ]

    def check(self, tool_name: str, params: Dict) -> Optional[GuardFinding]:
        """检查文件路径是否敏感"""
        file_path = params.get("path") or params.get("file_path")
        if not file_path:
            return None

        # 展开 ~ 和环境变量
        expanded = os.path.expanduser(os.path.expandvars(file_path))

        for sensitive in self.SENSITIVE_PATHS:
            if expanded.startswith(sensitive):
                return GuardFinding(
                    severity="high",
                    message=f"访问敏感路径: {file_path}",
                    pattern=sensitive
                )
        return None
```

#### Shell 逃逸守卫

检测 Shell 命令注入和逃逸尝试：

```python
class ShellEvasionGuardian:
    """Shell 命令逃逸检测"""

    EVASION_PATTERNS = [
        r"'\s*;\s*'",        # 分号分隔
        r"`.*`",              # 命令替换
        r"\$\(.*\)",          # $(command) 替换
        r"\|\s*\w+",          # 管道注入
        r"&&\s*\w+",          # 条件注入
    ]

    def check(self, tool_name: str, params: Dict) -> Optional[GuardFinding]:
        """检测 Shell 逃逸模式"""
        if tool_name != "bash":
            return None

        command = params.get("command", "")
        for pattern in self.EVASION_PATTERNS:
            if re.search(pattern, command):
                return GuardFinding(
                    severity="high",
                    message=f"检测到 Shell 逃逸模式: {pattern}",
                    pattern=pattern
                )
        return None
```

#### 规则守卫

支持 YAML 自定义规则 (`security/tool_guard/rules/dangerous_shell_commands.yaml`)：

```yaml
# 危险 Shell 命令规则
- id: TOOL_CMD_DANGEROUS_RM
  tools: [execute_shell_command]
  params: [command]
  category: command_injection
  severity: HIGH
  patterns:
    - "\\brm\\b"
    - "\\bdel\\b"
  exclude_patterns:
    - "^\\s*#"
  description: "Shell command contains 'rm' which may cause data loss"

- id: TOOL_CMD_PIPE_TO_SHELL
  tools: [execute_shell_command]
  params: [command]
  category: code_execution
  severity: CRITICAL
  patterns:
    - "\\b(curl|wget)\\b\\s+.*\\|.*\\b(bash|sh|zsh)\\b"
  description: "Detects 'curl | bash' patterns"

- id: TOOL_CMD_REVERSE_SHELL
  tools: [execute_shell_command]
  params: [command]
  category: network_abuse
  severity: CRITICAL
  patterns:
    - "\\/dev\\/(tcp|udp)\\/"
    - "\\bnc\\s+.*-e\\s*\\S+"
  description: "Detects reverse shell attempts"
```

#### 威胁类别

| 类别 | 说明 |
|------|------|
| `command_injection` | 命令注入 |
| `code_execution` | 代码执行 |
| `network_abuse` | 网络滥用 |
| `sensitive_file_access` | 敏感文件访问 |
| `data_exfiltration` | 数据泄露 |
| `resource_abuse` | 资源滥用 |

#### 配置方式

```json
{
  "security": {
    "tool_guard": {
      "enabled": true,
      "scope": ["bash", "read", "write", "edit"],
      "denied_tools": ["debug_py"]
    }
  }
}
```

或通过环境变量：
```bash
export QWENPAW_TOOL_GUARD_ENABLED=false
```

### 3.3 技能安全扫描 (Skill Scanner)

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

## 4. 部署模式

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

#### 启动命令

```bash
qwenpaw desktop
```

#### 特性

- 自动选择可用端口
- 打开原生 Webview 窗口
- 阻塞等待窗口关闭
- 窗口关闭后自动清理后端进程

```python
# desktop_cmd.py

def desktop():
    """桌面 Webview 模式"""
    # 1. 启动 FastAPI 后端（选择空闲端口）
    port = find_free_port()
    backend = start_backend(port)

    # 2. 打开 Webview 窗口
    webview.create_window(
        'QwenPaw',
        f'http://localhost:{port}'
    )
    webview.start()

    # 3. 窗口关闭后清理
    backend.terminate()
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

## 5. 最佳实践

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
