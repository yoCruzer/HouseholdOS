# PR5-IR-Closure-01 — 修复与验收合同

基于独立 Review：`faae13d93a83694a77da3d962423de2193f0fe88`。原报告位于 `ReviewSource/REVIEW.zh-CN.md`。
IR编号对应本次外部Review，不要与Codex此前内部R1～R6混淆。

只要求最小验证工程承担下面的行为。结论来源必须是当前源码和可复现测试；测试红→绿不能靠复写错误期望。

## IR-01 — incarnation 与父归属的准入先于字段合并 [P1]

### 失败场景
A/B原来有Item X、生命周期A；B离线修改分类；A删除后明确重新添加为生命周期B。B可能只收到B的最终状态，没有收到中间tombstone。当前ThreeWayMerge能把两代记录的不同字段合并，并保留本地旧incarnation。

### 最小修复约束
- 同一UUID不是同一生命周期的充分条件。对当前record与parent的incarnation/归属做准入，再决定是否可以字段merge。
- 不能只给ThreeWayMerge增加返回nil就认为完成：检查apply、projection、outbox和子项可见/发送路径。跨代冲突必须保留可恢复内容，不能产生混合生命周期的新wire或继续发送旧代内容覆盖新代。
- 不把墙钟或不同设备的本地revision数字当成全局因果顺序。保留必要局部revision不变量，但明确它不能证明跨代新旧。
- lifecycle/re-add及父归属信息作为一致语义组处理；既有合法Draft→Item确认不因加guard而被破坏。不要给正常typed字段套通用分布式合并框架。
- 检查WardrobeProfile：不能只按owner UUID把旧profile留到新incarnation；不需同步完整Profile体系，但现有两字段的投影应无幽灵归属。

### 回归要求
- 用同一真实SyncCore/ThreeWayMerge：B错过中间删除，只收到新代；不同字段改动不能跨代自动拼接。
- 旧子项先到/晚到，新子项先到/晚到：不归错父代；投影、待发送状态重启后仍一致。
- 相同incarnation下正常不同字段merge仍工作；同字段冲突内容留存。
- 两端正常确认同一Draft仍归一个逻辑Item；不因此次修复制造duplicate/意外阻塞。

可采用安全的显式冲突或明确接纳新代并保留旧候选，不要求新增产品冲突UI；但不能把“都暂停、永不继续”作为正常无冲突路径的修复。

## IR-02 — 已知前代 tombstone 重放不能撤销明确 re-add [P1]

### 失败场景
本地已应用D（ancestor=D），用户生成合法新R（new incarnation，replacesDeletion=D.operationID），R尚未上传；fetch重放同一D。当前remote.deleted分支先于ancestor相等判定，清除R的delivery并隐藏Item。

### 最小修复约束
- 识别相同已知前代D的重放与真正后续/并发删除，不采用无条件delete-wins或无条件re-add-wins。
- 同一D重放不能撤销R、清除R的outbox或错误改变当前projection。可以刷新安全的远端依据，但不能让旧ACK/token回退新认知。
- 必须保留D与R的操作关系；不要靠“所有deleted都忽略”或将所有冲突自动resolved修复。

### 回归要求
D→合法R→重放D→重启→再重放D；R仍可见、pending保持幂等，无多余新意图。
另外覆盖：R已在途、D重复回调；真正新一代的删除仍能生效；普通旧upsert不能越过tombstone；已解决/未解决冲突备份后状态与IR-05一致。

IR-01/02是一组边界但不是同一个反例，必须分别有可失败断言。

## IR-03 — 显式 current representation，而不是 max(revision) [P1]

### 失败场景
两端从同一revision 1分别创建A2/B2；新wire当前指向B2，历史A2仍在。MediaTransfers.current按max(revision)可能选A2；备份同样猜测当前版本。

### 最小修复约束
- 单一明确当前引用（wire.media.representationID或一致持久sidecar指针），所有投影/传输ticket/ACK/接收/备份选择使用该引用。不要再新建相互竞争的多份current真源。
- representation ID为具体不可变字节表示；revision/hash验证描述，不决定哪个表示被当前选中。历史表示保留但不默认生效。
- 当前引用不存在/版本或hash不符时明确unavailable/invariant，不静默回退另一历史图。
- 迟到结果可以记为旧表示副本已送达，但不能覆盖当前图/回写当前保护成功。并发当前选择的准入复用IR-01逻辑，不自建另一套冲突规则。
- 既有候选store若缺新指针，只能从明确wire/实际附件引用作可校验的兼容迁移；不得按最高revision猜历史状态。真实V1旧媒体保持原件，不臆造Photos引用。

