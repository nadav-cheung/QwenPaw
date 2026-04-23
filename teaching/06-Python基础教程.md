# Python 基础教程（面向 Java 开发者）

## 概述

本教程为有 Java 背景的开发者快速掌握 Python 基础而编写。Python 和 Java 在很多概念上是相通的，但语法和编程风格有显著差异。通过类比 Java 语法，可以帮助 Java 开发者更快上手 Python。

## 1. Python 与 Java 的核心差异对比

| 特性 | Java | Python |
|------|------|--------|
| 类型系统 | 静态类型（编译时检查） | 动态类型（可选静态类型检查） |
| 语法 | 花括号 `{}` 界定代码块 | 缩进界定代码块 |
| 方法/函数定义 | `public void method()` | `def method():` |
| 变量声明 | `String name = "Java"` | `name = "Python"` |
| 循环 | `for (int i : list)` | `for item in list:` |
| 类定义 | `public class Foo {}` | `class Foo:` |
| 空值 | `null` | `None` |
| 布尔值 | `true` / `false` | `True` / `False` |
| 字符串拼接 | `"Hello " + name` | `f"Hello {name}"` |
| 接口实现 | `implements Interface` | 直接继承或多继承 |
| 访问控制 | `public`/`private`/`protected` | `_`/`__` 前缀约定 |

### 关键区别

**1. 缩进代替花括号**
```python
# Python - 缩进定义代码块
if x > 0:
    print("positive")
    if x > 10:
        print("large")
else:
    print("non-positive")
```

**2. 动态类型 + 类型提示**
```python
# Python 可以不声明类型，但可以用类型提示
name: str = "QwenPaw"  # 类型提示
age: int = 25
```

**3. Everything is an object**
```python
# Python 中函数也是对象
def greet():
    return "Hello"

say = greet  # 函数可以赋值给变量
print(say())  # 输出: Hello
```

---

## 2. Python 语法快速上手

### 2.1 变量与数据类型

```python
# 字符串
name = "QwenPaw"
version = '1.0'
multi_line = """多行
字符串"""

# 数字
integer = 42
floating = 3.14
hex_num = 0xFF  # 255

# 布尔值
is_active = True
is_empty = False

# None 表示空值（相当于 Java 的 null）
result = None

# 列表（相当于 Java 的 List）
numbers = [1, 2, 3, 4, 5]
mixed = [1, "hello", True]

# 字典（相当于 Java 的 Map）
config = {
    "host": "localhost",
    "port": 8080,
    "debug": True
}

# 集合（相当于 Java 的 Set）
tags = {"python", "java", "golang"}

# 元组（不可变列表）
point = (10, 20)
```

**Java 对比：**
```java
// Java
String name = "QwenPaw";
List<Integer> numbers = Arrays.asList(1, 2, 3);
Map<String, Object> config = new HashMap<>();
config.put("host", "localhost");
```

### 2.2 控制流

```python
# 条件语句
age = 18
if age >= 18:
    print("成年")
elif age >= 6:
    print("青少年")
else:
    print("儿童")

# 三元表达式
status = "成年" if age >= 18 else "未成年"
```

**Java 对比：**
```java
// Java
String status = age >= 18 ? "成年" : "未成年";
```

```python
# for 循环 - 遍历列表
fruits = ["apple", "banana", "orange"]
for fruit in fruits:
    print(fruit)

# for 循环 - 遍历范围
for i in range(5):       # 0, 1, 2, 3, 4
    print(i)

for i in range(1, 6):    # 1, 2, 3, 4, 5
    print(i)

for i in range(0, 10, 2):  # 0, 2, 4, 6, 8
    print(i)

# while 循环
count = 0
while count < 5:
    print(count)
    count += 1

# break 和 continue
for i in range(10):
    if i == 3:
        continue  # 跳过本次循环
    if i == 7:
        break     # 跳出循环
    print(i)
```

**Java 对比：**
```java
// Java
for (int i = 0; i < 5; i++) {
    System.out.println(i);
}
for (String fruit : fruits) {
    System.out.println(fruit);
}
```

### 2.3 函数定义

