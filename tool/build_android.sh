#!/usr/bin/env bash
# 构建 Android release APK，自动读取根目录 .env.local 中的敏感配置
# 拼成 --dart-define 注入（不落源码、不上传 Git）。
#
# 用法：
#   bash tool/build_android.sh             # 正式构建
#   bash tool/build_android.sh --dry-run   # 仅打印将要注入的 defines，不构建
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 读取 .env.local（若存在），逐行解析 KEY=VALUE 生成 dart-define 数组
DEFINES=()
if [ -f "$ROOT/.env.local" ]; then
  while IFS='=' read -r _key _val; do
    case "$_key" in
      MOODIARY_*) DEFINES+=("-d$_key=$_val") ;;
    esac
  done < "$ROOT/.env.local"
fi

if [ "${1:-}" = "--dry-run" ]; then
  echo "Defines: ${DEFINES[*]:-(无 .env.local 或全部为空)}"
  exit 0
fi

echo "=== Building Android APK (release) ==="
flutter build apk --release "${DEFINES[@]}"
