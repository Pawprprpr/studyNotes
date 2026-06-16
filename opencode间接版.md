# OpenCode 源码学习笔记

> 基于 5 年 Java 经验，系统学习 AI Agent 开发核心机制

---

## 一、整体架构

### 1.1 项目结构

```
packages/
├── opencode/        # 后端 Agent 核心
├── app/             # Web 前端（SolidJS）
├── desktop/         # Desktop 前端（Tauri/Electron）
├── extensions/      # IDE 插件（Zed 等）
└── sdk/             # JS/Python/Java SDK
```

### 1.2 三层架构

```
用户（GUI/CLI）
    │
    ▼ HTTP/SSE（localhost:4096）
OpenCode 后端（本地进程）
    │
    ▼ API（远程调用）
LLM 服务（Anthropic/OpenAI/GitLab...）
```

**关键认知**：Agent 运行在本地，LLM 才是远程服务端。

---

## 二、Agent / Provider / Tool 关系

### 2.1 Agent（决策者）

Agent 决定：用哪个 LLM、有什么权限、系统提示词、最大循环次数。

```typescript
Agent.Info = {
  name: "build",
  mode: "primary" | "subagent",
  permission: Permission.Ruleset,     // 权限规则（不是工具列表！）
  model: { providerID, modelID },     // 使用的 LLM
  prompt: "...",                       // 系统提示词
  steps: 10,                           // 最大循环次数
  temperature: 0.5,
}
```

**内置 Agent**：

| Agent | 模式 | 权限特点 |
|-------|------|---------|
| build | primary | 全权限，默认 Agent |
| plan | primary | 禁用 edit 工具 |
| general | subagent | 通用子 Agent |
| explore | subagent | 只读+搜索，禁用 edit/write |
| compaction | primary(隐藏) | 禁用所有工具，压缩摘要用 |
| title | primary(隐藏) | 禁用所有工具，生成标题用 |

### 2.2 Provider / Model（LLM 提供商）

```typescript
Provider.Info = {
  id: "anthropic",
  name: "Anthropic",
  key: "sk-xxx",
  models: { "claude-sonnet-4": Model, ... }
}

Model = {
  id: "claude-sonnet-4-20250514",
  providerID: "anthropic",
  capabilities: { toolcall: true, reasoning: true, attachment: true, ... },
  cost: { input: 3, output: 15 },              // 每百万 token 价格
  limit: { context: 200000, output: 64000 },   // 上下文/输出限制
}
```

支持的 Provider：anthropic、openai、azure、google、vertex、bedrock、gitlab、github-copilot、openrouter、ollama 等 20+。

### 2.3 Tool（执行者）

Agent 不直接包含工具列表，通过 permission 控制哪些工具能用：
- build: `{ "*": "allow" }` → 所有工具
- plan: `{ "edit": "deny" }` → 禁用 edit
- explore: `{ "edit": "deny", "write": "deny" }` → 只读

**LLM 根据工具描述决定调用哪个工具。**

### 2.4 三者关系图

```
        ┌──────────┐
        │  Agent   │
        │ (决策者)  │
        └────┬─────┘
             │ 决定
    ┌────────┼────────┐
    ▼        ▼        ▼
permission  model   prompt
 (权限)    (LLM)   (提示词)
    │        │
    ▼        ▼
┌────────────────────┐
│  resolveTools()    │
│  permission 过滤    │
│  model 决定 schema  │
└────────┬───────────┘
         ▼
┌────────────────────┐
│ AI SDK streamText  │
│ LLM 决定调哪个工具  │
└────────┬───────────┘
         ▼
    ┌──────────┐
    │   Tool   │
    │ (执行者)  │
    └──────────┘
```

---

## 三、核心调用流程

### 3.1 主 Agent 流程

```
用户发消息
    ↓
prompt() → createUserMessage() → 保存到数据库
    ↓
runLoop() → while true 循环
    │
    ├─ agents.get(lastUser.agent)  → 获取 Agent 配置
    ├─ getModel(agent.model)       → 获取 LLM 模型
    ├─ resolveTools()              → 获取工具列表（转成 AI SDK 格式）
    ├─ handle.process()            → AI SDK 调用 LLM
    │   └─ llm.stream() → fullStream → handleEvent() 处理事件
    │
    ├─ compaction.isOverflow()     → 检查上下文是否超限
    ├─ compaction.create()         → 生成摘要（如需要）
    ├─ compaction.prune()          → 剪枝旧 tool 输出（后台异步）
    │
    └─ 判断结果：continue / stop / compact
```

