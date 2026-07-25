# Architecture

Status: PROVISIONALLY FROZEN
Version: 1.0

本文档定义起步技术方向。具体 Xcode 版本、最低部署版本和工程生成方式将在 F0 通过本机环境验证后记录。

## Platform Direction

- Native iOS app
- Swift
- SwiftUI
- SwiftData（若 F0/F1 环境验证无阻塞）
- Apple 原生框架优先
- Local-first storage

## Layering

建议目录和依赖方向：

```text
App
├── Application
├── Domain
├── Data
├── Features
├── DesignSystem
└── Support
```

### Domain

包含：

- 领域实体和值对象
- 领域服务
- Repository 协议
- 不变量和计算规则

不得依赖 SwiftUI View。

### Data

包含：

- SwiftData 模型/映射
- Repository 实现
- Media storage
- Export/backup adapters
- Migration

### Application

包含：

- Use Cases
- Stage 内原子操作
- Transaction boundaries
- Dependency assembly

### Features

按功能组织 SwiftUI：

- Capture
- Drafts
- Items
- Spaces
- Lifecycle
- Maintenance
- Settings

View 不直接维护跨实体不变量。

### DesignSystem

可复用 UI tokens 与组件。V1 只建立实际需要的最小集合。

## Core Architectural Rules

1. CaptureDraft 与 Item 存储边界独立。
2. 领域服务统一维护状态和位置快照。
3. 事件记录是历史事实来源。
4. 媒体文件与结构化数据分离，通过稳定标识关联。
5. Money 使用十进制值。
6. ApproximateDate 保留精度。
7. 所有可失败写入应避免产生半完成正式状态。
8. 洞察指标动态计算或使用可重建缓存。
9. 外部能力通过协议边界接入，但不得为未批准能力构建庞大框架。
10. 导出分享使用派生副本和隐私策略。

## Dependency Policy

- 初始阶段不引入第三方依赖。
- 新依赖必须记录：必要性、替代方案、隐私、许可证、维护风险和移除成本。
- Apple 原生 API 足够时不引入包装库。

## Concurrency

- 使用 Swift Concurrency。
- UI 状态在明确的主隔离域更新。
- Repository 和媒体写入需定义事务/串行边界。
- 不通过不安全共享可变状态实现批量录入。

## Error Handling

- 可恢复错误不得导致草稿或媒体丢失。
- 用户消息与诊断错误分离。
- 不记录敏感字段。
- 数据一致性错误应阻止提交并保留可恢复状态。

## Testing Boundaries

- Domain 规则优先纯单元测试。
- Repository 使用内存存储测试。
- 关键原子操作测试成功与回滚。
- UI 只测试高价值主流程。
