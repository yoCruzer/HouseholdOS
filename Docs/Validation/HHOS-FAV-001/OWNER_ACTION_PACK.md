# Owner Action Pack — HHOS-FAV-001 v1.2

状态：集中待执行；没有真实 CloudKit、真机 Photos 或双端恢复 PASS。此包让缺失平台证据一次准备、集中操作、统一导出。无需主 Apple ID 登出、系统密钥重置或清空 iCloud。

## 1. 设置（已有资源；不创建 Developer Portal 资源）

1. 准备两个隔离测试端 A/B，记录设备、OS、同一构建版本。CloudKit 可先用两个独立测试客户端；双真机 Photos/相机证据仍需对应真机。iOS 最低 17；当前本机只编译/运行过 SDK/runtime 26.5，不据此声称 iOS 17 runtime 已通过。
2. 提供已配置且明确允许本 Program 测试的 **Development** container，以及独立 App ID `com.yocruzer.householdos.foundationvalidation` 的现有 Development profile/签名。需要 CloudKit、该 container 关联和 development push entitlement。缺任何一项则保持 BLOCKED_EXTERNAL；不能改用正式 App ID。
3. 仅对 `Prototypes/FoundationValidation/FoundationValidation.xcodeproj` 使用现有 Manual 签名构建；不使用 `-allowProvisioningUpdates`，不让 Automatic Signing 创建资源，不改正式工程或 entitlements。不把未签名 Simulator 构建当 Development 签名证明。
4. 验证 App 与正式 App 可并存。不要卸载含真实数据的 App。仅选择少量专门准备的静态 JPEG/HEIC 测试图；默认约 20 Items/8 Media，LIVE 用 1–2 张小图即可。禁止把个人照片、账号信息或完整私有配置附到公开 PR。
5. A 启动后生成一个合成 Draft、确认 Item，点击“导出本地库设置”。私有 JSON 的 `libraryID` 用于两端配置；不要用正式库 ID。先不连接云。

在验证工程目录运行下列**模板**命令，用实际已经签名的 `.app` 和明确允许的 container 填写参数：

```sh
python3 Tools/prepare_live_config.py \
  --app '/path/to/already-signed/FoundationValidation.app' \
  --container 'iCloud.your.authorized.development.container' \
  --library 'UUID-FROM-A-PRIVATE-SETUP' \
  --role source --authorize-development-test \
  --output LocalEvidence/live-config-A.json
```

工具只检查已有签名/entitlements并写私有配置，不创建平台资源。A 导入该配置；它包含新随机测试 zone。B 用同一 library 和 A 的 `metadataZone`，针对 B 实际安装的签名产物另生成配置：

```sh
python3 Tools/prepare_live_config.py \
  --app '/path/to/already-signed/FoundationValidation.app' \
  --container 'iCloud.your.authorized.development.container' \
  --library 'SAME-LIBRARY-UUID' --role blankReplica \
  --zone 'HHOSVAL_UUID-FROM-A-CONFIG' --authorize-development-test \
  --output LocalEvidence/live-config-B.json
```

- App 核对可执行文件及 Debug dylib 指纹；重新构建/签名后重新生成匹配配置。配置不是远程 attestation，依赖 Owner 执行只读签名检查。
- B 导入后使用单独 blank-replica root，保留原 local root。同一 root 的库/账号不允许静默改绑。
- 只登记两个测试 zone（metadata 与 `_media`）。已有 zone 丢失或初始化结果不明确时不自动重建，保留配置及错误码。稳定 record type 为 `HHOSVAL_Entity` / `HHOSVAL_Original`；Development schema 是 container 级副作用，删除 zone 不删除 schema。
- 每端持久估算上限 50 MiB，A+B 总计最多 100 MiB；请求失败和重试也保留预留量。不得用重新安装、删除账本、新 run/换 role 重置预算。多于两个端需先集中核算余量，当前不自动授权更多额度。系统额外流量仅能估算，不是精准计费数据。

## 2. 一次集中设备执行