### 3.2 子 Agent 流程（TaskTool）

```
主 Agent 的 LLM 决定调用 task 工具
    ↓
TaskTool.execute({ subagent_type: "explore", prompt: "帮我找..." })
    ↓
Agent.get("explore")           → 获取子 Agent 配置
Session.create({ parentID })   → 创建子会话
SessionPrompt.prompt({         → 递归！又走一遍 prompt 流程
  sessionID: 子会话ID,
  agent: "explore",
  tools: { todowrite: false, task: false },  // 子 Agent 不能再开子
})
    ↓
返回结果给主 Agent
```

### 3.3 Assistant 消息每轮新建

每次 while 循环都创建新的 assistantMessage：
```
循环1：assistantMessage1 → AI 说"让我看看" → 返回 continue
循环2：assistantMessage2 → AI 调用工具拿到结果 → 返回 stop
```

---

## 四、工具系统

### 4.1 工具三层架构

1. **定义层**（`tool/read.ts` 等）：定义 description、parameters、execute
2. **注册层**（`tool/registry.ts`）：统一管理，支持动态发现
3. **包装层**（`session/prompt.ts`）：在 execute 外包装 Plugin 扩展点

### 4.2 工具来源

| 来源 | 说明 |
|------|------|
| 内置工具 | bash, read, edit, glob, grep, task, todo, write, fetch, skill, patch 等 |
| 自定义工具 | `{cwd}/tool/*.{js,ts}` 目录 |
| 插件工具 | `plugin.list() → p.tool` |
| MCP 工具 | `mcp.tools()` 外部工具 |

### 4.3 resolveTools

把 OpenCode 工具格式转成 AI SDK 格式：

```typescript
for (const item of registry.tools(model, agent)) {
  tools[item.id] = tool({
    id: item.id,
    description: item.description,
    inputSchema: jsonSchema(schema),
    execute(args, options) {
      const ctx = context(args, options)  // 创建执行上下文
      yield* plugin.trigger("tool.execute.before", ...)
      const result = yield* item.execute(args, ctx)  // 原工具执行
      yield* plugin.trigger("tool.execute.after", ...)
      return output
    }
  })
}
```

### 4.4 BashTool 核心流程

```
execute(params, ctx)
    ├─ parse(command) → tree-sitter 解析成 AST
    ├─ collect(root) → 遍历 AST，收集要访问的目录和命令
    ├─ ask(ctx, scan) → ctx.ask() 请求权限
    └─ run() → 子进程执行命令
```

### 4.5 EditTool 核心流程

9 种 Replacer 链式尝试（精确→模糊）：
1. SimpleReplacer（精确匹配）
2. LineTrimmedReplacer（去行尾空格）
3. BlockAnchorReplacer（首尾行锚点）
4. WhitespaceNormalizedReplacer
5. IndentationFlexibleReplacer
6. EscapeNormalizedReplacer
7. TrimmedBoundaryReplacer
8. ContextAwareReplacer
9. MultiOccurrenceReplacer

---

## 五、权限系统

### 5.1 三种 Action

| Action | 含义 | Java 类比 |
|--------|------|-----------|
| allow | 直接通过 | Permit |
| deny | 直接拒绝 | Deny |
| ask | 弹窗询问用户 | ConsentDialog |

### 5.2 evaluate() 匹配算法

- `findLast()` 从后往前找最后一个匹配的规则（后面的覆盖前面的）
- 默认 action 是 `"ask"`

### 5.3 权限请求流程

```
ctx.ask({ permission, patterns })
    ↓
evaluate() 遍历 patterns 匹配规则
    ├─ 全 allow → 直接通过（不弹窗）
    └─ 有 ask → Deferred.make() + Bus.publish(Event.Asked) + Deferred.await()
                    ↓
                 前端弹窗 → 用户点击
                    ↓
              permission.reply() → Deferred.succeed/fail → 唤醒
```

### 5.4 Agent 权限配置（三层叠加）

```
defaults（默认规则）
    ↓ merge
Agent 配置（plan 禁 edit 等）
    ↓ merge
用户配置（opencode.json）
```

### 5.5 build Agent 默认规则

```typescript
{ "*": "allow" }                    // 大部分默认 allow
external_directory: { "*": "ask" }  // 访问项目外目录 ask
read: { "*.env": "ask" }            // .env 文件 ask
```

---

## 六、事件系统

### 6.1 Bus（事件总线）

发布-订阅模式，后端和前端通信的核心。

### 6.2 Deferred（延迟结果）