```python
# 基本函数
def greet(name: str) -> str:
    """问候函数（docstring）"""
    return f"Hello, {name}!"

# 带默认参数
def connect(host: str = "localhost", port: int = 8080) -> None:
    print(f"Connecting to {host}:{port}")

# 可变参数
def sum_all(*numbers) -> int:
    total = 0
    for n in numbers:
        total += n
    return total

print(sum_all(1, 2, 3, 4, 5))  # 15

# 关键字参数
def create_user(name: str, age: int, admin: bool = False) -> dict:
    return {"name": name, "age": age, "admin": admin}

user = create_user(name="Alice", age=30)
user = create_user(age=25, name="Bob")  # 关键字参数可以打乱顺序
```

**Java 对比：**
```java
// Java
public String greet(String name) {
    return "Hello, " + name + "!";
}

public void connect(String host, int port) {
    System.out.println("Connecting to " + host + ":" + port);
}
```

### 2.4 类定义

```python
class Agent:
    """智能体基类"""
    
    # 类变量（相当于 Java 的 static 变量）
    count = 0
    
    def __init__(self, name: str, model: str = "gpt-4"):
        """构造函数（相当于 Java 的构造器）"""
        self.name = name          # 实例变量
        self.model = model
        self._active = False      # _ 前缀表示受保护
        self.__secret = None     # __ 前缀表示私有
        Agent.count += 1
    
    def start(self) -> None:
        """启动智能体"""
        self._active = True
        print(f"{self.name} started with {self.model}")
    
    def stop(self) -> None:
        """停止智能体"""
        self._active = False
        print(f"{self.name} stopped")
    
    def __str__(self) -> str:
        """字符串表示（相当于 Java 的 toString）"""
        return f"Agent({self.name}, {self.model})"
    
    @property
    def is_active(self) -> bool:
        """属性（相当于 Java 的 getter）"""
        return self._active
    
    @classmethod
    def get_count(cls) -> int:
        """类方法（相当于 Java 的静态方法）"""
        return cls.count
    
    @staticmethod
    def validate_name(name: str) -> bool:
        """静态方法"""
        return len(name) > 0 and len(name) <= 50


# 继承
class ChatAgent(Agent):
    def __init__(self, name: str, model: str = "gpt-4", temperature: float = 0.7):
        super().__init__(name, model)
        self.temperature = temperature
    
    def chat(self, message: str) -> str:
        """聊天方法"""
        return f"{self.name}: Processing '{message}' with temp={self.temperature}"
```

**Java 对比：**
```java
// Java
public class Agent {
    private String name;
    private String model;
    private boolean active;
    
    public Agent(String name, String model) {
        this.name = name;
        this.model = model;
        this.active = false;
    }
    
    public void start() {
        this.active = true;
    }
    
    public boolean isActive() {
        return active;
    }
}
```

### 2.5 异常处理

```python
try:
    result = 10 / 0
except ZeroDivisionError:
    print("Cannot divide by zero!")
except Exception as e:
    print(f"Error: {e}")
finally:
    print("Cleanup here")

# 抛出异常
def validate_age(age: int) -> None:
    if age < 0:
        raise ValueError("Age cannot be negative")
    if age > 150:
        raise ValueError("Age is unrealistic")
```

**Java 对比：**
```java
// Java
try {
    int result = 10 / 0;
} catch (ArithmeticException e) {
    System.out.println("Cannot divide by zero!");
} finally {
    System.out.println("Cleanup here");
}
```

### 2.6 常用内置函数

```python
# 字符串操作
text = "  Hello, Python!  "
text.strip()           # "Hello, Python!"
text.lower()           # "  hello, python!  "
text.upper()           # "  HELLO, PYTHON!  "
text.replace("Python", "Java")  # "  Hello, Java!  "
text.split(",")        # ["  Hello", " Python!  "]
",".join(["a", "b", "c"])  # "a,b,c"

# 列表操作
numbers = [3, 1, 4, 1, 5, 9, 2, 6]
sorted(numbers)        # [1, 1, 2, 3, 4, 5, 6, 9] (返回新列表)
numbers.sort()         # 就地排序
numbers.append(7)     # 添加元素
numbers.extend([8, 9])  # 合并列表
numbers.pop()         # 弹出并返回最后一个元素

# 字典操作
config = {"host": "localhost", "port": 8080}
config.keys()         # dict_keys(['host', 'port'])
config.values()       # dict_values(['localhost', 8080])
config.items()        # dict_items([('host', 'localhost'), ('port', 8080)])
config.get("debug", False)  # 获取值，不存在返回默认值
config.update({"debug": True})  # 合并字典

# 类型转换
int("42")             # 字符串转整数
float("3.14")         # 字符串转浮点数
str(123)              # 转字符串
list((1, 2, 3))       # 元组转列表
bool(0)               # False
bool(1)               # True
```

