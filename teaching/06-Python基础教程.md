# Python 基础教程（面向 Java 开发者）

## 本章导读

| 项目 | 内容 |
|------|------|
| **学习目标** | 完成本章后，你能够：1) 使用 Python 基本语法编写简单脚本 2) 理解 Python 与 Java 的关键差异 3) 阅读 QwenPaw 项目中的 Python 代码 |
| **前置知识** | [01-项目介绍](./01-项目介绍.md)、[03-项目架构](./03-项目架构.md) |
| **预计时长** | 60 分钟（阅读 40 分钟 + 练习 20 分钟） |
| **难度等级** | ⭐⭐ |
| **核心关键词** | `Python语法` `类型提示` `异步编程` `装饰器` |

> **一句话概述**：本章以 Java 开发者视角讲解 Python 核心语法，帮助你快速掌握阅读 QwenPaw 源码所需的 Python 基础。

## 概述

本教程为有 Java 背景的开发者快速掌握 Python 基础而编写。Python 和 Java 在很多概念上是相通的，但语法和编程风格有显著差异。通过类比 Java 语法，可以帮助 Java 开发者更快上手 Python。

本教程涵盖 Python 核心语法、异步编程基础、类型提示系统以及项目管理工具。完成学习后，你将能够阅读 QwenPaw 源码并参与项目开发。

**前置知识**：熟悉 Java 编程，理解面向对象概念。

**学习目标**：
- 理解 Python 与 Java 的核心差异
- 掌握 Python 基本语法和数据结构
- 理解 async/await 异步编程模型
- 掌握类型提示的用法
- 熟悉 pip 和虚拟环境的使用

---

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

### 关键区别详解

**1. 缩进代替花括号**

Python 使用缩进定义代码块，这是 Java 开发者需要适应的重要差异。统一的缩进风格使代码更具可读性，但需要借助 IDE 的自动格式化功能避免缩进错误。

```python
# Python - 缩进定义代码块
if x > 0:
    print("positive")
    if x > 10:
        print("large")
else:
    print("non-positive")
```

```java
// Java - 花括号界定代码块
if (x > 0) {
    System.out.println("positive");
    if (x > 10) {
        System.out.println("large");
    }
} else {
    System.out.println("non-positive");
}
```

**2. 动态类型 + 类型提示**

Python 是动态类型语言，变量可以随时指向不同类型的对象。类型提示（Type Hints）是 Python 3.5+ 引入的可选特性，用于为 IDE 和静态检查工具提供类型信息。

```python
# Python 可以不声明类型，但可以用类型提示
name: str = "QwenPaw"  # 类型提示（不影响运行时）
age: int = 25
```

**3. Everything is an object**

在 Python 中，一切皆为对象——函数、类、模块甚至代码块都是对象。这使得函数式编程模式成为可能。

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

Python 的内置数据类型比 Java 更简洁，没有 int/float/double 的区分，而是通过自动类型推断处理。

