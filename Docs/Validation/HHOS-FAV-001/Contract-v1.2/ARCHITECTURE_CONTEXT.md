# HouseholdOS — 语义边界与候选设计 v1.2

这是执行上下文，不是正式Foundation。固定产品目的：本地优先、拍照为主的家庭物品档案/查找/生命周期/成本复盘；衣物共用Item底座。iCloud可开关，媒体较多、原图重复空间、换机、恢复安全必须考虑。不是另做时尚社区，也不造通用资产平台。

## 1. 保留且不再重开讨论

Core Asset在代码继续称Item；Draft与正式Item分开；只填名称可建正式档案。typed Profile表达明确品类差异，不把全品类字段塞Item，也不依赖万能字典。Wardrobe作为验证域只需代表字段；Category/Tag/Profile不是同一概念。分类变更不默认毁掉Profile。

业务身份与Apple ID独立。事实与快照及派生指标分层；一次真实使用和同动作重试不能混淆。金额十进制、币种与unknown明确；日期精度不伪造。只做代表fixture，不预实现整套未来财务/时间/家庭模块。

## 2. 技术首选，不是待证明的“正确答案”

首选验证 Local SwiftData + durable Outbox + CKSyncEngine。Apple官方区分托管同步与需要更多应用控制的方案；这个选择是为本产品开关/媒体调度/恢复规则服务，不因为某模型能写复杂代码就必须自管。[A3]

本地是工作副本，不是永远胜过远端。ACK、删除、server change tag、account context等在同步边界处理。稳定ID不自动解决冲突。业务事务和outbox同本地原子边界，文件用journal。engine pending可做派生调度队列；一个可重建副本不是第二个权威。是否使用hasPendingUntrackedChanges按真实SDK证据选择，不能为了某个API把本来简单的方案复杂化。[A5]

本地SwiftData不是托管CloudKit store；后者的unique/relationship限制不直接适用。不要为了“Cloud-ready”机械去掉所有本地约束，也不把它们当跨设备协议。

固定一个库的scope与epoch，首次metadata抓取完成后才判断云空/首次上传。账号变化不自动转移家庭数据。同账号独立建的两个库也不能仅凭seed UUID/同名自动合并。全家不同Apple ID共享不在本阶段。

一个Household一个zone仅是候选。original-on-demand需要的最小media-zone/desiredKeys适配可以验证，不因此造可插拔传输系统。只有有证据不满足已批准需求时才探索替代，至多先做一个最小fallback。

## 3. 媒体：内容身份、源引用、表示、副本分开

Photos引用可节约复制，但不等于“原图受到本App独立保护”。PhotosPicker交付字节和持续PhotoKit权限不同；PHCloudIdentifier不是授权或原图存在保证。即使映射成功，新设备能否读到选定精度的图仍待证据。[A1][A2]

App相机/Files导入默认App-owned，不自动写系统Photos。Photos持续访问可用时走reference-first；无权/缺identifier时保存picker交付bytes为App-owned import，不谎称交付一定是原始未编辑资源。正常导入不强迫全库权限。旧V1文件全部保留App-owned，不能倒推引用并删副本。

Media identity稳定；外部源和安全副本可以共存，不是只能选一个的硬owner枚举。后加安全副本不能静默触发原件上云政策升级。每份representation有自己的类型/尺寸/精度/revision/hash；云ACK、下载、preview生成都核验revision，不能旧图覆盖新图。

档案里的选入表示和Photos里的“当前编辑版”可能不同。候选默认保护已记录表示及其来源信息；不因源编辑静默替换档案图片。prototype用版本fixture检验边界，不开发双向编辑器。

Thumbnail是可重建cache；recovery preview是原图不可访问时可浏览的受保护表示，但绝不是原图。它去除非必要GPS/EXIF；App原件保留原字节。单份静态图不代表Live Photo/RAW完整资源集合。无法保证的保真必须显示限制。

hash不用于判断“相同现实物品”，也不为了列表展示强制下载全部Photos原件。模糊指纹只给候选，不自动重绑/销毁副本。引用失效/无权限不删除Item。

## 4. 同步、备份、换机的承诺

iCloud OFF保留本地与待同步意图，不删除云。失败不回滚已成功本地操作，但本地磁盘/save仍会真实失败。配额可以阻止小记录，也不能承诺iOS后台长传输/字节级续传。

metadata/preview先到、original按需必须真实验证；CloudKit record取asset字段会取媒体，拆record本身不证明lazy下载。[A4] 不能访问尚无原件时伪称全量恢复。

MediaPolicy降档/OFF不自动清云；清理单独授权，也不保证立即释放配额。只计算App待传/已确认字节，不编造剩余账户空间/ETA。

Smart Backup含结构/引用/previews和承诺的App-owned原件，但外部Photos仍是依赖；Full必须包含承诺范围内所有实际资源。某原件缺失不能“跳过后成功”。恢复不写系统Photos：可靠引用可绑回；否则保留包内安全副本，不自动增加相册重复。

导出属于一致快照；restore属于独立staging完整generation切换；源store/备份保持。旧备份不带旧账号ACK直接推云；先检查scope/tombstone/当前远端。未解决冲突要被保护或明确排除，不能被迁移成功标签隐藏。

云上传ACK只是某副本接收证据；目标端snapshot/表示精度校验才支持“可删除旧机数据”的承诺。Photos有ID、系统备份开启或同步ON均不够。

## 5. 安全与优化的先后

实验App/目录/资源硬隔离；实验只碰合成素材/明确选择测试图及允许Development namespace。生产schema与加密字段设计不能自动冻结；明文小包仅用于功能验证，不作为生产机密性承诺。[A7]

v1.2纠正优先级：先保证不可重建原件的备份资格；可重建缓存排除；不能仅凭一次CloudACK就把用户原件排除系统备份。动态备份排除/重新纳入可能增加失效窗口，暂不实现。明确承认可能重复占空间，待有可靠重下载契约及产品选择后优化。Apple提供文件排除机制不等于证明同步副本是独立备份。[A6]

所有失败恢复核心：无静默丢数据；精确ACK；账号隔离；重试幂等；父子乱序可恢复；删除不被旧操作复活；无权限不叫损坏；不自动删库；不可用平台不冒充PASS。

## 6. 复审输出的边界

v1.2无新产品功能授权。实验范围收窄不等于安全要求减少。延期优化明确列在Contract P1和impact，不影响无损本地/幂等/恢复等核心门槛。

最终需要正式实现地图：哪些已验证代码可提炼，哪些仅fixture/实验，哪些安全承诺尚缺证据。不要回到无限架构推演；也不要把可编译prototype直接接进shipping runtime。