---

## 3. Python 异步编程（async/await）详解

Python 的 `async/await` 是处理并发任务的强大机制，类似于 JavaScript 的 Promise 或 Java 的 CompletableFuture，但语法更简洁。**这是 Java 开发者需要重点学习的新概念。**

### 3.1 基本概念

```python
import asyncio

# 同步函数
def sync_function():
    return "sync result"

# 异步函数（asyncio 的核心）
async def async_function():
    return "async result"

# 运行协程
result = asyncio.run(async_function())
print(result)  # "async result"
```

### 3.2 async/await 语法

```python
import asyncio
import time

# 模拟耗时操作
async def fetch_data(delay: float, name: str) -> str:
    """模拟获取数据（相当于 Java 的 CompletableFuture.supplyAsync）"""
    print(f"[{name}] Starting fetch...")
    await asyncio.sleep(delay)  # 异步等待（不阻塞其他任务）
    return f"{name} data"

async def main():
    """主异步函数"""
    # 顺序执行（总耗时 = 所有延迟之和）
    start = time.time()
    result1 = await fetch_data(1.0, "API1")
    result2 = await fetch_data(1.0, "API2")
    print(f"Sequential took: {time.time() - start:.2f}s")
    print(f"Results: {result1}, {result2}")

asyncio.run(main())
```

### 3.3 并发执行

```python
async def concurrent_demo():
    """并发执行多个任务（相当于 Java 的 CompletableFuture.allOf）"""
    start = time.time()
    
    # 并发执行：gather 等待所有任务完成
    results = await asyncio.gather(
        fetch_data(1.0, "API1"),
        fetch_data(2.0, "API2"),
        fetch_data(1.5, "API3"),
    )
    
    elapsed = time.time() - start
    print(f"Concurrent took: {elapsed:.2f}s")  # ~2.0s（最长任务的耗时）
    print(f"Results: {results}")

asyncio.run(concurrent_demo())
```

### 3.4 并发替代顺序

```python
# 顺序执行（慢）
async def sequential():
    await fetch_data(1.0, "A")
    await fetch_data(1.0, "B")
    await fetch_data(1.0, "C")
    # 总耗时: 3.0s

# 并发执行（快）
async def parallel():
    await asyncio.gather(
        fetch_data(1.0, "A"),
        fetch_data(1.0, "B"),
        fetch_data(1.0, "C"),
    )
    # 总耗时: 1.0s
```

### 3.5 实际应用示例（来自 QwenPaw）

QwenPaw 的 `MultiAgentManager` 展示了 async/await 的实际应用：

```python
import asyncio
from typing import Dict

class MultiAgentManager:
    def __init__(self):
        self.agents: Dict[str, Workspace] = {}
        self._lock = asyncio.Lock()  # 异步锁
    
    async def get_agent(self, agent_id: str) -> Workspace:
        """异步获取智能体（懒加载）"""
        # 快速路径：已缓存则直接返回
        if agent_id in self.agents:
            return self.agents[agent_id]
        
        # 使用锁保护共享状态
        async with self._lock:
            # 双重检查锁定
            if agent_id in self.agents:
                return self.agents[agent_id]
            
            # 创建新实例
            instance = Workspace(agent_id=agent_id)
            await instance.start()  # 异步启动
            
            self.agents[agent_id] = instance
            return instance
    
    async def reload_agent(self, agent_id: str) -> None:
        """异步重载智能体"""
        async with self._lock:
            if agent_id in self.agents:
                await self.agents[agent_id].stop()
                await self.agents[agent_id].start()
```

### 3.6 asyncio 其他常用功能

```python
# 创建后台任务
async def background_task():
    while True:
        await asyncio.sleep(1)
        print("Running...")

async def main():
    # 创建任务（不立即执行）
    task = asyncio.create_task(background_task())
    
    # 可以取消任务
    # task.cancel()
    
    # 等待任务完成（带超时）
    try:
        await asyncio.wait_for(task, timeout=5.0)
    except asyncio.TimeoutError:
        print("Task timed out")
    
    # 或等待一组任务
    task1 = asyncio.create_task(do_something())
    task2 = asyncio.create_task(do_something_else())
    done, pending = await asyncio.wait([task1, task2])
```

