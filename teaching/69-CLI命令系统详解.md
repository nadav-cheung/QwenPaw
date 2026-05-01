# CLI 命令系统详解

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 分析 CLI 命令的注册和分发 2) 理解懒加载命令的优化 3) 扩展自定义 CLI 命令 |
| **前置知识** | [10-CLI配置与安全](./10-CLI配置与安全.md)、[03-项目架构](./03-项目架构.md) |
| **预计时长** | 35 分钟（阅读 25 分钟 + 练习 10 分钟） |
| **难度等级** | ⭐⭐⭐ |
| **核心关键词** | `CLI` `命令注册` `懒加载` |

> **一句话概述**：本章详解 QwenPaw CLI 基于 Click 框架的命令系统，重点分析 LazyGroup 按需加载机制、初始化计时和自定义命令扩展方法。

## 概述

QwenPaw CLI 基于 Click 框架，使用 LazyGroup 实现命令按需加载，支持多子命令分组和异步初始化计时。

---

## 1. CLI 入口

源码路径：`src/qwenpaw/cli/main.py`

### 1.1 模块结构

```
cli/main.py
├── 导入区 (1-25)
│   ├── ensure_standard_streams() - Windows UTF-8 支持
│   └── 计时记录 (_init_timings)
├── LazyGroup 类 (53-78)
│   ├── list_commands() - 列出所有命令
│   └── get_command() - 惰性加载命令
├── cli Group 定义 (80-135)
│   ├── 惰性子命令映射 (86-135)
│   └── cli() 主命令 (137-160)
└── log_init_timings() (44-49)
```

### 1.2 Windows UTF-8 支持

```python
# src/qwenpaw/cli/main.py:15
# On Windows, force UTF-8 for stdout/stderr so cron and other commands
# can handle Chinese and other non-ASCII (Linux is UTF-8 by default).
if sys.platform == "win32":
    ensure_standard_streams()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass
```

### 1.3 初始化计时

```python
# src/qwenpaw/cli/main.py:26-44
_init_timings: list[tuple[str, float]] = []
_t0_main = time.perf_counter()
_init_timings.append(("main.py loaded", 0.0))

def _record(label: str, elapsed: float) -> None:
    _init_timings.append((label, elapsed))
    logger.debug("%.3fs %s", elapsed, label)

# 模块导入时记录
_t = time.perf_counter()
from ..config.utils import read_last_api
_record("..config.utils", time.perf_counter() - _t)

def log_init_timings() -> None:
    """Emit init timing debug lines after setup_logger(debug) in app_cmd."""
    for label, elapsed in _init_timings:
        logger.debug("%.3fs %s", elapsed, label)
```

### 1.4 Click Group 定义

```python
# src/qwenpaw/cli/main.py:80-135
@click.group(
    cls=LazyGroup,
    context_settings={"help_option_names": ["-h", "--help"]},
    lazy_subcommands={
        "app": ("qwenpaw.cli.app_cmd", "app_cmd", ".app_cmd"),
        "init": ("qwenpaw.cli.init_cmd", "init_cmd", ".init_cmd"),
        "doctor": ("qwenpaw.cli.doctor_cmd", "doctor_cmd", ".doctor_cmd"),
        "models": ("qwenpaw.cli.providers_cmd", "models_group", ".providers_cmd"),
        ...
    },
)
@click.version_option(version=__version__, prog_name="QwenPaw")
@click.option("--host", default=None, help="API Host")
@click.option("--port", default=None, type=int, help="API Port")
@click.pass_context
def cli(ctx: click.Context, host: str | None, port: int | None) -> None:
    """QwenPaw CLI."""
    # default from last run if not provided
    last = read_last_api()
    if host is None or port is None:
        if last:
            host = host or last[0]
            port = port or last[1]

    # final fallback
    host = host or "127.0.0.1"
    port = port or 8088

    ctx.ensure_object(dict)
    ctx.obj["host"] = host
    ctx.obj["port"] = port
```

---

## 2. LazyGroup 按需加载