类似 Java 的 `CompletableFuture`：
- `Deferred.make()` → 创建
- `Deferred.await()` → 阻塞等待
- `Deferred.succeed()` → 成功唤醒
- `Deferred.fail()` → 失败唤醒

### 6.3 AI SDK fullStream 事件

| 事件 | 触发时机 | 数据 |
|------|---------|------|
| text-delta | 输出文本增量 | `text` |
| tool-input-start | 工具参数开始 | `id`, `toolName` |
| tool-input-delta | 工具参数增量 | `id`, `delta` |
| tool-call | 触发工具调用 | `toolCallId`, `toolName`, `input` |
| tool-result | 工具执行完成 | `toolCallId`, `output` |
| finish | 全部完成 | 无 |

### 6.4 后端→前端通信

```
AI SDK fullStream → handleEvent() → Bus.publish() → SSE /event
                                                      ↓
前端 global-sdk.tsx → EventSource 接收 → event-reducer.ts 更新 UI
```

---

## 七、上下文压缩

### 7.1 compaction.create（生成摘要）

触发：`isOverflow()` = 当前 token >= (限制 - 预留空间)

流程：找到用户消息 → 创建空 assistant 消息 → LLM 生成 summary → 返回 continue

### 7.2 compaction.prune（剪枝旧输出）

从最新消息往前遍历，保留最近 2 轮 tool 输出，标记更早的为 compacted。

### 7.3 isOverflow 实现

```typescript
return tokens.total >= (context - 20000)  // 预留 20000 token
```

---

## 八、Plugin 系统

### 8.1 本质

事件总线模式（不是 AOP）：
- 切入点硬编码在业务代码里，手动 `trigger` 触发
- 一个切入点可以挂多个插件

### 8.2 核心概念

| 概念 | 说明 |
|------|------|
| Plugin | 返回 hooks 对象的函数 |
| Hooks | `{ "扩展点名": fn }` 对象 |
| hooks 数组 | 存所有 Plugin 返回的 hooks |
| trigger | 遍历 hooks 数组，找对应 key 执行 |

### 8.3 常用扩展点

| 扩展点 | 时机 |
|--------|------|
| tool.execute.before | 工具执行前 |
| tool.execute.after | 工具执行后 |
| tool.definition | 工具定义时 |
| experimental.chat.messages.transform | 消息转换时 |
| event | Bus 事件 |

### 8.4 完整链路

```
1. 定义：Plugin 函数返回 { "扩展点名": fn }
2. 注册：INTERNAL_PLUGINS 数组
3. 初始化：启动时调用 plugin(input)，返回 hooks 存入数组
4. 触发：业务代码调用 plugin.trigger("扩展点名", input, output)
   → 遍历 hooks 数组，找对应 key 执行
   → 返回（可能被修改的）output
```

### 8.5 插件示例（HelloPlugin）

```typescript
export const HelloPlugin: Plugin = async ({ client }) => {
  return {
    "tool.execute.before": async (input, output) => {
      console.log(`工具即将执行: ${input.tool}`)
    },
    "tool.execute.after": async (input, output) => {
      console.log(`工具执行完成: ${input.tool}`)
    },
  }
}
```

---

## 九、MessageV2 数据结构

### 9.1 User 消息

```typescript
{ id, sessionID, role: "user", time, tools, format, summary, agent, model, system }
```

### 9.2 Assistant 消息

```typescript
{ id, sessionID, role: "assistant", parentID, time, mode, agent,
  finish: "stop" | "tool-calls" | "error",
  tokens: { input, output, reasoning, cache },
  parts: [TextPart, ReasoningPart, ToolPart, StepStartPart, StepFinishPart, ...] }
```

### 9.3 Part 类型

| 类型 | 作用 |
|------|------|
| TextPart | 普通文本 |
| ReasoningPart | AI 思考过程 |
| ToolPart | 工具调用（pending→running→completed/error） |
| ToolDeltaPart | 工具参数流式（GUI 用） |
| StepStartPart / StepFinishPart | 循环步骤 |
| CompactionPart | 压缩标记 |
| RetryPart | 重试记录 |

---

## 十、Java 对照表