### 3.7 与 Java 对比

| Java | Python |
|------|--------|
| `CompletableFuture.supplyAsync()` | `asyncio.create_task()` |
| `future.get()` | `await future` |
| `CompletableFuture.allOf()` | `asyncio.gather()` |
| `ExecutorService` | `asyncio.Lock()` |
| `Future.cancel()` | `task.cancel()` |
| `@Async` 注解 | `async def` |

---

## 4. Python 类型提示（Type Hints）

Python 3.5+ 引入了类型提示，允许为变量、函数参数和返回值声明类型。这使得静态检查工具（如 mypy）可以检测类型错误，同时保持代码的可读性。

### 4.1 基本类型提示

```python
# 变量类型提示
name: str = "QwenPaw"
age: int = 25
price: float = 99.99
is_active: bool = True
items: list = []  # 不指定元素类型
tags: list[str] = ["python", "java"]  # Python 3.9+
numbers: list[int] = [1, 2, 3]

# 字典类型提示
config: dict = {}  # 不指定键值类型
config: dict[str, str] = {"host": "localhost"}  # Python 3.9+
config: dict[str, int | str] = {"port": 8080, "host": "localhost"}  # 联合类型

# 可空类型（相当于 Java 的 Optional）
from typing import Optional

result: Optional[str] = None  # str 或 None
result: str | None = None    # Python 3.10+ 简化写法
```

### 4.2 函数类型提示

```python
def greet(name: str, times: int = 1) -> str:
    """带类型提示的函数"""
    return (f"Hello, {name}! " * times).strip()

# 返回 None 的函数
def log_message(message: str) -> None:
    print(message)

# 多类型参数
def process(value: int | str | float) -> str:
    return str(value)

# 可选参数（带默认值）
def connect(host: str, port: int = 8080, timeout: float | None = None) -> bool:
    ...
```

### 4.3 复杂类型

```python
from typing import Dict, List, Set, Tuple, Optional, Callable, Any

# 嵌套类型
users: List[Dict[str, Any]] = [
    {"name": "Alice", "age": 30},
    {"name": "Bob", "age": 25},
]

# 元组（固定长度和类型）
point: Tuple[float, float] = (10.5, 20.3)
rgb: Tuple[int, int, int] = (255, 128, 0)

# 集合
unique_tags: Set[str] = {"python", "java", "go"}

# 可调用对象（函数类型）
def apply(func: Callable[[int], int], value: int) -> int:
    return func(value)

add_one: Callable[[int], int] = lambda x: x + 1

# 回调函数
def fetch_data(
    callback: Callable[[str], None],
    on_error: Callable[[Exception], None]
) -> None:
    try:
        result = "data"
        callback(result)
    except Exception as e:
        on_error(e)
```

### 4.4 自定义类型

```python
from typing import TypeAlias, NewType

# 类型别名
UserId: TypeAlias = int | str
AgentConfig: TypeAlias = dict[str, str | int | bool]

# NewType（编译时类型检查）
UserId = NewType('UserId', int)
OrderId = NewType('OrderId', str)

def get_user(user_id: UserId) -> dict:
    return {"id": user_id}

# 泛型
from typing import Generic, TypeVar

T = TypeVar('T')
K = TypeVar('K')
V = TypeVar('V')

class Box(Generic[T]):
    def __init__(self, content: T):
        self.content = content
    
    def get(self) -> T:
        return self.content

string_box: Box[str] = Box("hello")
int_box: Box[int] = Box(42)
```

### 4.5 QwenPaw 中的类型提示示例

QwenPaw 大量使用类型提示：

```python
# 来自 qwenpaw/exceptions.py
from typing import Any, Dict, Optional

class ProviderError(AgentRuntimeErrorException):
    def __init__(
        self,
        message: str,
        details: Optional[Dict[str, Any]] = None,  # 可选的字典类型
    ) -> None:
        super().__init__("PROVIDER_ERROR", message, details)

# 来自 qwenpaw/constant.py
class EnvVarLoader:
    @staticmethod
    def get_bool(env_var: str, default: bool = False) -> bool:
        ...
    
    @staticmethod
    def get_float(
        env_var: str,
        default: float = 0.0,
        min_value: float | None = None,  # Python 3.10+ 联合类型语法
        max_value: float | None = None,
        allow_inf: bool = False,
    ) -> float:
        ...
```