### 回归要求
- A2/B2相同revision、不同ID；互换插入和枚举/到达顺序，当前选择相同。
- 保留一个revision更高但未被选中的历史表示，也不能抢占当前。
- 旧upload ACK、旧download晚到；重启后仍不影响当前图。
- export→restore后当前引用、可用preview、原件描述与源snapshot一致，旧表示仍留存。
- 相同representation ID内容被改变应拒绝；缺当前表示不能下载/上传错误历史图。

## IR-04 — 有界、可前进、重复准备安全的 batch [P1]

### 失败场景
先取100在途，再次nextBatch先加入这100又继续append，`count == 100`追加后判断无法拦101+；Live预取、send、delegate可能在ACK前连续调用。limitExceeded无缩批/持久阻塞路径。

### 最小修复约束
- 100是当前harness应用预算，不是声称CloudKit服务固定上限。按真实SDK响应处理服务限制。
- 选择前计算剩余容量，在途和新pending都受限；若旧checkpoint里在途已超限，也分批返回并保留未选意图，不能删掉overflow。
- 同一实体维持已定义的一次在途版本；重复准备对未ACK集合不无限膨胀。排序/选择应稳定可解释，部分ACK后剩余记录能前进，不能永久饥饿。
- 分离纯查看与登记发送的副作用，或证明多层调用幂等；真实delegate和测试共用选批实现。
- limitExceeded：有限缩批或明确可恢复阻塞；一个实体本身过大时保留outbox/内容并报告，不无界重送不变大批次。错误必须绑定实际scope/对应发送，旧错误不能影响新会话。
- 不用提高上限、丢记录、一次全库发送或无限timer重试来修复。

### 回归要求
99/100/101/300条、连续准备无ACK、100在途重启、旧超额在途checkpoint、部分ACK、重复ACK、逐批最终清空、limitExceeded到单条仍失败。
在源码实际batch provider/错误reducer边界做确定性回归；不发真实大量CloudKit请求。

## IR-05 — 冲突状态与 scope 独立，restore不重新激活历史 [P2]

### 失败场景
旧实现用`resolved/<scope>`承载解决状态，restore却给全部ConflictCandidate重新写scope，历史resolved变active并阻塞发送。

### 最小修复约束
- 用明确active/resolved状态或同等严格表示；scope只表示归属/隔离，恢复/绑定不能改冲突解决语义。
- 保留候选内容与解决状态。不得删除所有冲突、恢复后全resolved或全active。
- 为已有候选store/备份里的旧`resolved/`形态提供明确兼容解释，不能让历史样本因新增字段被清掉；仅涉及验证候选，不改正式V1。
- re-add不是“所有冲突都已经解决”的通用理由；只能解决与实际明确操作有关的候选。

### 回归要求
通过真实业务路径得到一个resolved历史冲突，另一个保持active；export→restore→cloud admission→重启后只active阻塞，对应local/remote候选均保留。
复用IR-02重放用例，防止修复resolved状态后旧删除又撤回re-add。

## E-01 — Preview失败后的录入可恢复，而不是只有staging字节

### 本轮明确要补的最小能力
有效原件已安全落盘而preview失败时，选择以下最小方案之一：
A. 提交可解释的降级Draft + 原件引用 + 同事务outbox，preview单独待补；或
B. 保留带稳定操作身份的prepared记录，通过已有recovery入口可真正恢复/继续建档。

任选其一，复用现有journal和App/CLI最小入口，不做新的恢复Dashboard或通用任务引擎。不能只列出磁盘文件并声称闭环。

### 不变量
- 同一准备操作重试/恢复沿用稳定draft/media/profile或等效幂等键，不生成第二次录入。
- 未提交与已提交但整理失败区分；不谎称原图/preview完整，也不把唯一原件当可清理缓存。
- 确实没有写成原件、或原件已损坏，不能凭journal制造成功Draft；保留可诊断状态，不阻塞其它可恢复记录。
- recovery第二次遇到preview/DB错误仍保留恢复入口；不得新造空preview当健康图片绕过约束。
- 新增journal字段/候选字段要有明确旧测试数据兼容策略，不能改旧源fixture或丢未知内容。

