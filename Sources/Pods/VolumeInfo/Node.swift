import AppKit
import NSpaceContracts

/// 卷信息节点（Axiom 2：无全局可变状态；NSWorkspace/FileManager 是被控物理基质）
public struct VolumeInfo: Sendable {
    public init() {}

    /// 枚举当前挂载卷（浏览可见卷；跳过系统隐藏卷）
    public func volumes() -> [VolumeItem] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsRootFileSystemKey,
            .volumeIsBrowsableKey, .volumeIsReadOnlyKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let rv = try? url.resourceValues(forKeys: Set(keys)),
                  rv.volumeIsBrowsable ?? true else { return nil }
            // 容量双通道：importantUsage 是 APFS 上的"重要用途"口径（Finder 同源），但第三方 FS
            // （macFUSE/ufsd 挂的 NTFS、FAT32）一律返回 0——此时回退 f_bavail，否则会被上层
            // 误判成"只读"（双 NSpace 那次同类问题的兄弟 bug）
            let important = rv.volumeAvailableCapacityForImportantUsage ?? 0
            let plain = Int64(rv.volumeAvailableCapacity ?? 0)
            return VolumeItem(
                name: rv.volumeName ?? url.lastPathComponent,
                url: url,
                totalCapacity: Int64(rv.volumeTotalCapacity ?? 0),
                availableCapacity: important > 0 ? important : plain,
                isEjectable: rv.volumeIsEjectable ?? false,
                isRemovable: rv.volumeIsRemovable ?? false,
                isRoot: rv.volumeIsRootFileSystem ?? (url.path == "/"),
                isReadOnly: rv.volumeIsReadOnly ?? false
            )
        }
    }

    /// 挂载/卸载变更信号流（NSWorkspace 通知在主线程投递；流终止自动移除观察者）
    @MainActor
    public func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = NSWorkspace.shared.notificationCenter
            let names: [Notification.Name] = [
                NSWorkspace.didMountNotification,
                NSWorkspace.didUnmountNotification,
                NSWorkspace.didRenameVolumeNotification,
            ]
            // 观察者令牌非 Sendable，用盒子跨进 @Sendable 的 onTermination
            let box = ObserverBox(center: center, tokens: names.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    continuation.yield(())
                }
            })
            continuation.onTermination = { _ in box.removeAll() }
        }
    }

    /// 推出卷（失败归 external：设备占用/权限等外部条件）
    public func eject(_ url: URL) throws {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            throw VolumeError(.external, error.localizedDescription)
        }
    }
}