| AI Agent 概念 | Java 类比 | 关键差异 |
|--------------|-----------|---------|
| ReAct 循环 | 工作流引擎状态机 | LLM 决策不确定 |
| 工具调用 | SPI + 策略模式 | 工具需自然语言描述 |
| Plugin 扩展点 | AOP 切面 | Plugin 是事件总线，手动 trigger |
| Deferred | CompletableFuture | Effect 框架实现 |
| Bus 事件总线 | Spring Event | SSE 推送到前端 |
| 权限系统 | Spring Security | 三层叠加 + Deferred 阻塞等待 |
| 上下文压缩 | 缓存淘汰策略 | LLM 生成摘要 + 剪枝 |
| ToolRegistry | Spring Bean 容器 | 工具需描述供 LLM 理解 |
| resolveTools | 适配器模式 | 格式转换 + Plugin 包装 |
| Provider | DataSource 工厂 | 6步初始化 + Brand Type |
| custom() | BeanPostProcessor | 每个 Provider 的后处理 |
| resolveSDK | DataSource.getConnection() | Hash 缓存 + 动态 npm install |
| ProviderTransform | DatabaseDialect | 不同 LLM 的消息格式适配 |

---

## 十一、关键代码速查

| 模块 | 文件 | 关键行 |
|------|------|--------|
| Agent 配置 | `agent/agent.ts` | 27-53 (Info), 115-242 (内置 Agent) |
| LLM 调用 | `session/llm.ts` | 261 (streamText) |
| 主循环 | `session/prompt.ts` | 1356 (prompt), 1388 (runLoop), 1472 (获取 Agent) |
| 事件处理 | `session/processor.ts` | 129 (handleEvent) |
| 工具注册 | `tool/registry.ts` | 139-156 (内置), 191-238 (tools 方法) |
| 工具包装 | `session/prompt.ts` | 389-479 (resolveTools) |
| 权限系统 | `permission/index.ts` | 168 (ask), 205 (reply), 280 (trigger) |
| 权限匹配 | `permission/evaluate.ts` | findLast 匹配 |
| 事件总线 | `bus/index.ts` | 83 (publish), 149 (subscribe) |
| 上下文压缩 | `session/compaction.ts` | 93 (prune), 141 (create) |
| Plugin | `plugin/index.ts` | 71 (列表), 170 (初始化), 280 (trigger) |
| 子 Agent | `tool/task.ts` | 28 (TaskTool), 130 (递归调用 prompt) |
| Provider | `provider/provider.ts` | 822 (Model 定义), 893 (Provider 定义) |
| Provider 初始化 | `provider/provider.ts` | 1014-1339 (layer 6步) |
| Provider 定制 | `provider/provider.ts` | 175-820 (custom 函数) |
| SDK 解析 | `provider/provider.ts` | 1344-1479 (resolveSDK) |
| getLanguage | `provider/provider.ts` | 1503-1544 (Model→LanguageModelV3) |
| 消息适配 | `provider/transform.ts` | 278 (message), 364 (variants), 746 (options) |
| Provider 认证 | `provider/auth.ts` | 165 (authorize), 192 (callback) |
| 类型定义 | `provider/schema.ts` | 6 (ProviderID), 29 (ModelID) |
| 消息结构 | `session/message-v2.ts` | 371 (User), 420 (Assistant) |
| SSE 端点 | `server/routes/event.ts` | 92 (subscribeAll) |
| 前端 SDK | `app/src/context/global-sdk.tsx` | 139 (SSE 连接) |

---

## 十二、Provider 模块（LLM 接入层）

### 12.1 整体定位

Provider 是 Agent 和 LLM 之间的桥梁。Agent 说"我要用 claude-sonnet-4"，Provider 负责：找到模型 → 创建 SDK 客户端 → 返回 AI SDK 能用的 LanguageModelV3 对象。

**Java 类比**：DataSource 接口，背后可以是 MySQL/PostgreSQL/Oracle。

### 12.2 三层类型体系

```
ProviderID (品牌标识) → Info (Provider 全量配置) → Model (一个具体模型)
```

| 类型 | 含义 | Java 类比 |
|------|------|-----------|
| `ProviderID` | Effect Schema Brand 品牌字符串 | 枚举 |
| `Info` | Provider 全量信息：名称、Key、env、模型列表 | DataSource 配置 Bean |
| `Model` | 模型元数据：能力、费用、上下文、变体 | Connection 配置 |

ProviderID 和 ModelID 用 **Brand Type**（编译时类型安全，运行时就是字符串）：
```typescript
const providerIdSchema = Schema.String.pipe(Schema.brand("ProviderID"))
// 不能把 ProviderID 传给需要 ModelID 的函数
```

### 12.3 初始化流程（6 步）

