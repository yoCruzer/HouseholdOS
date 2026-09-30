# PR5-IR-Closure-02 — 跨模块交互验收合同

## 0. 问题不是“单测不够多”

本轮要求同一数据经过多个模块之后仍然正确：
`本地修改 → outbox/发送快照 → server条件版本 → ACK或fetch → 入站投影 → backup/restore → 重新准入`。
重点是数据交接时的身份、因果依据、提交点、重放及终态。目标不是实现通用分布式平台。

测试应尽可能沿现有 LocalChain/SyncCore/CloudCodec/CloudAdapter/BackupRestore/MediaTransfers 路径。
一个函数“返回成功”、一个列表“变空”、一张图“仍在磁盘”，都不足以单独证明跨模块流程完成。

## 1. 两类验收必须同时有

**Safety／安全性：**scope与生命周期不串、不静默覆盖新编辑、不丢唯一字节、不误用旧备份状态、
不把无发送证据的输入当ACK、不过早推进checkpoint、不因重试生成重复业务事实。

**Progress／有条件可完成性：**只针对明确的成功条件——同一合法scope、必要fetch/apply已完成、
本地存储可用、无未解决真实冲突、无新用户修改/外部删除、测试服务按约定成功交付。
在此条件下，当前合法意图应在有限步骤内完成并在重启后保持；不能永远返回同一条件写冲突，
不能把自己的连续编辑变成人工冲突，不能只剩永远不可发送且无明确原因/出口的pending。

此要求不是声称真实云会在固定秒数内完成。对于OFF、未授权、quota、未知parent、真实冲突，
允许有原因的等待/阻塞；测试必须知道为什么不是成功，不能强迫清空队列。

## 2. 交接责任表（必须能在实现中定位，不要求全部拆成新实体）

| 内容 | 权威/证据 | 交接后要满足 |
| --- | --- | --- |
| 最新本地业务状态 | 已提交的业务记录与对应意图 | 接收旧消息不能回退用户当前有效选择 |
| 当前服务端写入依据 | 验证scope的服务端记录/system fields；适用的观察上下文 | 业务值不覆盖，也可能需要更新下一次条件写依据；不能凭recordID或本地revision伪造依据 |
| 自己曾发送的operation | durable发送快照、send-time base或同等持久来源证明 | ACK与fetch自回传走兼容的退休/基准更新规则；payload与作用域均须匹配 |
| 待完成工作 | authoritative outbox及可重建engine调度副本 | ready、blocked和终态可解释；下一批为空不等于全同步完成 |
| 明确替代的旧意图 | 新的持久用户意图与前代关系 | 可退休/归档，不能伪装ACK；必要迟到回调信息仍安全处理 |
| 恢复后的运行时 | 新session/epoch + 保留的业务来源/未解决候选 | 清旧transport状态但不清继续同步所需的用户因果信息；重新获取条件基准 |
| 当前媒体 | 明确representation ID与descriptor | 不按最大revision猜图；迟到结果不能覆盖当前引用 |

## 3. R2-01：re-add恢复后的条件写闭环

最小路径：已知D → 明确re-add R（新incarnation、replacesDeletion=D）→ R未ACK时备份恢复
→ 清旧session/systemFields → 按新scope准入 → fetch当前D → 条件保存R → ACK → 重启。

必须同时成立：
- D重放不撤销R、不生成无关人工冲突、不遗失有效意图。
- 恢复后重新取得足够的、经scope及观察上下文验证的服务端基准，使下一次条件写真正被测试服务接受。
- 拿到基准、更新ancestor/receipt、退休意图与推进checkpoint的事务边界明确，失败可重放。
- 不是仅断言systemFields非nil或nextBatch含R；必须继续检查实际生成的发送请求与服务端条件相符。
- 较晚已观察的服务端新incarnation/新删除不能被迟到旧D的基准覆盖。
- 不采用无条件allKeys/changedKeys、不从旧备份直接复用tag、不把本地revision当远端全局时钟。

官方依据S1/S2：条件写比较change tag；成功发送后的system fields用于后续写。见SOURCE_MANIFEST。

## 4. R2-02：自己的fetch回传与后续编辑不能误冲突

有/无旧ancestor两种：本地7 → 持久发送7 → 本地同字段编辑为8 → 服务器保存7但ACK未达
→ fetch返回准确7 → 继续发送8 → 服务确认8 → 重开。

必须同时成立：
- 业务值仍是8，无伪造的并发冲突；发送7的退休不能吞8。
- 根据充分的持久来源证明识别自回传，接收它作为适用的服务端基准，再发送8。
- ACK和fetch处理共享一致的状态语义；允许窄重构，不要求特定类名或必须单函数。
- 完成后重复合法回传、迟到ACK7不能回退8/其基准；拒绝scope/epoch不符的旧回调。
- 不是operationID相同就信任：还验证实体、内容保真、scope、生命周期及适用的发送/观察来源。
- 真正另一端、不同operation改同字段仍保留可恢复冲突；缺少充分来源时不可假装自回传。
- 未知字段/版本不因为解码后“看起来相等”被丢失或不安全重写。

不要先删唯一send-base/snapshot，再发现后续merge缺少因果依据。必要的新回执必须持久且可重放。

## 5. R2-03：旧子意图需要可解释终态

P下旧子C1待发（分别覆盖从未发/已在途）→ 父删除D → 明确re-add R → 用户明确把该子项
关联到新parentIncarnation，形成C2 → R/C2确认 → 重启。