```python
# 字符串
name = "QwenPaw"
version = '1.0'
multi_line = """多行
字符串"""

# 数字（Python 自动区分整数和浮点数）
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

**Java 对比**：

```java
// Java
String name = "QwenPaw";
List<Integer> numbers = Arrays.asList(1, 2, 3);
Map<String, Object> config = new HashMap<>();
config.put("host", "localhost");
config.put("port", 8080);
config.put("debug", true);
Set<String> tags = new HashSet<>(Arrays.asList("python", "java"));
```

**类型转换**：

```python
# Python 的类型转换
int("42")             # 字符串转整数
float("3.14")         # 字符串转浮点数
str(123)              # 转字符串
list((1, 2, 3))       # 元组转列表
bool(0)               # False
bool(1)               # True
bool("")              # False
bool("hello")         # True
```

### 2.2 控制流

Python 的控制流语法比 Java 更简洁，但功能相同。

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

**Java 对比**：

```java
// Java
String status = age >= 18 ? "成年" : "未成年";
```

**循环结构**：

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

**Java 对比**：

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

Python 函数定义使用 `def` 关键字，支持默认参数、可变参数和关键字参数。

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

**Java 对比**：

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

Python 的类定义比 Java 更简洁，但概念相通。需要注意 `self` 参数相当于 Java 的 `this`。

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

**Java 对比**：

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

Python 的异常处理与 Java 类似，但语法更简洁。

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

**Java 对比**：

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

Python 提供了丰富的内置函数，无需导入即可使用。

**字符串操作**：

```python
text = "  Hello, Python!  "
text.strip()           # "Hello, Python!"
text.lower()           # "  hello, python!  "
text.upper()           # "  HELLO, PYTHON!  "
text.replace("Python", "Java")  # "  Hello, Java!  "
text.split(",")        # ["  Hello", " Python!  "]
",".join(["a", "b", "c"])  # "a,b,c"
text.find("Python")    # 4（找不到返回 -1）
text.startswith("  ")  # True
text.endswith("!  ")  # True
```

**列表操作**：

```python
numbers = [3, 1, 4, 1, 5, 9, 2, 6]
sorted(numbers)        # [1, 1, 2, 3, 4, 5, 6, 9] (返回新列表)
numbers.sort()         # 就地排序
numbers.append(7)     # 添加元素
numbers.extend([8, 9])  # 合并列表
numbers.pop()         # 弹出并返回最后一个元素
numbers.insert(0, 0)  # 在指定位置插入
numbers.remove(1)     # 移除第一个匹配的元素
numbers.reverse()     # 反转列表
len(numbers)          # 列表长度
```

**字典操作**：

```python
config = {"host": "localhost", "port": 8080}
config.keys()         # dict_keys(['host', 'port'])
config.values()       # dict_values(['localhost', 8080])
config.items()        # dict_items([('host', 'localhost'), ('port', 8080)])
config.get("debug", False)  # 获取值，不存在返回默认值
config.update({"debug": True})  # 合并字典
config.pop("port")    # 弹出并返回指定键的值
config.setdefault("timeout", 30)  # 设置默认值
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
from typing import Dict, Set

class MultiAgentManager:
    def __init__(self):
        self.agents: Dict[str, Workspace] = {}
        self._lock = asyncio.Lock()  # 异步锁
        self._pending_starts: Dict[str, asyncio.Event] = {}  # 待启动事件
        self._cleanup_tasks: Set[asyncio.Task] = set()         # 清理任务

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

### 3.7 Java 对照表

| Java | Python |
|------|--------|
| `CompletableFuture.supplyAsync()` | `asyncio.create_task()` |
| `future.get()` | `await future` |
| `CompletableFuture.allOf()` | `asyncio.gather()` |
| `ExecutorService` | `asyncio.Lock()` |
| `Future.cancel()` | `task.cancel()` |
| `@Async` 注解 | `async def` |

### 🐍 来自 Java 的你

如果你熟悉 Java 的并发编程，下表帮你快速找到 Python 中的对应概念：

| Java | Python | 说明 |
|------|--------|------|
| `CompletableFuture.supplyAsync(Supplier)` | `asyncio.create_task()` 或直接 `asyncio.gather()` | 创建异步任务 |
| `future.get()` | `await coroutine` | 阻塞等待异步结果 |
| `CompletableFuture.allOf(f1, f2, ...)` | `await asyncio.gather(task1, task2)` | 并发执行多个任务并等待全部完成 |
| `CompletableFuture.thenCompose()` | `await` 链式调用 | 异步任务链式组合 |
| `ExecutorService` + `submit()` | `asyncio.create_task()` | 提交异步任务到线程池/事件循环 |
| `newSingleThreadExecutor()` | `asyncio.Lock()` | 串行化访问共享资源 |
| `ReentrantLock.lock()` / `unlock()` | `async with lock:` | 异步锁的获取与释放 |
| `CountDownLatch.await()` | `asyncio.Event.wait()` | 等待事件触发 |
| `Semaphore.acquire()` / `release()` | `asyncio.Semaphore` | 控制并发数量 |
| `ScheduledExecutorService.schedule()` | `asyncio.get_event_loop().call_later()` | 延迟执行一次性任务 |
| `Future.isDone()` | `task.done()` | 检查任务是否完成 |

**关键区别**：
- Python 的 `async/await` 是单线程协作式并发，Java 的 `CompletableFuture` 通常基于线程池
- Python 异步代码必须显式使用 `await` 才能让出控制权，Java 的 `Future.get()` 会阻塞线程
- Python 的协程比线程更轻量，同一线程可以运行数千个协程

---

## 4. Python 类型提示（Type Hints）

Python 3.5+ 引入了类型提示，允许为变量、函数参数和返回值声明类型。这使得静态检查工具（如 mypy）可以检测类型错误，同时保持代码的可读性。

