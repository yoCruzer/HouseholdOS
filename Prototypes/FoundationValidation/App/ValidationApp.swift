import SwiftUI
import PhotosUI
import Photos
import SwiftData

@main struct FoundationValidationApp: App {
    var body: some Scene { WindowGroup { ValidationView() } }
}

@MainActor struct ValidationView: View {
    @State private var chain: LocalChain?
    @State private var message = "隔离验证环境准备中"
    @State private var counts = [String: Int]()
    @State private var selected: PhotosPickerItem?
    @State private var lastDraft: UUID?
    @State private var latestBackup: URL?
    @State private var restoredSnapshotID: UUID?
    @State private var reportURL: URL?
    @State private var previews = [URL]()

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
                        chain = try LocalChain(root: programRoot.appendingPathComponent("local"))
                        try requireChain().recover(); message = "本地库已重新打开"
                    }}
                }
                Section("Photos 测试") {
                    PhotosPicker("选择一张测试 JPEG/HEIC", selection: $selected, matching: .images, preferredItemEncoding: .current)
                    Button("单独请求 PhotoKit 持续访问权限") {
                        Task { let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                            message = "PhotoKit 权限状态：\(status.rawValue)。普通选图不依赖此授权。"
                        }
                    }
                    Text("Picker 交付表示会保留为 App 安全副本；不声称它一定是未编辑原图或 Live Photo 全资源。")
                }
                Section("一致快照与隔离恢复") {
                    Button("创建 Smart 目录备份") { perform {
                        let packages = programRoot.appendingPathComponent("packages")
                        try FileManager.default.createDirectory(at: packages, withIntermediateDirectories: true)
                        let target = packages.appendingPathComponent(UUID().uuidString)
                        let result = try BackupRestore.export(requireChain(), to: target, full: false)
                        latestBackup = target; message = "快照已校验：\(result.files.count) 个文件。明文实验包，不是生产保密承诺。"
                    }}
                    Button("恢复最近备份到新 generation") { perform {
                        guard let source = latestBackup else { throw ValidationFailure.invariant("先创建测试备份") }
                        restoredSnapshotID = try BackupRestore.restore(source, into: programRoot.appendingPathComponent("restored"))
                        message = "隔离 generation 已恢复；原库保留；系统相册写入为零；云端准入待验证"
                    }}
                }
                Section("平台证据") {
                    Text("CloudKit：尚未配置已授权的 Development 容器。不得把本地通过当作真实服务通过。")
                    Button("生成脱敏执行摘要") { perform {
                        let url = programRoot.appendingPathComponent("validation-summary.json")
                        let summary: [String: Any] = ["program": "HHOS-FAV-001", "counts": counts,
                            "liveCloud": "NOT_RUN", "crossDevicePhotos": "NOT_RUN", "photosWrites": 0,
                            "sourceSnapshotVerifiedOnTarget": restoredSnapshotID != nil ? "LOCAL_GENERATION_ONLY" : "NOT_RUN"]
                        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
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
            .navigationTitle("Foundation Validation")
            .task { perform {
                chain = try LocalChain(root: programRoot.appendingPathComponent("local"))
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
                            message = "选中表示已保存；持续访问状态：\(resolution.access.rawValue)"
                        }
                    } catch { message = "选图未完成：\(error.localizedDescription)" }
                }
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
            previews = try chain.context.fetch(FetchDescriptor<MediaAssetRecord>()).compactMap { $0.thumbnailFileName.map { chain.root.appendingPathComponent("media/" + $0) } }
        } catch { message = "操作未完成，数据保留：\(error.localizedDescription)" }
    }
}