| 顺序 | 操作 | 记录与合格条件 |
| --- | --- | --- |
| 1 本地 | A 保存合成 Draft，关闭重启，恢复 journal，确认 Item | Draft/Item 数量正确；媒体可读；同一 Draft 重试不重复；无照片/账号泄露 |
| 2 云 create/read | A “连接已授权测试容器”→“抓取 metadata／preview，再发送本地意图” | 不出现隐式签名/资源创建；首次 fetch 完成后才有发送；导出摘要，失败保留错误码和未完成操作 |
| 3 空白端 | B 导入 blankReplica 配置、连接、只跑 metadata/preview | Item/Profile 和 recovery preview 可见；在显式原件取回前记录 original request 计数为 0。结合原生 SDK/网络观测确认没有隐式原件请求；仅看到小图不够 |
| 4 update | A 点击“修改测试 Item”再发送，B 再抓取 | B 显示/摘要对应更新；真实 encrypted payload 可解码；真实回调顺序单列 LIVE_SERVICE，不由 mock 代替 |
| 5 CKAsset | A 明确上传一张 App-owned 测试原件；B 按需取回一张并校验；重启 B 后再核对文件 | 当前 representation/hash 校验，durable 本地文件存在；不能只用 A ACK 宣称换机成功。不要选大原件 |
| 6 OFF | 关闭测试同步，保留本地内容，重开 | 不再新调度；云数据未删除。开启后先完成抓取；无主账号登出 |
| 7 Photos | 用专用 JPEG/HEIC 分别验证未授权普通选图、limited 包含/不包含、充分授权、撤权；点击“重查已选测试照片…” | 每次导出对应权限状态结果。拒绝 PhotoKit 仍保留 picker bytes；nil identifier/不可访问也不丢图；不承诺 picker 是未编辑原图 |
| 8 跨端 Photos | A 选择专用素材并授权后复制 metadata 到 B；B 允许访问对应素材后重查 | 只按 PHCloudIdentifier 线索映射已选引用；读当前静态表示。无匹配/多候选/需网络要如实记录，不要求全图库扫描，不覆盖档案已保存表示 |
| 9 backup/restore | A 生成 Smart 目录包，恢复隔离 generation；导出源 snapshot 与目标本地校验；可选“选用隔离恢复库…”后再连接 | 原库保留；无 Photos 新增写入；恢复清旧 session/ACK，先 fetch 当前 tombstone。包含 Photos picker 表示不宣称 Full 原始资源保真 |
| 10 收尾 | A/B 各生成脱敏摘要，统一汇总 | 保留中断/失败记录，不能只交最终一次成功。账号、引用和真实 hash 不进入公开材料 |

说明：当前 PhotoKit 当前表示读取禁止隐式网络下载；云端独有资源会报告需网络/不可用，不伪称原件已恢复。参考照片的编辑版、Live Photo/RAW 全资源仍在未支持范围。备份包恢复当前只演示同端隔离 generation；真正双端迁移需源 snapshot/包和目标端完整表示校验的额外操作证据，不能据上述云复制步骤直接抹旧机。

quota、网络、节流、部分成功、删除与旧备份/旧 ACK 等破坏性边界以确定性注入为主；无需填满真实磁盘/iCloud，也不让 Owner 删除系统云数据制造错误。`userDeletedZone` 与普通 `zoneNotFound` 按不同原因暂停；不得把删除测试 zone 冒充系统设置主动删除证据。

## 3. 已接受正式构建的 PR #4 真机待验（同次操作，单列证据）

使用已接受的正式生产代码 `5d0c4c347f4069432d94459b1c3c204c748a68b6` 对应现有构建，记录实际构建号；若没有该构建则记 BLOCKED_EXTERNAL，不用 prototype 替代，不改正式 App：

1. 相机权限允许/拒绝及拍摄流程。
2. 光学预览与最终照片内容一致。
3. 竖横屏/旋转方向正确。
4. 一次物理快门只生成一个 Draft。
5. 真实测试照片保存后进程重启仍存在、可读。

这些结果仅归属于对应正式构建。验证 App 同名按钮的通过不覆盖它们。

## 4. 一份脱敏证据交付

集中提供 A/B 导出的 `validation-summary.json`、设备/OS/构建代号、每步动作与预期/实际、失败/中断位置，以及上述正式构建五项结果。App 持久记录 LIVE 操作起始/结果、原件请求次数、估算流量、preview 数、当前表示校验；STARTED 不等于 PASS。Photos 只导出分类计数，不导出 identifier 或照片。

需要私下保留但不公开：签名 entitlement/config、真实账号/Photos ID、真实文件 hash、照片/GPS、本机个人路径、完整云 dump、备份包。不要把私有配置或真实备份加入 Git。

当前最终验收与一次独立审查尚未结束；本包会随最终证据收敛。平台准备失败不影响已保存的本地工程。未得到目标端 snapshot/精度证据前，无任何“安全抹除旧机”建议。清理云测试资源必须核对登记 namespace；本 App 不提供自动清空按钮。