源码路径：`src/qwenpaw/cli/main.py:53`

### 2.1 类定义

```python
# src/qwenpaw/cli/main.py:53
class LazyGroup(click.Group):
    """支持命令惰性加载的 Group"""

    def list_commands(self, ctx):
        """返回所有命令名（包含惰性加载的命令）"""
        base = super().list_commands(ctx)
        return sorted(set(base) | set(self.lazy_subcommands.keys()))

    def get_command(self, ctx, cmd_name):
        """获取命令，必要时惰性加载"""
        cmd = super().get_command(ctx, cmd_name)
        if cmd is not None:
            return cmd

        # 惰性加载
        if cmd_name in self.lazy_subcommands:
            module_path, attr_name, label = self.lazy_subcommands[cmd_name]
            module = __import__(module_path, fromlist=[attr_name])
            cmd = getattr(module, attr_name)
            self.add_command(cmd, cmd_name)
            return cmd
```

### 2.2 加载流程

```
用户执行 qwenpaw app
    ↓
cli.get_command("app")
    ↓
LazyGroup.get_command("app")
    ↓
检查命令是否已加载
    ├── 已加载 → 直接返回
    └── 未加载 → __import__("qwenpaw.cli.app_cmd")
                    ↓
                getattr(module, "app_cmd")
                    ↓
                self.add_command(cmd, "app")
                    ↓
                返回 app_cmd
```

**LazyGroup 优势**：
1. `qwenpaw --help` 快速响应（不需要导入所有子命令模块）
2. 内存节省（只加载使用的命令模块）
3. 启动加速（延迟导入直到真正需要）

---

## 3. 子命令列表

### 3.1 惰性加载映射

```python
lazy_subcommands = {
    "app":      ("qwenpaw.cli.app_cmd", "app_cmd", ".app_cmd"),
    "acp":      ("qwenpaw.cli.acp_cmd", "acp_cmd", ".acp_cmd"),
    "channels": ("qwenpaw.cli.channels_cmd", "channels_group", ".channels_cmd"),
    "daemon":   ("qwenpaw.cli.daemon_cmd", "daemon_group", ".daemon_cmd"),
    "chats":    ("qwenpaw.cli.chats_cmd", "chats_group", ".chats_cmd"),
    "clean":    ("qwenpaw.cli.clean_cmd", "clean_cmd", ".clean_cmd"),
    "cron":     ("qwenpaw.cli.cron_cmd", "cron_group", ".cron_cmd"),
    "env":      ("qwenpaw.cli.env_cmd", "env_group", ".env_cmd"),
    "init":     ("qwenpaw.cli.init_cmd", "init_cmd", ".init_cmd"),
    "models":   ("qwenpaw.cli.providers_cmd", "models_group", ".providers_cmd"),
    "skills":   ("qwenpaw.cli.skills_cmd", "skills_group", ".skills_cmd"),
    "uninstall":("qwenpaw.cli.uninstall_cmd", "uninstall_cmd", ".uninstall_cmd"),
    "desktop":  ("qwenpaw.cli.desktop_cmd", "desktop_cmd", ".desktop_cmd"),
    "update":   ("qwenpaw.cli.update_cmd", "update_cmd", ".update_cmd"),
    "shutdown": ("qwenpaw.cli.shutdown_cmd", "shutdown_cmd", ".shutdown_cmd"),
    "auth":     ("qwenpaw.cli.auth_cmd", "auth_group", ".auth_cmd"),
    "agents":   ("qwenpaw.cli.agents_cmd", "agents_group", ".agents_cmd"),
    "plugin":   ("qwenpaw.cli.plugin_commands", "plugin", ".plugin_commands"),
    "task":     ("qwenpaw.cli.task_cmd", "task_cmd", ".task_cmd"),
    "mission":  ("qwenpaw.cli.mission_cmd", "mission_group", ".mission_cmd"),
    "doctor":   ("qwenpaw.cli.doctor_cmd", "doctor_cmd", ".doctor_cmd"),
}
```

### 3.2 子命令分类