**进阶内容**：详见 [06.1-Python进阶教程.md](./06.1-Python进阶教程.md) 第3章 Pydantic 数据模型和第4章 dataclass。

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

### 5.5 Java 对照表

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

## 6. 应用场景

### 6.1 Web 开发

Python 的异步特性使其非常适合构建高性能 Web 服务。QwenPaw 使用 FastAPI 作为 Web 框架。

```python
from fastapi import FastAPI

app = FastAPI()

@app.get("/api/health")
async def health_check():
    return {"status": "healthy"}

@app.post("/api/agents")
async def create_agent(request: CreateAgentRequest):
    agent = await agent_manager.create_agent(request)
    return agent
```

### 6.2 脚本与自动化

Python 是编写系统脚本的理想语言：

```python
#!/usr/bin/env python3
"""自动化脚本示例"""
import asyncio
from pathlib import Path

async def cleanup_old_files(directory: Path, days: int = 7):
    """清理指定目录下超过指定天数的文件"""
    from datetime import datetime, timedelta
    cutoff = datetime.now() - timedelta(days=days)

    for file in directory.rglob("*.log"):
        if datetime.fromtimestamp(file.stat().st_mtime) < cutoff:
            file.unlink()
            print(f"Deleted: {file}")

if __name__ == "__main__":
    asyncio.run(cleanup_old_files(Path.home() / "logs"))
```

### 6.3 数据处理

Python 的列表推导式和丰富的标准库使数据处理变得简洁：

```python
# 列表推导式
squares = [x**2 for x in range(10)]
evens = [x for x in range(100) if x % 2 == 0]

# 字典推导式
word_lengths = {word: len(word) for word in ["apple", "banana", "cherry"]}

# 聚合操作
from collections import defaultdict
word_count = defaultdict(int)
for word in ["apple", "banana", "apple", "cherry", "banana"]:
    word_count[word] += 1
# {'apple': 2, 'banana': 2, 'cherry': 1}
```

### 6.4 QwenPaw 中的典型场景

**异步初始化**：

```python
async def initialize_application():
    """应用初始化场景：并发加载多个组件"""
    # 顺序初始化（慢）
    config = await load_config()
    plugins = await load_plugins()
    agents = await create_agents()

    # 并发初始化（快）
    config, plugins, agents = await asyncio.gather(
        load_config(),
        load_plugins(),
        create_agents()
    )
```

**带超时的操作**：

```python
async def call_with_timeout():
    """需要设置超时的场景"""
    try:
        async with asyncio.timeout(30.0):
            result = await long_running_operation()
    except asyncio.TimeoutError:
        logger.warning("Operation timed out after 30 seconds")
        result = None
    return result
```

---

## 7. 最佳实践

### 7.1 代码风格

**使用 Black 格式化代码**：

Black 是 Python 最流行的代码格式化工具，遵循 PEP 8 规范但更加严格。

```bash
# 安装
pip install black

# 格式化文件
black src/

# 检查格式（不修改）
black --check src/
```

**使用 Ruff 进行 linting**：

Ruff 是 Python 最快的 linter，比 flake8 快 10-100 倍。

```bash
pip install ruff
ruff check src/
ruff check --fix src/  # 自动修复
```

### 7.2 虚拟环境管理

**使用 pyenv 管理 Python 版本**：

```bash
# 安装 pyenv
brew install pyenv

# 安装特定版本
pyenv install 3.11.5

# 设置项目 Python 版本
echo "3.11.5" > .python-version
pyenv local
```

**使用 Direnv 管理环境变量**：

```bash
# 安装
brew install direnv

# 在项目目录创建 .envrc
echo 'export OPENAI_API_KEY="sk-xxx"' > .envrc
direnv allow
```

### 7.3 类型检查

**使用 mypy 进行静态类型检查**：

```bash
pip install mypy
mypy src/

# 严格模式
mypy --strict src/
```

**在 IDE 中启用类型检查**：

VS Code 用户应安装 Pylance 扩展，它提供实时类型检查和智能补全。

### 7.4 测试实践

**使用 pytest + pytest-asyncio**：

```python
import pytest

@pytest.fixture
def sample_agent():
    """测试夹具"""
    return Agent(name="test", model="gpt-4")

@pytest.mark.asyncio
async def test_agent_lifecycle(sample_agent):
    """测试智能体生命周期"""
    assert not sample_agent.is_active
    await sample_agent.start()
    assert sample_agent.is_active
    await sample_agent.stop()
    assert not sample_agent.is_active
```

