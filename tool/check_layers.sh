#!/bin/bash
# 分层约束校验。CI 与 PostToolUse hook 共用。
#
# 依赖方向（只能自上而下）：
#   features / providers  →  services  →  data/repository  →  data/datasource
#                                      ↘  domain / dto / blockchain / enums / constants
#   core 谁都能用，但 core 不许用任何人
#
# 用法：tool/check_layers.sh [文件...]    不带参数则全量扫描 lib/
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=; YEL=; GRN=; DIM=; OFF=; }
fail=0

# 只校验传入文件中属于 lib/ 的 dart 文件；无参数则全量。
targets=()
if [ $# -gt 0 ]; then
  for f in "$@"; do
    case "$f" in
      */lib/*.dart|lib/*.dart) targets+=("${f#"$PWD"/}") ;;
    esac
  done
  [ ${#targets[@]} -eq 0 ] && exit 0
else
  while IFS= read -r f; do targets+=("$f"); done < <(find lib -name '*.dart')
fi

report() {  # report <严重度> <规则> <文件:行> <内容>
  local sev=$1 rule=$2 loc=$3 line=$4
  local c=$RED; [ "$sev" = warn ] && c=$YEL
  printf '%s%s%s %s\n  %s%s%s\n  %s%s%s\n' \
    "$c" "[$sev]" "$OFF" "$rule" "$DIM" "$loc" "$OFF" "$DIM" "$line" "$OFF"
  [ "$sev" = error ] && fail=1
  return 0
}

# —— 规则 1：core 不许依赖任何业务层 ——
# core 是纯基础设施，必须能被任何人依赖而不产生环。
BIZ='domain|blockchain|enums|services|providers|features|widgets|constants|data|dto'
for f in "${targets[@]}"; do
  case "$f" in lib/core/*) ;; *) continue ;; esac
  while IFS=: read -r n line; do
    [ -n "$n" ] && report error "core 不得依赖业务层（core 只能被依赖）" "$f:$n" "$line"
  done < <(grep -nE "^import '(\.\./)*($BIZ)/" "$f")
done

# —— 规则 2：datasource 不许反向依赖上层 ——
for f in "${targets[@]}"; do
  case "$f" in lib/data/datasource/*) ;; *) continue ;; esac
  while IFS=: read -r n line; do
    [ -n "$n" ] && report error "datasource 不得依赖 repository/providers/features" "$f:$n" "$line"
  done < <(grep -nE "^import '.*(repository|providers|features)/" "$f")
done

# —— 规则 3：data 层不许依赖 UI ——
for f in "${targets[@]}"; do
  case "$f" in lib/data/*) ;; *) continue ;; esac
  while IFS=: read -r n line; do
    [ -n "$n" ] && report error "data 层不得依赖 features（UI）" "$f:$n" "$line"
  done < <(grep -nE "^import '.*features/" "$f")
done

# —— 规则 4：provider body 内取依赖要用 ref.watch ——
# ref.read 不建立依赖边：上游被 override / invalidate 时本 provider 不会重建。
# 事件回调里的 ref.read 是对的，所以只看顶层 provider 声明块内部。
for f in "${targets[@]}"; do
  while IFS=: read -r n line; do
    [ -n "$n" ] && report warn "provider body 内应使用 ref.watch 而非 ref.read" "$f:$n" "$line"
  done < <(awk '
    # 顶层 provider 声明开始
    /^final [A-Za-z_][0-9A-Za-z_]*[Pp]rovider[0-9A-Za-z_]* *=/ { inblk=1 }
    # 类定义强制结束——Notifier 类的方法体内 ref.read 是合法的（事件动作，非依赖装配）
    /^class / { inblk=0 }
    inblk && /ref\.read\(/ { printf "%d:%s\n", NR, $0 }
    # 块结束：顶格（无缩进）且以 ); 收尾的行
    inblk && /^[^ \t].*\);[ \t]*$/ { inblk=0 }
  ' "$f")
done

if [ $fail -eq 0 ]; then
  printf '%s✓ 分层校验通过%s (%d 个文件)\n' "$GRN" "$OFF" "${#targets[@]}"
else
  printf '\n%s分层校验失败。%s依赖方向见本脚本头部注释。\n' "$RED" "$OFF"
fi
exit $fail