### 4.6 TYPE_CHECKING 技巧

```python
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    # 这些导入只在类型检查时生效，运行时不导入
    # 可以避免循环导入
    from .some_module import SomeClass

class MyClass:
    def __init__(self, name: str):
        self.name = name
    
    def process(self, other: "SomeClass") -> None:  # 前向引用
        ...
```

---

## 5. pip 和虚拟环境

Python 项目管理涉及依赖安装和环境隔离。Java 有 Maven/Gradle，Python 有 pip 和虚拟环境。

### 5.1 pip 基础

```bash
# 安装包
pip install requests
pip install httpx>=0.27.0

# 从 requirements.txt 安装
pip install -r requirements.txt

# 卸载包
pip uninstall requests

# 查看已安装的包
pip list

# 导出依赖
pip freeze > requirements.txt

# 升级包
pip install --upgrade httpx
```

### 5.2 虚拟环境

虚拟环境将每个项目的依赖隔离，避免版本冲突。**强烈建议每个项目使用独立虚拟环境。**

```bash
# 创建虚拟环境
python -m venv .venv

# 激活虚拟环境
# Linux/macOS:
source .venv/bin/activate

# Windows:
.venv\Scripts\activate

# 激活后，pip 会安装到虚拟环境
pip install httpx

# 退出虚拟环境
deactivate
```

### 5.3 pyproject.toml（现代方式）

QwenPaw 使用 `pyproject.toml` 作为项目配置（相当于 Java 的 pom.xml 或 build.gradle）：

```toml
[project]
name = "qwenpaw"
dynamic = ["version"]
description = "QwenPaw is a personal assistant"
requires-python = ">=3.10,<3.14"

dependencies = [
    "httpx>=0.27.0",
    "uvicorn>=0.40.0",
    "fastapi>=0.100.0",
    "packaging>=24.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.3.5",
    "pytest-asyncio>=0.23.0",
    "pre-commit>=4.2.0",
]

[project.scripts]
qwenpaw = "qwenpaw.cli.main:cli"

[build-system]
requires = ["setuptools>=42", "wheel"]
build-backend = "setuptools.build_meta"
```

```bash
# 安装项目（开发模式）
pip install -e .

# 安装可选依赖
pip install -e ".[dev]"      # 开发依赖
pip install -e ".[full]"     # 完整依赖

# 构建发布包
pip build
```

### 5.4 pipx（工具隔离）

如果只想安装 CLI 工具而不影响全局 Python：

```bash
# 安装工具到隔离环境
pipx install black
pipx install mypy

# 运行工具
pipx run black .
```

### 5.5 与 Java 对比

| Java | Python |
|------|--------|
| Maven/Gradle | pip + pyproject.toml |
| pom.xml / build.gradle | pyproject.toml |
| mvn package | pip build |
| mvn dependency:tree | pip freeze |
| .m2/repository | ~/.cache/pip |
| mvn exec:java | pip run |

### 5.6 QwenPaw 项目结构

```
QwenPaw/
├── src/qwenpaw/           # 源代码
│   ├── __init__.py
│   ├── cli/               # CLI 模块
│   ├── app/               # 应用模块
│   └── ...
├── tests/                 # 测试代码
├── pyproject.toml         # 项目配置
├── .python-version        # Python 版本约束
├── .venv/                 # 虚拟环境
└── Makefile               # 构建脚本
```

### 5.7 开发工作流

```bash
# 1. 克隆项目
git clone https://github.com/example/qwenpaw.git
cd qwenpaw

# 2. 创建虚拟环境
python -m venv .venv
source .venv/bin/activate

# 3. 安装项目
pip install -e ".[dev]"

# 4. 运行测试
make test

# 5. 代码检查
make lint  # 或 python -m pre_commit run --all-files
```

---

## 6. 总结

作为 Java 开发者学习 Python，需要关注以下几点：

1. **缩进代替花括号** - 这是最直观的差异，需要适应
2. **动态类型 + 类型提示** - Python 是动态类型，但可以用类型提示辅助
3. **async/await** - 这是 Java 没有的概念，需要重点学习
4. **虚拟环境** - 每个项目使用独立环境是最佳实践
5. **现代包管理** - 使用 pyproject.toml 而非 requirements.txt

QwenPaw 项目是一个很好的参考，展示了 Python 在实际应用中的最佳实践，包括类型提示的广泛使用、异步编程模式等。