---

## 8. 常见问题

### 8.1 为什么 Python 的 `==` 比较和 `is` 不同？

- `==` 比较值是否相等
- `is` 比较对象身份（内存地址）

```python
a = [1, 2, 3]
b = [1, 2, 3]
print(a == b)  # True（值相等）
print(a is b)  # False（不同对象）

c = a
print(a is c)  # True（同一个对象）
```

**注意**：对于小整数和小字符串，Python 会进行 interning优化，可能出现 `a is b` 为 True 的情况，但这不是可靠的行为。

### 8.2 如何正确比较字符串？

始终使用 `==` 比较字符串值：

```python
name1 = "Alice"
name2 = "Alice"
print(name1 == name2)  # True
print(name1 is name2)  # 可能 True（interning），但不可靠
```

### 8.3 为什么不要使用 `time.sleep()` 在 async 代码中？

`time.sleep()` 会阻塞整个线程，而 `asyncio.sleep()` 只会暂停当前协程，让事件循环处理其他任务。

```python
# ❌ 错误：在 async 函数中使用 time.sleep
async def bad_example():
    time.sleep(5)  # 阻塞整个程序 5 秒

# ✅ 正确：使用 asyncio.sleep
async def good_example():
    await asyncio.sleep(5)  # 暂停 5 秒，但允许其他任务运行
```

### 8.4 为什么函数参数默认值不要使用可变对象？

```python
# ❌ 危险：默认参数在函数定义时创建，所有调用共享同一个对象
def add_item(item, items=[]):
    items.append(item)
    return items

print(add_item("a"))  # ['a']
print(add_item("b"))  # ['a', 'b'] — 预期之外！

# ✅ 正确：使用 None 作为默认值
def add_item(item, items=None):
    if items is None:
        items = []
    items.append(item)
    return items
```

### 8.5 如何处理循环导入？

循环导入是 Python 项目中的常见问题。有几种解决方案：

**方案1：延迟导入（在函数内部导入）**：

```python
# module_a.py
def func_a():
    from module_b import ClassB  # 延迟导入
    return ClassB()
```

**方案2：使用 TYPE_CHECKING**：

```python
# module_a.py
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from module_b import ClassB  # 仅类型检查时导入

class ClassA:
    def method(self, other: "ClassB") -> None:  # 前向引用
        pass
```

**方案3：重构代码结构**：将共享的类型和常量移到独立的模块中。

### 8.6 如何调试 Python 异步代码？

**使用 `asyncio.run()` 配合异常堆栈**：

```python
import asyncio

async def problematic_async_func():
    raise ValueError("test error")

try:
    asyncio.run(problematic_async_func())
except Exception as e:
    import traceback
    traceback.print_exc()
```

**使用 breakpoint() 和 pdb**：

```python
async def debug_async():
    import pdb
    pdb.set_trace()
    result = await some_async_operation()
    return result
```

### 8.7 pip 安装失败怎么办？

```bash
# 清理 pip 缓存
pip cache purge

# 使用国内镜像
pip install -i https://pypi.tuna.tsinghua.edu.cn/simple some-package

# 升级 pip
python -m pip install --upgrade pip

# 创建新的虚拟环境
python -m venv new_venv
source new_venv/bin/activate
pip install -r requirements.txt
```

---

## 练习题

### 基础练习

1. **Python 语法转换**：将以下 Java 代码转换为 Python（注意缩进和类型提示）：
   ```java
   public class User {
       private String name;
       private int age;

       public User(String name, int age) {
           this.name = name;
           this.age = age;
       }

       public String getName() { return name; }
       public int getAge() { return age; }
   }
   ```

2. **异步函数理解**：解释以下代码的输出顺序（参考 `07-智能体核心架构.md` 中的 `multi_agent_manager.py`）：
   ```python
   import asyncio

   async def task_a():
       print("A start")
       await asyncio.sleep(0.5)
       print("A end")

   async def task_b():
       print("B start")
       await asyncio.sleep(0.3)
       print("B end")

   async def main():
       await asyncio.gather(task_a(), task_b())

   asyncio.run(main())
   ```

3. **类型提示练习**：为以下函数添加完整的类型提示，并说明每个类型的作用：
   ```python
   def process_items(items, filter_fn, default=None):
       result = [x for x in items if filter_fn(x)]
       return result if result else default
   ```

