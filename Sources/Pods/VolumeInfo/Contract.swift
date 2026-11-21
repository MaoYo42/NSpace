import Foundation
import NSpaceContracts

// VolumeInfo 胶囊唯一对外契约面（Axiom 3）：挂载卷枚举 / 变更信号 / 推出

public struct VolumeItem: Sendable, Hashable {
    public let name: String
    public let url: URL
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    public let isEjectable: Bool
    public let isRemovable: Bool
    /// 内置根卷（"/"）不显示推出钮
    public let isRoot: Bool
    /// 真实只读态（volumeIsReadOnly）。第三方 FS（macFUSE/ufsd 的 NTFS、FAT32）容量可能读不到，
    /// 但**不等于**只读——判定只读必须看这个标志，不能拿可用容量为 0 代替
    public let isReadOnly: Bool

    public init(name: String, url: URL, totalCapacity: Int64, availableCapacity: Int64,
                isEjectable: Bool, isRemovable: Bool, isRoot: Bool, isReadOnly: Bool = false) {
        self.name = name; self.url = url
        self.totalCapacity = totalCapacity; self.availableCapacity = availableCapacity
        self.isEjectable = isEjectable; self.isRemovable = isRemovable; self.isRoot = isRoot
        self.isReadOnly = isReadOnly
    }
}

public struct VolumeError: ClassifiedError {
    public let errorClass: ErrorClass
    public let localizedDescription: String

    init(_ cls: ErrorClass, _ message: String) {
        self.errorClass = cls
        self.localizedDescription = message
    }
}