| 类别 | 命令 |
|------|------|
| 核心 | `app`, `init`, `shutdown` |
| 调试/维护 | `doctor`, `clean`, `update` |
| 多 Agent | `agents`, `channels`, `chats` |
| 开发者 | `models`, `skills`, `plugin` |
| 后台任务 | `daemon`, `cron`, `task`, `mission` |
| 桌面/认证 | `desktop`, `auth` |

---

## 4. 初始化计时

源码路径：`src/qwenpaw/cli/main.py:30`

### 4.1 计时机制

```python
# src/qwenpaw/cli/main.py:30
_init_timings: list[tuple[str, float]] = []
_t0_main = time.perf_counter()

def _record(label: str, elapsed: float) -> None:
    _init_timings.append((label, elapsed))

# 模块导入时记录
_t = time.perf_counter()
from ..config.utils import read_last_api
_record("..config.utils", time.perf_counter() - _t)
```

### 4.2 计时日志

```python
# src/qwenpaw/cli/main.py:44
def log_init_timings() -> None:
    """在 app_cmd 中设置 debug 日志级别后发出初始化计时"""
    for label, elapsed in _init_timings:
        logger.debug("%.3fs %s", elapsed, label)
```

**使用方式**：

```bash
qwenpaw --log-level DEBUG app
# 输出示例:
# DEBUG: 0.012s ..config.utils
# DEBUG: 0.045s ..server.settings
# DEBUG: 0.103s ..agents.utils
```

---

## 5. Windows UTF-8 支持

源码路径：`src/qwenpaw/cli/main.py:15`

```python
# src/qwenpaw/cli/main.py:15
if sys.platform == "win32":
    ensure_standard_streams()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass
```

**问题**：Windows 默认控制台编码不是 UTF-8，中文输出会乱码。

---

## 6. 主要命令详解

### 6.1 qwenpaw app

源码路径：`src/qwenpaw/cli/app_cmd.py:15`

```python
# src/qwenpaw/cli/app_cmd.py:15
@click.command("app")
@click.option("--host", default="127.0.0.1", show_default=True, help="Bind host")
@click.option("--port", default=8088, type=int, show_default=True, help="Bind port")
@click.option("--reload", is_flag=True, help="Enable auto-reload (dev only)")
@click.option(
    "--log-level",
    default="info",
    type=click.Choice(["critical", "error", "warning", "info", "debug", "trace"]),
    show_default=True,
    help="Log level",
)
@click.option(
    "--hide-access-paths",
    multiple=True,
    default=("/console/push-messages",),
    show_default=True,
    help="Path substrings to hide from uvicorn access log (repeatable).",
)
@click.option(
    "--workers",
    type=int,
    default=None,
    help="[DEPRECATED] Number of worker processes. "
    "This option is deprecated and will be removed in a future version.",
)
def app_cmd(host, port, reload, workers, log_level, hide_access_paths) -> None:
    """Run QwenPaw FastAPI app."""
    # 处理已弃用的 --workers 参数
    if workers is not None:
        click.echo("WARNING: --workers option is deprecated...", err=True)

    # 持久化最后使用的 host/port
    if host == "0.0.0.0":
        write_last_api("127.0.0.1", port)
    else:
        write_last_api(host, port)
    os.environ[LOG_LEVEL_ENV] = log_level

    # 热重载模式下启用 Windows 兼容
    if reload:
        os.environ["QWENPAW_RELOAD_MODE"] = "1"

    setup_logger(log_level)

    # 隐藏指定路径的访问日志
    paths = [p for p in hide_access_paths if p]
    if paths:
        logging.getLogger("uvicorn.access").addFilter(
            SuppressPathAccessLogFilter(paths),
        )

    uvicorn.run(
        "qwenpaw.app._app:app",
        host=host,
        port=port,
        reload=reload,
        workers=1,  # 始终使用 1 worker
        log_level=log_level,
    )
```