### 进阶练习

1. **异步锁实现**：参考 `07-智能体核心架构.md` 中的 `MultiAgentManager` 示例，实现一个异步缓存类 `AsyncCache`，要求：
   - 支持 `get(key)` 和 `set(key, value)` 异步方法
   - 使用 `asyncio.Lock` 保护共享状态
   - 包含缓存过期逻辑（可选）

2. **上下文管理器**：实现一个测量异步函数执行时间的上下文管理器：
   ```python
   class Timer:
       async def __aenter__(self):
           # TODO: 记录开始时间
           pass

       async def __aexit__(self, *args):
           # TODO: 计算并打印耗时
           pass
   ```

3. **类型约束**：使用 `NewType` 定义 `UserId` 和 `SessionId`，并编写一个验证函数确保 ID 格式正确（参考 `08-消息渠道系统.md` 中的渠道 ID 处理）。

### 实战练习

- **QwenPaw 配置解析器**：参考 `src/qwenpaw/config/config.py`，实现一个简化版的配置解析器：
  1. 使用 `@dataclass` 定义配置模型
  2. 支持从环境变量或 YAML 文件加载配置
  3. 实现配置验证（参考 Pydantic 风格）
  4. 包含异步初始化方法 `async def initialize()`

**答案提示**：
- 参考 `06.1-Python进阶教程.md` 中的 Pydantic 和 dataclass 章节
- 参考 `src/qwenpaw/config/config.py` 的配置加载模式
- 异步上下文管理器可参考 `src/qwenpaw/app/_app.py` 的应用启动模式

---

## 9. 总结

### 学习要点回顾

作为 Java 开发者学习 Python，需要关注以下核心差异：

| 序号 | 要点 | 说明 |
|------|------|------|
| 1 | **缩进代替花括号** | 这是最直观的差异，需要适应使用空格/Tab 界定代码块 |
| 2 | **动态类型 + 类型提示** | Python 是动态类型，但类型提示可以提供静态检查能力 |
| 3 | **async/await** | Java 没有的并发模型，是处理 I/O 密集型任务的关键 |
| 4 | **虚拟环境** | 每个项目使用独立环境是 Python 开发最佳实践 |
| 5 | **现代包管理** | 使用 pyproject.toml 而非 requirements.txt |
| 6 | **访问控制约定** | `_` 和 `__` 前缀代替 `private`/`protected` 关键字 |

### 进阶学习路径

完成本教程后，建议继续学习：

1. **[06.1-Python进阶教程.md](./06.1-Python进阶教程.md)** — 装饰器、上下文管理器、Pydantic、 dataclass、ABC 等高级特性
2. **[07-智能体核心架构.md](./07-智能体核心架构.md)** — 理解 QwenPaw 的智能体设计
3. **[08-消息渠道系统.md](./08-消息渠道系统.md)** — 消息传递与并发处理

### QwenPaw 项目参考

QwenPaw 项目展示了 Python 在实际应用中的最佳实践：

- **类型提示**：全面使用类型注解，便于 IDE 和 mypy 检查
- **异步编程**：大量使用 async/await 处理并发任务
- **项目结构**：遵循 `src/` layout，清晰的分层架构
- **代码质量**：使用 Black、Ruff、mypy 保证代码风格和类型安全

建议通过阅读 QwenPaw 源码来巩固 Python 知识，特别是以下模块：

- `src/qwenpaw/app/_app.py` — 应用入口和异步上下文管理
- `src/qwenpaw/app/multi_agent_manager.py` — 异步锁和并发模式
- `src/qwenpaw/config/config.py` — Pydantic 配置模型
- `src/qwenpaw/agents/` — 智能体核心实现

## 知识检查

1. Python 的列表推导式与 Java Stream 有什么异同？
2. Python 的 `async/await` 与 Java 的 `CompletableFuture` 有何区别？
3. 为什么 Python 推荐使用 `pathlib.Path` 而非字符串拼接路径？

## 延伸阅读

| 方向 | 章节 | 说明 |
|------|------|------|
| 进阶学习 | [06.1-Python进阶教程](./06.1-Python进阶教程.md) | 基于源码的 Python 进阶 |
| 核心架构 | [07-智能体核心架构](./07-智能体核心架构.md) | 理解智能体设计 |
| 下一章 | [06.1-Python进阶教程](./06.1-Python进阶教程.md) | 继续深入学习 |