### 回归要求
有效JPEG/HEIC→原件落盘→preview失败→进程结束/独立重开→从实际入口恢复→确认Item→再次恢复/重启。
断言：原件字节/hash未变；只有一个logical Draft/Item、一份正确媒体与profile；outbox完整且重试幂等；preview就绪状态真实。
另测恢复再次失败、缺失/损坏原件、提交后整理中断。程序化复用少量素材，不要求Owner拍照。仅运行抛错单测不声称证明所有SIGKILL/断电窗口。

## E-02 — 真实V1迁移到首次sync的最小桥接

### 本轮明确要补的最小能力
在隔离prototype建立一个可调用且幂等的legacy首次引导入口，至少把**一条由原始V1模型生成的既有Item**经clone迁移、显式库归属映射后送入同一outbox/codec，并在空白隔离接收端正确出现。

不用实现生产全字段/全量历史同步。选择真实旧模型创建的小fixture，包含旧媒体并核对其原件和关联未受损；本轮不必上传原图。若选用静态JPEG样本，用旧模型正常生成新的合成fixture；不能拿候选Schema冒充V1，也不能改掉已保存的原fixture来迎合迁移。

### 不变量
- 原V1的householdID、Item/Draft ID与新local libraryID映射显式、可持久回查；保留源库不变；不能把两个独立旧库因默认household UUID相同悄悄合并。
- 引导调用两次、跨进程重启、失败后重试，不重复制造本地实体/上传意图/目标逻辑Item；使用稳定operation或durable引导回执，不每次随机生成新动作来“防重”。
- legacy映射和outbox保持同事务；只为scope内明确获准映射的对象建意图。实际发送前仍需metadata fetch/apply barrier。
- 云端已有同UUID/tombstone时，不由旧库引导覆盖最新删除；复用正常restore/admission与IR-01/02规则，不开绕过gate的上传捷径。
- 不删除旧原图、不猜Photos引用；未知分类、缺值等保留或明确限定fixture映射，不静默虚构产品属性。
- target收到的字段/身份与本次映射承诺一致。对未覆盖的生产字段明确列出，禁止宣称“全部老用户历史同步已完成”。

### 回归要求
真实旧源→完整clone→Candidate迁移→首次引导→重启→重复引导→完成模拟服务fetch gate→发送→空白端apply。
至少断言旧Item稳定身份/名称、目标恰一件、源原件hash/旧引用不变、未发送前的barrier、重复/失败无phantom。
增加同ID远端tombstone及两个独立legacy库默认household相同的反例。桥接使用真实本地SwiftData与共享sync代码；云服务可确定性替代，证据标LOCAL_PLATFORM+LOGIC，不标LIVE_SERVICE。

## 组合收尾：不靠互相独立的绿灯推出整体正确

小型组合场景必须由上面测试复用，避免新增庞大矩阵：
1. re-add→旧tombstone重放→新旧子项→重启：不跨代复活/混合，合法新意图不丢。
2. 相同revision两图→明确当前选择→备份恢复→旧ACK/download：当前图不漂移，历史不丢。
3. legacy首次引导→批次部分ACK→重启→再次引导：有限批次最终前进，不重复逻辑对象。
4. prepared原件恢复→确认→备份恢复：唯一原件/身份/outbox不丢；不写Photos。

不要求四个新test class或每条重新造App；允许以现有fixture/参数化用例覆盖，并建立清晰case→实际测试/证据映射。

## 门禁与证据表

| 项 | 完成条件 | 不接受的替代 |
| --- | --- | --- |
| IR-01/02 | 本地原生路径上双向生命周期反例通过，正常merge/confirm仍正常 | 只改纯函数而apply/projection仍错；所有情形一律暂停 |
| IR-03 | 显式当前表示贯穿传输/恢复，相同revision反例通过 | 按revision最大/文件最新时间推断 |
| IR-04 | 连续prepare/重启/partial/limit错误有界且可前进 | 增大上限、丢overflow、无限重试 |
| IR-05 | resolved与active恢复保真且只active阻塞 | 只检查冲突数量 |
| E-01 | 有效prepared原件真正能恢复成一次录入并重试安全 | 仅证明staging还有文件 |
| E-02 | 真实旧Item跨迁移、引导、空白端链路与幂等 | 迁移和新capture分别PASS后拼成旧库同步PASS |
| 最终候选 | 受影响证据覆盖最终代码，验证工程完整确定性集合/交付build通过 | 复用修复前51/51声称新版本已测 |

未取得的真实CloudKit/Photos/真机/最低版本runtime证据继续外部待验。它们既不是这轮逻辑修复的挡箭牌，也不能被这轮本地绿色结果替代。