**命令参数**：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--host` | `127.0.0.1` | 绑定主机地址 |
| `--port` | `8088` | 绑定端口 |
| `--reload` | `False` | 启用热重载（仅开发用） |
| `--log-level` | `info` | 日志级别 |
| `--hide-access-paths` | `/console/push-messages` | 从 uvicorn 访问日志中隐藏的路径 |
| `--workers` | `None` | **已弃用**，始终使用 1 worker |

**设计要点**：
- `--workers` 参数已弃用，始终使用 1 worker 保证稳定性
- `0.0.0.0` 绑定时，写入 `127.0.0.1` 到 last_api 以便其他终端连接
- 热重载模式下设置 `QWENPAW_RELOAD_MODE` 环境变量，Windows 兼容
- 使用 `SuppressPathAccessLogFilter` 过滤敏感路径的访问日志

### 6.2 qwenpaw init

```bash
# 初始化工作目录和配置
qwenpaw init
qwenpaw init --dir /path/to/dir

# 不带 --dir 时，在当前目录创建 ~/.qwenpaw 结构
```

### 6.3 qwenpaw doctor

```bash
# 诊断检查
qwenpaw doctor

# 修复操作（自动修复可诊断的问题）
qwenpaw doctor fix

# 深度检查（包含网络、依赖检查）
qwenpaw doctor --deep
```

**doctor 检查项**：

| 检查项 | 说明 |
|--------|------|
| 配置文件 | 检查 config.json 格式和必填字段 |
| 工作区 | 检查工作区目录结构 |
| 渠道配置 | 检查各渠道配置是否有效 |
| 依赖 | 检查 Python 依赖是否完整 |
| 网络 | 检查外部服务连通性（--deep） |

### 6.4 qwenpaw models

```bash
# 模型管理
qwenpaw models list           # 列出可用模型
qwenpaw models add <name>     # 添加模型配置
qwenpaw models remove <name>  # 移除模型配置
qwenpaw models pull <name>    # 拉取本地模型（如 Ollama）
```

### 6.5 qwenpaw agents

```bash
# Agent 管理
qwenpaw agents list           # 列出所有 Agent
qwenpaw agents create <id>   # 创建新 Agent
qwenpaw agents delete <id>   # 删除 Agent
qwenpaw agents start <id>    # 启动 Agent
qwenpaw agents stop <id>      # 停止 Agent
```

### 6.6 qwenpaw channels

```bash
# 渠道管理
qwenpaw channels list         # 列出所有渠道
qwenpaw channels enable <name>   # 启用渠道
qwenpaw channels disable <name>  # 禁用渠道
qwenpaw channels status <name>   # 渠道状态
```

### 6.7 qwenpaw shutdown

```bash
# 优雅关闭
qwenpaw shutdown

# 强制关闭（不等候任务完成）
qwenpaw shutdown --force
```

---

## 7. 自定义 CLI 命令

### 7.1 命令模块结构

```python
# qwenpaw/cli/my_cmd.py
import click
from ..cli.main import cli

@click.command("my-cmd")
@click.option("--name", default="world", help="Name to greet")
def my_cmd(name):
    """My custom command."""
    click.echo(f"Hello, {name}!")

# 注册到 LazyGroup
cli.lazy_subcommands["my-cmd"] = ("qwenpaw.cli.my_cmd", "my_cmd", ".my_cmd")
```

### 7.2 子命令组

```python
# qwenpaw/cli/my_group.py
import click

@click.group("my-group")
def my_group():
    """My command group."""
    pass

@my_group.command("sub1")
def sub1():
    """Sub command 1."""
    pass

@my_group.command("sub2")
def sub2():
    """Sub command 2."""
    pass

# 使用
# qwenpaw my-group sub1
# qwenpaw my-group sub2
```

---

## 8. 应用场景

### 场景一：自动化部署

```bash
#!/bin/bash
# deploy.sh

# 初始化环境
qwenpaw init --dir /opt/qwenpaw

# 配置渠道
qwenpaw channels enable telegram
qwenpaw channels enable discord

# 启动服务
qwenpaw app --host 0.0.0.0 --port 8000 &

