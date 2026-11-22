# 开发与发布

面向改这个仓库的人。上游 `SammySnake-d/NSpace` 的原始文档在 `DESIGN.md` / `spec.md` / `PRODUCT.md`，
这里只记**本机怎么构建、怎么验、怎么发版，以及踩过的坑**。

## 环境

- macOS 26.0+（`Package.swift` 的 `platforms` 与 `Info.plist` 的 `LSMinimumSystemVersion` 都是 26.0）
- Apple Silicon；**Command Line Tools 就够，不需要完整 Xcode**
- Swift 6（`swift-tools-version` 见 `Package.swift`）

## 构建

```bash
swift build -c release --disable-sandbox   # 首次约 60s，增量 20s
./scripts/build-app.sh release             # 组装 .app + 签名 + 注册
open build/NSpace.app
```

`--disable-sandbox` 不是可选项：SwiftPM 编译 manifest 时会调 `sandbox-exec`，在被沙盒化的
终端里会报 `sandbox_apply: Operation not permitted` 直接失败。`scripts/build-app.sh` 里已经带上了。

安装到系统：

```bash
ditto build/NSpace.app /Applications/NSpace.app   # 用 ditto 覆盖，别先 rm 旧包（见坑 4）
```

## 签名与 TCC

`build-app.sh` 的签名优先级：`SIGN_IDENTITY` 环境变量 > 本机证书 `NSpace Dev` > ad-hoc。

- **ad-hoc 签名每次重编译 cdhash 都会变**，TCC（完全磁盘访问）是按 cdhash 记的，所以每次装新版
  都可能要重新授权一次。
- 想一劳永逸：钥匙串里建一张自签代码签名证书，命名为 `NSpace Dev`，脚本会自动识别并优先使用。
  之后指纹稳定，授权跨构建持久。

## LaunchServices 注册卫生

同一个 bundle id（`com.nspace.NSpace`）只要有两份**同时存在**的注册，Spotlight、「打开方式」、
启动台就会列出两个 NSpace，且点开启动哪一份是随机的。

`build-app.sh` 结尾做了两件事：

1. 清理路径已消失的死注册（`lsregister -dump` → `[ -d ]` 判断 → `-u`）。注意解析 path 行要用
   `sed` 剥掉 `path:` 前缀和 `(0x…)` 后缀，**不能用 `awk '{print $2}'`**——路径含空格时只会截到
   第一段，清理逻辑会静默空转。
2. 已安装到 `/Applications` 时只注册安装版、并 `-u` 掉 `build/` 副本（`REGISTER_BUILD=1` 可强制注册副本）。

## 测试

两条通道，互补。**都用脚本跑，别手敲 `swift test`。**

### 单元测试（18 个套件 / 147 项）

```bash
./scripts/test.sh --disable-sandbox
```

`test.sh` 存在的意义就是绕开「只装 CLT 跑不了 swift-testing」这个坑：它用 `-plugin-path` 指认
CLT 里的 `TestingMacros` 插件、用 `-rpath` 补上 `Testing.framework` 的搜索路径。裸跑
`swift test` 会报 `TestingMacros.TestDeclarationMacro could not be found`——那是**没带这些参数**，
不是环境缺东西。

`--disable-sandbox` 不能省（同构建：manifest 编译会调 `sandbox-exec`）。

### UI 冒烟（无需 Xcode、无需辅助功能权限）

```bash
./scripts/ui-smoke.sh          # 退出码 0 = 全过
cat /tmp/nspace-ui/report.txt  # 逐条断言
open /tmp/nspace-ui/           # 33 张自渲染截图
```

脚本先构建，再分两阶段跑：阶段 A 把窗口 frame 设成 900×520 并退出（触发 autosave），阶段 B 断言
frame 恢复。**窗口尺寸类断言必须走这个脚本**——手敲 `NSPACE_UITEST=1` 直接跑会因为上一次残留的
窗口 frame 而随机失败，看着像回归其实不是。

纯逻辑断言（决策谓词、步进器之类）优先加进 `UISelfTest`，比等 UI 复现划算，例如
`M29 ⌘+滚轮缩放` 就是直接测 `DisplayZoom.steps` 的方向与累积阈值。

## 发版

```bash
# 1. 改 VERSION（新功能 bump minor，修 bug bump patch）+ 在 CHANGELOG.md 顶部加一节
# 2. 提交
git add -A && git commit -m "chore: 发布 vX.Y.Z"
# 3. 打 tag 推送，CI 自动构建并发 release
git tag -a vX.Y.Z -m "vX.Y.Z — 一句话"
git push origin main && git push origin vX.Y.Z
```

`.github/workflows/release.yml` 在 tag 推送后跑：`build-app.sh` → 打 zip → 抽 CHANGELOG 对应小节
当 release 说明 → 上传 `NSpace-vX.Y.Z.zip` + `checksums.txt`。

手工发（CI 不可用时）：

```bash
ditto -c -k --sequesterRsrc --keepParent build/NSpace.app NSpace-vX.Y.Z.zip
gh release create vX.Y.Z NSpace-vX.Y.Z.zip -R <owner>/NSpace --notes-file notes.md
```

`-R` 不能省：仓库同时有 `origin`（本仓库）和 `upstream`（上游）两个远程时，`gh` 可能解析到上游，
报「tag exists locally but has not been pushed to <upstream>」。

## 已知坑清单

1. **`super.draggingEnded(_:)` 必崩**。`NSView.h` 声明了 `draggingEnded:` 但全链路没有实现
   （运行时 `NSView.instancesRespond(to:)` / `NSTableView` 都是 false，其余 `dragging*` 都是 true）。
   AppKit 在拖拽会话结束时会给拖放目标发这个消息，override 里一调 super 就
   `unrecognized selector` → `abort()`。`draggingExited(_:)` 的 super 是安全的。
2. **`volumeAvailableCapacityForImportantUsage` 在第三方文件系统上恒为 0**（macFUSE/ufsd 挂的
   NTFS、FAT32）。拿它判断「有没有空间」会把可写卷判成只读。容量走双通道
   `important > 0 ? important : f_bavail`；只读判定只认 `volumeIsReadOnly`。
3. **裸 `swift test` 跑不了**，不是环境缺 Xcode 的问题——`scripts/test.sh` 补了插件路径与 rpath，见上文。
4. **覆盖安装后别让旧 app 留在废纸篓**：某些机制会把被替换的 `.app` 挪进 `~/.Trash`，
   而废纸篓里的 app 仍会被 Finder 重新注册 → 又出现第二个 NSpace。装完顺手清掉废纸篓。
5. **跨卷搬运用 `ditto`**：`mv` 在跨设备时可能直接 `EXDEV` 失败。搬完核对文件数与 `git status` 再删源。
6. **新仓库刚建时 CI 可能不触发**：tag 推送后工作流注册有延迟，第一次发版可能需要手工建 release，
   之后正常。
