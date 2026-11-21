#!/usr/bin/env bash
# NSpace 无 Xcode 构建管线：swift build → 组装 .app → 签名
# 用法: ./scripts/build-app.sh [debug|release]   (默认 release)
# 签名身份优先级：env SIGN_IDENTITY > 本机固定证书 "NSpace Dev"（I-29 根治：ad-hoc 每次构建换指纹
# 会让图标服务/TCC 把每个构建当陌生 App——图标空白+FDA 授权漂移）> ad-hoc 兜底（CI 无证书自动落此）
if [ -z "${SIGN_IDENTITY:-}" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "NSpace Dev"; then
  SIGN_IDENTITY="NSpace Dev"
fi
# 环境: SIGN_IDENTITY 可指自签证书使 TCC 授权跨构建持久；默认 "-"(ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

CONF="${1:-release}"
APP="build/NSpace.app"
BIN=".build/$CONF/NSpace"

swift build -c "$CONF" --disable-sandbox

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NSpace"

# 探针不进包（生产二进制隔离）
cp Support/Info.plist "$APP/Contents/Info.plist"
VERSION="$(cat VERSION | tr -d '[:space:]')"
BUILD_NUM="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUM" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# 本地化与图标
cp -R Resources/zh-Hans.lproj Resources/en.lproj "$APP/Contents/Resources/"
if [ ! -f Support/NSpace.icns ]; then
  swift scripts/generate-icon.swift Support/icon_1024.png
  ./scripts/make-icns.sh
fi
cp Support/NSpace.icns "$APP/Contents/Resources/NSpace.icns"

codesign --force --sign "${SIGN_IDENTITY:--}" --identifier com.nspace.NSpace "$APP"
echo "✓ 已构建并签名 $APP (v$VERSION build $BUILD_NUM, sign=${SIGN_IDENTITY:-ad-hoc})"

# LS 注册卫生（I-15 根因回归防护）：清除已消失路径的 com.nspace 注册（并发 worktree 构建残留会
# 让 LaunchServices 解析到死 bundle → 设默认程序报"未能打开该文件"、TCC 面板丢图标），再注册当前构建
# CI 跑器上无既有注册（grep 零命中会在 pipefail 下杀脚本——本项目陷阱清单第 5 条，CI 复发实锤），
# 且注册对 CI 产物无意义——仅本机开发环境执行
if [ -z "${CI:-}" ]; then
  LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  INSTALLED="/Applications/NSpace.app"

  # dump 的 path 行形如 "path:    /Applications/NSpace.app (0x7458)"：后缀要剥掉，
  # 且路径可能含空格（本项目目录就叫 "WorkBuddy AI"），所以不能用 awk '{print $2}'
  { "$LSREG" -dump 2>/dev/null | grep -E "^path:" | grep -i nspace \
      | sed -E 's/^path:[[:space:]]*//; s/[[:space:]]*\(0x[0-9a-fA-F]+\)[[:space:]]*$//' | sort -u || true; } \
    | while read -r p; do
        [ -d "$p" ] || "$LSREG" -u "$p" >/dev/null 2>&1 || true
      done

  # 双 NSpace 防护：build/ 副本与 /Applications 安装版同 bundle id（com.nspace.NSpace）、同版本，
  # 两份同时注册会让 Spotlight / 打开方式 / Launchpad 列出两个 NSpace，且点开启动的是哪份随机。
  # 已安装则只注册安装版；确需注册副本（如未安装时调试）设 REGISTER_BUILD=1。
  if [ -d "$INSTALLED" ] && [ "${REGISTER_BUILD:-0}" != "1" ]; then
    "$LSREG" -u "$APP" >/dev/null 2>&1 || true
    "$LSREG" -f "$INSTALLED" >/dev/null 2>&1 || true
    echo "✓ 检测到 $INSTALLED —— 跳过 build 副本注册（避免出现两个 NSpace；需注册副本请设 REGISTER_BUILD=1）"
  else
    "$LSREG" -f "$APP" >/dev/null 2>&1 || true
    echo "✓ LaunchServices 已清理死注册并注册 $APP"
  fi
fi