echo "QwenPaw deployed!"
```

### 场景二：多环境配置

```bash
# 开发环境
qwenpaw init --dir ./dev-workspace
qwenpaw app --debug

# 生产环境
qwenpaw init --dir /opt/qwenpaw
qwenpaw app
```

### 场景三：故障排查

```bash
# 诊断问题
qwenpaw doctor --deep

# 查看日志
qwenpaw logs --follow

# 检查特定组件
qwenpaw doctor fix
```

---

## 9. 最佳实践

### 9.1 日志级别

```bash
# 调试模式查看初始化计时
qwenpaw --log-level DEBUG app

# 生产模式减少日志
qwenpaw --log-level WARNING app
```

### 9.2 异步命令执行

```bash
# 长时间运行的命令应后台执行
qwenpaw app &
APP_PID=$!

# 等待服务启动
sleep 5

# 检查状态
curl http://localhost:8000/api/version

# 关闭
qwenpaw shutdown
```

### 9.3 命令别名

```bash
# ~/.bashrc 或 ~/.zshrc
alias qp="qwenpaw"
alias qpa="qwenpaw app"
alias qpd="qwenpaw doctor"

# 使用
qpa --debug
qpd fix
```

---

## 10. 常见问题

### Q1: `qwenpaw: command not found`

**原因**：安装问题或 PATH 未配置。

**解决**：
```bash
# 检查安装
pip show qwenpaw

# 重新安装
pip install -e .

# 检查 PATH
which qwenpaw
```

### Q2: 中文输出乱码

**原因**：Windows 控制台编码问题。

**解决**：
```bash
# 设置控制台编码
chcp 65001

# 或使用 Python 启动
python -m qwenpaw app
```

### Q3: 子命令加载慢

**原因**：首次加载需要导入模块。

**解决**：
```bash
# 预热：查看帮助
qwenpaw --help

# 第二次执行会使用缓存的模块
qwenpaw app
```

### Q4: doctor fix 无法修复的问题

**原因**：问题超出自动修复范围。

**解决**：
```bash
# 查看详细错误
qwenpaw doctor --deep

# 手动修复
# 1. 检查配置文件语法
# 2. 检查工作区权限
# 3. 查看日志
```

---

## 知识检查

1. LazyGroup 的 `get_command` 方法在命令未加载时执行了哪些操作？为什么这种按需加载能显著提升 `qwenpaw --help` 的响应速度？
2. `_init_timings` 计时机制记录的是什么阶段的耗时？这些数据在什么场景下最有诊断价值？
3. 如果要新增一个 `qwenpaw my-cmd` 子命令，需要修改哪些文件？注册到 `lazy_subcommands` 的三元组分别代表什么？

---

## 11. 总结

### 核心要点

1. **LazyGroup 按需加载**：`qwenpaw --help` 快速响应，只导入使用的命令模块
2. **初始化计时**：记录各模块导入时间，便于性能分析
3. **Windows UTF-8 支持**：自动配置控制台编码，避免中文乱码
4. **22+ 子命令**：覆盖启动、配置、调试、Agent 管理等全场景
5. **统一参数风格**：`--help`、`--debug`、`--log-level`

### 关键文件索引

| 组件 | 文件路径 |
|------|----------|
| CLI 入口 | `src/qwenpaw/cli/main.py:80` |
| LazyGroup | `src/qwenpaw/cli/main.py:53` |
| 初始化计时 | `src/qwenpaw/cli/main.py:30` |
| App 命令 | `src/qwenpaw/cli/app_cmd.py` |
| Init 命令 | `src/qwenpaw/cli/init_cmd.py` |
| Doctor 命令 | `src/qwenpaw/cli/doctor_cmd.py` |
| Models 命令 | `src/qwenpaw/cli/providers_cmd.py` |

---

## 延伸阅读

- [10-CLI配置与安全](./10-CLI配置与安全.md) -- 了解 CLI 的安全配置和敏感信息管理
- [18-插件系统](./18-插件系统.md) -- 理解插件系统如何扩展 CLI 命令和功能