必须同时成立：
- C1不能再作为新父代的子项发送；C2/R能正常完成。
- 完成时，C1不能永远作为无出口活动pending；给出有根据的superseded/retired/history状态。
- 为保存历史仍可保留payload、关联和旧ticket，但“旧历史”不计为仍需上传的新工作，不谎称server ACK。
- 新的替代关系与旧项终态必须在可验证的本地事务中保存；崩溃不产生既丢新意图又隐藏旧意图的窗口。
- 未知parent待到达、真正未解决冲突、仍合法的独立操作不能一并退休。
- 旧C1迟到ACK/fetch后不得修改C2当前父代、业务值、条件基准或重新激活历史。
- backup/restore保留终态或可靠重建所需证明；不能重绑scope时把终态历史全激活。

允许现有表/窄回执表达终态，不要求本轮实现历史管理UI或通用队列库。记录选择依据与恢复规则。

## 6. 八类事件序列：覆盖而非海量组合

`SCENARIOS.json` 给出覆盖索引。默认采用八类小场景：三个原反例、真正冲突对照、
恢复+自回传组合、账号/OFF边界、媒体/冲突恢复回归、批次+混合确认的完成性。
它们不是八个Goal；一个参数化用例可覆盖多个。已有证据可复用的旧行为不另外堆同义测试。

仅对有合理因果顺序的事件做定向变化：ACK丢失/晚到/重复、fetch自回传、关键持久边界重开、
parent/child先后、完整generation恢复、OFF/epoch变化。不要生成因真实调度不可能发生的事件序列，
再为了让它绿而更改产品语义；拿不准就注明具体来源/许可的观察窗口，等待实际SDK补证。

少量固定fixtures/固定seed即可。不得新增依赖做大规模fuzzing、无界排列组合、通用状态机平台。
如果薄的scenario helper能减少重复，可放现有Tests目录；不写“读JSON→通用解释器”。

## 7. Fake应能拒绝错误，而不是给被测代码补答案

现有fake允许由调用者传expectedOperation，这可能绕过生成请求的真实基准缺失。
本轮的条件服务替身必须从**被测sender生成且持久基准参与构造的请求**取得所需条件，
不能测试代码单独把“正确server version”传进去让错误实现也成功。

最小fake职责：服务端持有不可由客户端改写的opaque版本；按固定scope/record执行条件判断；
save失败时不改服务状态；成功后版本变化；可配置保存成功但ACK丢失；fetch/冲突回执返回服务观察。
不通过operationID等于本地已知值就绕过所有条件比较；相同业务操作的幂等效果需由应用路径证明。

无需为离线fake伪造CloudKit私有内部对象：若本机SDK无法安全构造真实changeTag，
允许一个窄的测试transport-envelope/token seam，明确它只模拟条件服务。
但需配对验证真实CloudCodec/adapter使用持久化后重新读取的服务systemFields构造下一次请求；
不能仅在fake里修复、仅检查字段非nil，不能用KVC/private API制造假“真实CloudKit通过”。

至少一个负向控制：去掉/错用sender的版本依据应被条件服务拒绝。真实CloudKit时序继续LIVE_PENDING。

## 8. 每步断言及终态，不止最终测试数量

关键事件后检查（按场景相关性）：
- 当前scope/epoch、业务ID/incarnation/parentIncarnation、当前representation。
- 未丢失的最新本地选择、已观察服务端基准和send-time来源。
- ready/inflight/blocked/terminal操作及原因；未解决与已解决冲突状态。
- 对应媒体字节/引用存在性；恢复后完整generation；无Photos写入。

用预设fixture目标/明确预期来判定结果，不能直接用被测reducer本身计算expected。
成功型场景最终验证：目标语义与最后合法用户意图一致、条件写已接受、ACK/适用回传已确认、
无意外active conflict、无无法解释的pending、重开保持。历史行可以存在，不以“所有表都空”判成功。

有阻塞型对照：准确blocked原因及保留内容，不能报已同步；本轮不开发冲突UI。

终止条件：每个确定性fixture设有限事件/交付round上限，无sleep或真实网络等待。
上限依据fixture工作量设置，不当云SLA。若在允许成功的条件下重复调度仍无语义进展，
测试失败并导出最后事件轨迹；不能用随机delay、不断换operation UUID或清状态掩盖不收敛。

重开要重建真实ModelContainer/相关对象并从磁盘读取，不仅复用同一实例；
涉及commit与file journal的新增崩溃窗再用现有进程工具，其他小差异不重跑全部SIGKILL矩阵。

## 9. 诊断只加到必要的交接点

记录脱敏的：scenarioID/step、事件、scope/epoch alias、实体/operation alias、生命周期、
本地/远端基准alias、发送快照来源、队列状态及转换理由、commit结果、最终代码指纹。
重点解释为什么应用/忽略/阻塞/替代，不只输出计数。真实照片、账号、密钥或用户路径不进公开证据。
保持测试私有trace与现有summary；不因加诊断而新建生产遥测平台或大幅扩UI。

## 10. 最终验收

三项发现均有真实源码处置及原生定向回归；八类场景有适用证据映射；
本轮关联失败在最终候选闭环，不把历史绿色覆盖到失效断言。
安全性/可完成性分别给结论，条件服务模型边界清楚。
一次收尾完整确定性测试和必要构建覆盖最终代码；之后docs-only更新清楚标注。

允许结果：本轮本地整改完成、等待独立复核、真实平台证据继续pending。
不允许：仅nextBatch非空/空、systemFields非nil、原件还在、count正确，就声称整个流程完成；
不允许为了不再返工而宣称已穷尽全部跨模块错误。
