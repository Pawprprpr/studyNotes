你输入 → createUserMessage() → 创建消息
    ↓
runLoop() → while 循环
    ↓
resolveTools() → 准备工具列表
    ↓
handle.process() → 调用 LLM
    ↓
llm.stream() → AI SDK 发送请求
    ↓
LLM 返回 tool_call
    ↓
handleEvent("tool-call") → 处理工具调用
    ↓
handleEvent("tool-result") → 处理工具结果
    ↓
返回给 LLM
    ↓
LLM 生成最终回复
    ↓
loop 结束或继续