```
1. ModelsDev.get()         → 加载模型数据库（所有已知 Provider+Model 元数据）
2. config 合并             → opencode.json 中的用户自定义 Provider
3. env 检测                → 环境变量中的 API Key（ANTHROPIC_API_KEY 等）
4. auth 读取               → 存储中的 OAuth/API Key
5. custom() 后处理          → 每个 Provider 的定制化逻辑
6. filter                  → 过滤 disabled/alpha/deprecated
```

**优先级链**：database → config → env → auth → custom → filter，后者覆盖前者。
**Java 类比**：Spring PropertySource 优先级链。

### 12.4 custom() 函数——Provider 后处理器

每个 Provider 可定义特殊行为，返回：
```typescript
{
  autoload: boolean,           // 无 Key 时是否还显示
  getModel?: CustomModelLoader, // 自定义模型创建逻辑
  vars?: CustomVarsLoader,     // URL 变量替换（${GOOGLE_VERTEX_PROJECT}）
  options?: Record<string, any>, // 传给 SDK 的额外选项
  discoverModels?: CustomDiscoverModels  // 动态发现模型
}
```

典型例子：
- **anthropic**：添加 `anthropic-beta` 请求头（扩展思考、工具流式）
- **openai**：用 `sdk.responses()` 而非 `sdk.languageModel()`（OpenAI Responses API）
- **amazon-bedrock**：根据 region 自动加前缀（`us.claude-sonnet-4`），处理 AWS 凭证链
- **gitlab**：运行时动态发现工作流模型（`discoverModels`）
- **azure**：根据配置选择 `sdk.responses()` 或 `sdk.chat()`

**Java 类比**：BeanPostProcessor，每个供应商有自己的后处理器。

### 12.5 getLanguage()——核心调用路径

```
Agent 要用模型 → Provider.getLanguage(model)
  → resolveSDK(model) 创建 SDK 客户端
    → BUNDLED_PROVIDERS[api.npm] 内置？或 Npm.add() 动态安装？
  → modelLoaders[providerID] 存在？用自定义 getModel()
    → 否则用 sdk.languageModel(model.api.id)
  → 缓存到 Map<string, LanguageModelV3>
```

### 12.6 resolveSDK 关键逻辑

1. 合并 options（baseURL、apiKey、headers）
2. URL 中的 `${VAR}` 变量替换（varsLoaders + 环境变量）
3. Hash 缓存 key（同 providerID + npm + options 复用 SDK 实例）
4. 包装自定义 fetch：超时控制、SSE 超时检测（`wrapSSE`）
5. 优先 BUNDLED_PROVIDERS（编译时打包的 20+ SDK），否则动态 `npm install + import`

### 12.7 ProviderTransform——消息适配层

处理不同 LLM 的"怪癖"（Dialect 模式）：

| 函数 | 作用 |
|------|------|
| `normalizeMessages()` | Anthropic 不接受空 content；Claude toolCallId 只能含字母数字下划线；Mistral toolId 限9字符且 tool 后不能紧跟 user |
| `applyCaching()` | 对 system 和最后2条消息加缓存标记（Anthropic/OpenRouter/Bedrock 各有不同字段名） |
| `unsupportedParts()` | 模型不支持图片/PDF 时，把附件转成文本提示 |
| `variants()` | 推理模型的思考级别配置（high/max/low），每个 Provider 参数格式不同 |
| `temperature()` | 不同模型默认温度（qwen: 0.55, gemini: 1.0, claude: undefined） |
| `options()` | 每个 Provider 特殊请求选项（openai: store=false, openrouter: usage.include=true） |
| `schema()` | Gemini 不接受 integer 枚举，转成 string |
| `providerOptions()` | 把选项映射到正确的 SDK 命名空间（azure 需同时设 openai 和 azure） |

**Java 类比**：DatabaseDialect，不同数据库的 SQL 方言翻译层。

### 12.8 ProviderAuth——认证流程

两种认证方式：
- **API Key**：直接存 key，由 custom() 或 env 填入
- **OAuth**：`authorize()` → 浏览器授权 → `callback()` 拿到 access_token/refresh_token

OAuth 通过 Plugin 的 `auth` 钩子扩展（如 GitLab 的 OAuth 流程）。

### 12.9 BUNDLED_PROVIDERS

编译时打包的 20+ SDK 映射表：

```typescript
BUNDLED_PROVIDERS = {
  "@ai-sdk/anthropic": createAnthropic,
  "@ai-sdk/openai": createOpenAI,
  "@ai-sdk/amazon-bedrock": createAmazonBedrock,
  // ... 20+ 个
}
```

如果模型的 `api.npm` 不在此表中，resolveSDK 会动态 `npm install` + `import`。
