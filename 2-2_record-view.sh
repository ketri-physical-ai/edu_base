#!/usr/bin/env bash
# 2-2 · 녹화 내용 확인 — 찍은 편을 브라우저에서 하나씩 본다.
#      사용법 :  edu2-2            실제 녹화본 전체
#                edu2-2 --test     연습 녹화본
#                edu2-2 5          5번 편만
#                edu2-2 3-6        3~6번 편
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

ROOT="$EDU_ROOT"; LABEL="실제 녹화본"
ARGS=()
for a in "$@"; do
  case "$a" in
    --test) ROOT="$EDU_TEST_ROOT"; LABEL="연습 녹화본" ;;
    -y|--yes) ;;
    *) ARGS+=("$a") ;;
  esac
done

if [[ ! -d "$ROOT" ]]; then
  echo "아직 녹화한 것이 없다: $ROOT" >&2
  echo "  → 먼저 edu2-1 이나 edu2-3 을 돌린다." >&2
  exit 1
fi

banner "2-2 · 녹화 내용 확인 — $LABEL" \
        "$ROOT" \
        "Chrome 탭이 열린다. 편마다 구간만 반복 재생된다."

VIEW_BASE="$(dirname "$ROOT")" \
  bash "$EDU_DIR/_view.sh" "$(basename "$ROOT")" "${ARGS[@]+"${ARGS[@]}"}"
