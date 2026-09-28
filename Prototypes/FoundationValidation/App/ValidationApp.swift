import SwiftUI
import PhotosUI
import Photos
import SwiftData
import UniformTypeIdentifiers

@main struct FoundationValidationApp: App {
    var body: some Scene { WindowGroup { ValidationView() } }
}

@MainActor struct ValidationView: View {
    @State private var chain: LocalChain?
    @State private var message = "隔离验证环境准备中"
    @State private var counts = [String: Int]()
    @State private var itemNames = [String]()
    @State private var selected: PhotosPickerItem?
    @State private var lastDraft: UUID?
    @State private var latestBackup: URL?
    @State private var restoredSnapshotID: UUID?
    @State private var reportURL: URL?
    @State private var previews = [URL]()
    @State private var liveConfiguration: LiveConfiguration?
    @State private var live: LiveValidation?
    @State private var importingConfiguration = false
    @State private var busy = false
    @State private var setupURL: URL?

    private var programRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--self-test") ? "HHOS-FAV-001-synthetic-self-test" : "HHOS-FAV-001", isDirectory: true)
    }
    var body: some View {
        NavigationStack {
            List {
                Section("HHOS-FAV-001 · v1.2") {
                    Text("本应用仅用于合成测试或明确选中的测试照片。真实云与跨设备验证结果单独记录。")
                    Text(message).accessibilityIdentifier("validation.status")
                    Text("Draft \(counts["drafts", default: 0]) · Item \(counts["items", default: 0]) · Media \(counts["media", default: 0])")
                }
                if !itemNames.isEmpty {
                    Section("当前测试 Item") {
                        ForEach(Array(itemNames.enumerated()), id: \.offset) { _, name in Text(name) }
                    }
                }
                Section("本地链路") {
                    Button("生成测试图片并保存 Draft") { perform {
                        lastDraft = try requireChain().capture(MediaFiles.syntheticJPEG())
                        message = "原件、预览、Draft、Profile 和 outbox 已保存"
                    }}.accessibilityIdentifier("validation.capture")
                    Button("确认最近 Draft") { perform {
                        guard let id = lastDraft else { throw ValidationFailure.invariant("先生成或选择测试图片") }
                        _ = try requireChain().confirm(id); message = "Item 已确认；媒体和 Profile 身份保持"
                    }}
                    Button("重开并恢复 journal") { perform {
                        chain = try LocalChain(root: requireChain().root)
                        live = nil
                        try requireChain().recover(); message = "本地库已重新打开"
                    }}
                }
                Section("Photos 测试") {
                    PhotosPicker("选择一张测试 JPEG/HEIC", selection: $selected, matching: .images, preferredItemEncoding: .current)
                    Button("单独请求 PhotoKit 持续访问权限") {
                        Task { let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                            perform {
                                try LiveEvidence.append(at: programRoot.appendingPathComponent("live-evidence.json"), action: "photos-authorization", outcome: "OBSERVED", report: ["photosAuthorization": String(status.rawValue)])
                                message = "PhotoKit 权限状态：\(status.rawValue)。普通选图不依赖此授权。"
                            }
                        }
                    }
                    Button("重查已选测试照片的映射与当前静态表示") { perform {
                        let references = try requireChain().context.fetch(FetchDescriptor<MediaRepresentation>()).compactMap(\.photosReference)
                        let mapped = PhotosMappingBatch().localReferences(forCloudReferences: references)
                        var outcomes: [String: Int] = [:]
                        for result in mapped.values {
                            outcomes[result.state.rawValue, default: 0] += 1
                            if let identifier = result.identifier, result.state == .mapped {
                                do {
                                    let data = try PhotosAdapter.readSelectedCurrentRepresentation(identifier)
                                    outcomes["readableCurrentStill", default: 0] += data.isEmpty ? 0 : 1
                                } catch { outcomes[PhotosAdapter.classify(error).rawValue, default: 0] += 1 }
                            }
                        }
                        try JSONEncoder().encode(outcomes).write(to: programRoot.appendingPathComponent("photos-observation.json"), options: .atomic)
                        try LiveEvidence.append(at: programRoot.appendingPathComponent("live-evidence.json"), action: "photos-mapping-current-still", outcome: "OBSERVED", report: outcomes.mapValues(String.init))
                        message = "已检查 \(mapped.count) 份已选引用；仅读取当前静态表示，不替换档案图片，也不写相册"
                    }}
                    Text("Picker 交付表示会保留为 App 安全副本；不声称它一定是未编辑原图或 Live Photo 全资源。")
                }
                Section("一致快照与隔离恢复") {
                    Button("创建 Smart 目录备份") { perform {
                        let packages = programRoot.appendingPathComponent("packages")
                        try FileManager.default.createDirectory(at: packages, withIntermediateDirectories: true)
                        let target = packages.appendingPathComponent(UUID().uuidString)
                        let result = try BackupRestore.export(requireChain(), to: target, full: false)
                        try LiveEvidence.append(at: programRoot.appendingPathComponent("live-evidence.json"), action: "backup", outcome: "COMPLETED", report: ["snapshotCode": String(MediaFiles.hash(Data(result.snapshotID.uuidString.utf8)).prefix(12)), "sourceRepresentations": String(result.representations.count)])
                        latestBackup = target; message = "快照已校验：\(result.files.count) 个文件。明文实验包，不是生产保密承诺。"
                    }}
                    Button("恢复最近备份到新 generation") { perform {
                        guard let source = latestBackup else { throw ValidationFailure.invariant("先创建测试备份") }
                        let generations = programRoot.appendingPathComponent("restored")
                        restoredSnapshotID = try BackupRestore.restore(source, into: generations)
                        let manifest = try BackupRestore.validate(source)
                        let target = try BackupRestore.activeGeneration(in: generations)
                        for representation in manifest.representations {
                            guard try MediaFiles.hash(Data(contentsOf: target.appendingPathComponent(representation.path))) == representation.sha256 else { throw ValidationFailure.invariant("target representation verification failed") }
                        }
                        try LiveEvidence.append(at: programRoot.appendingPathComponent("live-evidence.json"), action: "restore", outcome: "LOCAL_TARGET_VERIFIED", report: ["snapshotCode": String(MediaFiles.hash(Data(manifest.snapshotID.uuidString.utf8)).prefix(12)), "verifiedTargetRepresentations": String(manifest.representations.count), "photosWrites": "0"])
                        message = "隔离 generation 已恢复；原库保留；系统相册写入为零；云端准入待验证"
                    }}
                    Button("选用隔离恢复库进行准入验证") { perform {
                        guard live == nil else { throw ValidationFailure.invariant("先关闭当前同步") }
                        chain = try LocalChain(root: BackupRestore.activeGeneration(in: programRoot.appendingPathComponent("restored")))
                        message = "已选用恢复库；连接后必须先抓取远端 tombstone；原库保持"
                    }}
                }
                Section("平台证据") {
                    Text(liveConfiguration == nil ? "CloudKit 未配置。导出本地库设置，在已签名 App 上运行配置工具，再导入配置。" : "Development 配置已校验；仅手动执行。需分别保留源端与空白端证据。")
                    Button("导出本地库设置（用于生成私有配置）") { perform {
                        let url = programRoot.appendingPathComponent("local-setup.json")
                        let setup = ["program": "HHOS-FAV-001", "libraryID": try requireChain().libraryID.uuidString]
                        try JSONEncoder().encode(setup).write(to: url, options: .atomic)
                        setupURL = url
                    }}
                    if let setupURL { ShareLink("分享私有设置", item: setupURL) }
                    Button("导入已签名 Development 配置") { importingConfiguration = true }
                    Button("连接已授权测试容器") { runLive {
                        guard let config = liveConfiguration else { throw ValidationFailure.invariant("先导入已校验配置") }
                        live = try await LiveValidation.start(config: config, chain: requireChain(), budgetURL: programRoot.appendingPathComponent("live-budget.json"))
                        message = "已连接测试 namespace；尚未声明复制或恢复成功"
                    }}
                    Button("抓取 metadata／preview，再发送本地意图") { runLive {
                        try await requireLive().metadataRoundTrip()
                        message = "本次 metadata 操作结束；请导出摘要核对实际结果"
                    }}
                    Button("修改测试 Item（验证 update）") { perform {
                        let runner = try requireLive()
                        guard let item = try requireChain().context.fetch(FetchDescriptor<ItemRecord>()).first,
                              let document = try runner.core.document(item.id) else { throw ValidationFailure.invariant("先确认测试 Item") }
                        var wire = try JSONDecoder().decode(WireRecord.self, from: document.payload)
                        wire.operationID = UUID(); wire.revision += 1; wire.name = "Synthetic updated item"
                        try runner.core.write(wire); message = "更新意图已本地保存，等待手动发送"
                    }}
                    Button("明确上传一张 App-owned 测试原件") { runLive {
                        try await requireLive().uploadOneOriginal(); message = "上传操作结束；ACK 不代表目标端已恢复"
                    }}
                    Button("按需取回一张测试原件并校验") { runLive {
                        try await requireLive().fetchOneOriginal(); message = "按需读取结束；摘要记录目标表示校验结果"
                    }}
                    Button("关闭测试同步，保留云端数据") { runLive {
                        try await requireLive().adapter.stop(); live = nil; message = "同步已关闭；云端既有数据未删除"
                    }}
                    Button("生成脱敏执行摘要") { perform {
                        let url = programRoot.appendingPathComponent("validation-summary.json")
                        let summary: [String: Any] = ["program": "HHOS-FAV-001", "counts": counts,
                            "liveCloud": live?.report ?? ["status": "NOT_RUN_THIS_SESSION"], "crossDevicePhotos": "NOT_RUN", "photosWrites": 0,
                            "sourceSnapshotVerifiedOnTarget": restoredSnapshotID != nil ? "LOCAL_GENERATION_ONLY" : "NOT_RUN"]
                        var exported = summary
                        let evidence = try LiveEvidence.load(programRoot.appendingPathComponent("live-evidence.json"))
                        let photosURL = programRoot.appendingPathComponent("photos-observation.json")
                        if FileManager.default.fileExists(atPath: photosURL.path) {
                            exported["photosObservation"] = try JSONSerialization.jsonObject(with: Data(contentsOf: photosURL))
                        }
                        exported["liveObservations"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence))
                        exported["estimatedTransferredBytes"] = try LiveBudget.load(programRoot.appendingPathComponent("live-budget.json")).estimatedBytes
                        try JSONSerialization.data(withJSONObject: exported, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
                        reportURL = url; message = "脱敏摘要已生成，不含照片、账号或原始路径"
                    }}
                    if let reportURL { ShareLink("导出脱敏摘要", item: reportURL) }
                }
                if !previews.isEmpty {
                    Section("受保护的 recovery preview") {
                        ForEach(previews, id: \.self) { url in
                            if let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200) }
                        }
                    }
                }
            }
            .disabled(busy)
            .navigationTitle("Foundation Validation")
            .fileImporter(isPresented: $importingConfiguration, allowedContentTypes: [.json]) { result in
                perform {
                    let url = try result.get()
                    let accessible = url.startAccessingSecurityScopedResource()
                    defer { if accessible { url.stopAccessingSecurityScopedResource() } }
                    let bytes = try Data(contentsOf: url)
                    let config = try JSONDecoder().decode(LiveConfiguration.self, from: bytes)
                    try installConfiguration(config)
                    try bytes.write(to: programRoot.appendingPathComponent("live-config.json"), options: .atomic)
                    message = "签名配置已绑定；尚未发起网络请求"
                }
            }
            .task { perform {
                chain = try LocalChain(root: programRoot.appendingPathComponent("local"))
                let configurationURL = programRoot.appendingPathComponent("live-config.json")
                if FileManager.default.fileExists(atPath: configurationURL.path) {
                    try installConfiguration(JSONDecoder().decode(LiveConfiguration.self, from: Data(contentsOf: configurationURL)))
                }
                try requireChain().recover(); message = "独立本地环境就绪"
                if ProcessInfo.processInfo.arguments.contains("--self-test") { try runSyntheticSelfTest() }
            }}
            .onChange(of: selected) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw ValidationFailure.invariant("未取得选中图片字节") }
                        let resolution = PhotosAdapter.resolveSelected(identifier: item.itemIdentifier, deliveredBytes: data)
                        perform {
                            let cloudReference = resolution.localIdentifier.flatMap { id in PhotosMappingBatch().cloudReferences(forSelectedIdentifiers: [id])[id]?.identifier }
                            lastDraft = try requireChain().capture(resolution.fallbackBytes, precision: resolution.precision, photoReference: cloudReference)
                            try LiveEvidence.append(at: programRoot.appendingPathComponent("live-evidence.json"), action: "photos-selection", outcome: "SAVED", report: ["selectedAccess": resolution.access.rawValue, "representationPrecision": resolution.precision, "hasCloudReference": String(cloudReference != nil)])
                            message = "选中表示已保存；持续访问状态：\(resolution.access.rawValue)"
                        }
                    } catch { message = "选图未完成：\(error.localizedDescription)" }
                }
            }
        }
    }
    private func installConfiguration(_ config: LiveConfiguration) throws {
        guard live == nil else { throw ValidationFailure.invariant("先关闭当前同步") }
        try config.validateArtifact()
        // A replica gets its own persistent store; the existing local library is never rebound.
        let root = programRoot.appendingPathComponent(config.role == "blankReplica" ? "blank-replica" : "local")
        let configured = try LocalChain(root: root, libraryID: config.libraryID)
        try configured.recover()
        chain = configured; liveConfiguration = config; lastDraft = nil
    }
    private func requireLive() throws -> LiveValidation {
        guard let live else { throw ValidationFailure.invariant("先连接已授权测试容器") }
        return live
    }
    private func runLive(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try LiveEvidence.append(at: programRoot.appendingPathComponent("live-evidence.json"), action: "manual-control", outcome: "STARTED", report: live?.report ?? [:])
                try await operation(); perform {}
            } catch {
                // Record only stable error class/code, never userInfo, account IDs or raw paths.
                let value = error as NSError
                var report = live?.report ?? [:]
                report["errorCode"] = String(value.code)
                report["errorClass"] = value.domain == "CKErrorDomain" ? "CloudKit" : "local-or-configuration"
                do { try LiveEvidence.append(at: programRoot.appendingPathComponent("live-evidence.json"), action: "manual-control", outcome: "FAILED", report: report) }
                catch { message = "证据文件无法保存；停止测试并保留本地数据"; return }
                message = "平台操作未完成；保留本地数据。请核对配置、账号和执行摘要。"
            }
        }
    }

    private func runSyntheticSelfTest() throws {
        let source = try requireChain()
        let backup = programRoot.appendingPathComponent("snapshot")
        let generations = programRoot.appendingPathComponent("generations")
        let reopening = FileManager.default.fileExists(atPath: backup.path)
        if !reopening {
            let id = try source.capture(MediaFiles.syntheticJPEG(seed: 42))
            _ = try source.confirm(id)
            _ = try BackupRestore.export(source, to: backup, full: true)
            _ = try BackupRestore.restore(backup, into: generations)
        }
        let manifest = try BackupRestore.validate(backup)
        let restored = try LocalChain(root: BackupRestore.activeGeneration(in: generations))
        guard try source.counts()["items"] == 1, try restored.counts() == source.counts() else {
            throw ValidationFailure.invariant("self-test count mismatch")
        }
        for representation in manifest.representations {
            let original = try Data(contentsOf: source.root.appendingPathComponent(representation.path))
            let copy = try Data(contentsOf: restored.root.appendingPathComponent(representation.path))
            guard original == copy, MediaFiles.hash(copy) == representation.sha256 else { throw ValidationFailure.invariant("self-test restored original mismatch") }
        }
        let report: [String: Any] = ["program": "HHOS-FAV-001", "mode": reopening ? "process-reopen" : "initial-chain", "result": "PASS", "snapshot": manifest.snapshotID.uuidString, "counts": try restored.counts(), "verifiedRepresentations": manifest.representations.count, "liveService": "NOT_RUN", "photosWrites": 0]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: programRoot.appendingPathComponent(reopening ? "reopen-report.json" : "initial-report.json"), options: .atomic)
        message = reopening ? "合成链路重启复核通过；云与真机待验" : "合成链路与恢复校验通过；云与真机待验"
    }

    private func requireChain() throws -> LocalChain {
        guard let chain else { throw ValidationFailure.invariant("本地库不可用；保留原数据") }
        return chain
    }
    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            let chain = try requireChain(); counts = try chain.counts()
            itemNames = try chain.context.fetch(FetchDescriptor<ItemRecord>()).map(\.name)
            previews = try chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).compactMap { $0.thumbnailFileName.map { chain.root.appendingPathComponent("media/" + $0) } }
        } catch {
            message = (error as? CommittedCaptureError)?.errorDescription ?? StorageFailure.classify(error).message
        }
    }
}
