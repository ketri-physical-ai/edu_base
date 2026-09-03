#!/usr/bin/env bash
# 교육용 도구 공통부 — 설정을 읽고, 안전장치와 실행기를 제공한다.
# 이 파일을 직접 실행하지 않는다. 각 스크립트가 source 한다.

set -uo pipefail

EDU_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$EDU_DIR/config.sh"

EDU_CANCEL=42
trap 'echo; echo "중단했다 (Ctrl+C)."; exit 130' INT

# ── 파이썬 환경 ───────────────────────────────────────────────────
# shellcheck disable=SC1091
source "$EDU_DIR/_env.sh"
# 진단 도구(edu-set)는 환경을 못 잡아도 멈추지 않는다 — 그걸 알려주는 게 그 도구의 일이다.
if ! edu_activate; then
  [[ "${EDU_ENV_OPTIONAL:-0}" == "1" ]] || exit 1
  EDU_ENV_BAD=1
fi
command -v lerobot-record >/dev/null || \
  echo "  ⓘ lerobot 명령이 PATH 에 없다 — 보기·판정은 되지만 녹화·학습은 안 된다." >&2
export HF_LEROBOT_HOME="$LEROBOT_HOME"

# meta/info.json 에서 값을 읽는다.
#   ⚠ grep 으로 긁으면 그 키가 **마지막**일 때 값에 `}` 가 붙어 계산이 깨진다
#      (진행도가 "-" 로 나오던 원인). JSON 은 JSON 으로 읽는다.
edu_meta() {   # edu_meta <info.json> <키>  →  없으면 0
  python3 -c "import json,sys
try:
    print(json.load(open(sys.argv[1])).get(sys.argv[2], 0))
except Exception:
    print(0)" "$1" "$2" 2>/dev/null || echo 0
}

# ── 제목 ──────────────────────────────────────────────────────────
banner() {
  echo
  echo "══════════════════════════════════════════════════════"
  printf '  %s\n' "$@"
  echo "══════════════════════════════════════════════════════"
}

# ── 포트 확인 ─────────────────────────────────────────────────────
need_ports() {
  local p
  for p in "$@"; do
    if [[ ! -e "$p" ]]; then
      echo "포트가 없다: $p" >&2
      echo "  붙어 있는 포트 :" >&2
      ls -1 /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | sed 's/^/    /' >&2 || echo "    (없음)" >&2
      echo "  → config.sh 의 FOLLOWER_PORT / LEADER_PORT 를 고친다." >&2
      exit 1
    fi
    if command -v lsof >/dev/null 2>&1 && [[ -n "$(lsof -t "$p" 2>/dev/null)" ]]; then
      echo "이미 다른 프로그램이 쓰는 중이다: $p" >&2
      echo "  → 먼저 그 창을 끝낸다 (LeLab UI 도 포트를 잡는다)." >&2
      exit "$EDU_CANCEL"
    fi
  done
}

# ── GPU 확인 ──────────────────────────────────────────────────────
gpu_guard() {
  if ! nvidia-smi >/dev/null 2>&1; then
    echo "nvidia-smi 가 실패했다 — GPU 상태를 확인할 수 없다." >&2
    echo "  '안 돌고 있다' 가 아니라 '확인 못 함' 이므로 진행하지 않는다." >&2
    exit 1
  fi
  local busy
  busy="$(pgrep -af 'lerobot-(train|rollout|record)' 2>/dev/null)"
  if [[ -n "$busy" ]]; then
    echo "⚠ GPU 를 쓰는 작업이 이미 돌고 있다 :" >&2
    printf '    %s\n' "$busy" >&2
    echo "  같이 띄우면 돌던 학습이 죽는다." >&2
    read -r -p "그래도 진행할까? [y/N] " a || exit "$EDU_CANCEL"
    [[ "$a" =~ ^[Yy]$ ]] || { echo "취소했다."; exit "$EDU_CANCEL"; }
  fi
}

# ── 지우기 (미리보기 → Y/n) ───────────────────────────────────────
# ask_delete <경로> [설명] [기본답: Y|N]  — 기본 Y. 되돌리기 어려운 자리는 N 을 준다.
ask_delete() {
  local target="$1" what="${2:-폴더}" def="${3:-Y}" real
  [[ -e "$target" ]] || return 0
  real="$(readlink -f "$target")"
  # 접두어 완전일치 + 최소 한 단계 하위. 상위 디렉터리 자체는 절대 안 지운다.
  # ⚠ LEROBOT_HOME 도 실경로로 풀어서 비교한다 — 기본 경로(~/.cache/...)가
  #    프로젝트로 걸린 심링크일 때 대상만 풀면 영영 안 맞아 아무것도 못 지운다.
  local home_real; home_real="$(readlink -f "$LEROBOT_HOME")"
  case "$real" in
    "$home_real"/data/?*|"$home_real"/outputs/train/?*) ;;
    *) echo "안전 범위 밖이라 손대지 않는다: $real" >&2; return 1 ;;
  esac
  if [[ "$real" == "$home_real/data" || "$real" == "$home_real/outputs/train" ]]; then
    echo "상위 디렉터리는 지우지 않는다: $real" >&2; return 1
  fi
  echo
  echo "── 이미 있는 $what ────────────────────────────────"
  echo "  $real"
  echo "  크기 : $(du -sh "$real" 2>/dev/null | cut -f1)"
  if [[ -f "$real/meta/info.json" ]]; then
    echo "  편수 : $(edu_meta "$real/meta/info.json" total_episodes)"
  fi
  echo "───────────────────────────────────────────────────"
  local prompt="[Y/n]"; [[ "$def" == "N" ]] && prompt="[y/N]"
  read -r -p "지우고 새로 시작할까? $prompt " a || { echo "입력을 못 받았다 — 지우지 않았다." >&2; return 1; }
  [[ -z "$a" ]] && a="$def"
  if [[ "$a" =~ ^[Yy]$ ]]; then
    rm -rf -- "$real" && echo "지웠다: $real" && return 0
  fi
  echo "그대로 두었다."
  return 1
}

# ── 미리보기 → Y/n → 실행 ─────────────────────────────────────────
run_cmd() {
  echo
  echo "── 실행할 명령 ────────────────────────────────────"
  printf '  %s\n' "$@"
  echo "───────────────────────────────────────────────────"
  if [[ "${EDU_YES:-0}" != "1" ]]; then
    if ! read -r -p "실행하나? [Y/n] " a; then
      echo "입력을 받을 수 없다 — 실행하지 않았다. 터미널에서 직접 실행한다." >&2
      exit 1
    fi
    [[ -z "$a" || "$a" =~ ^[Yy]$ ]] || { echo "취소했다."; exit "$EDU_CANCEL"; }
  fi
  # 명령 확인을 받은 뒤, 실행 직전에 한 번 더 알릴 것이 있으면 여기서 보여준다.
  # (녹화 중 조작법처럼 "읽고 시작해야 하는" 안내가 여기 온다)
  if [[ -n "${RUN_NOTICE:-}" ]]; then
    echo
    printf '%s\n' "$RUN_NOTICE"
    if [[ "${EDU_YES:-0}" != "1" ]]; then
      if ! read -r -p "  확인했으면 [Enter] · [q] 취소 : " a; then
        echo "입력을 받을 수 없다 — 실행하지 않았다." >&2; exit 1
      fi
      [[ "$a" =~ ^[qQ]$ ]] && { echo "취소했다."; exit "$EDU_CANCEL"; }
    fi
  fi

  # ⚠ conda 를 안 쓰는 PC(venv·시스템 파이썬)에는 CONDA_PREFIX 가 없다.
  #    무조건 참조하면 set -u 에서 "unbound variable" 로 **명령이 시작도 못 한다.**
  #    (torchcodec 이 ffmpeg 라이브러리를 찾게 하려는 것이니, 있을 때만 붙인다)
  local _cp="${CONDA_PREFIX:-}"
  if [[ -n "$_cp" && -d "$_cp/lib" ]]; then
    export LD_LIBRARY_PATH="$_cp/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
  # 걸개(RUN_FILTER) — 출력을 함수 하나에 통과시킨다. 편 사이 경계를 찍는 데 쓴다.
  #   ⚠ 걸개는 INT 를 무시한다. Ctrl+C 로 걸개가 먼저 죽으면, 아직 영상을 저장 중인
  #      lerobot 이 broken pipe 를 맞는다. EOF 까지 받아 흘려보내야 한다.
  #   ⚠ 파이프에 물리면 파이썬 stdout 이 블록 버퍼가 되어 늦게 몰려 나온다.
  #      정작 중요한 줄(logging)은 stderr 라 줄 단위로 나오지만, 나머지도 맞춘다.
  #   ⚠ 종료코드는 파이프 맨 앞(=실제 명령) 것을 돌려준다. 걸개 것이 아니다.
  if [[ -n "${RUN_FILTER:-}" ]]; then
    if [[ -n "${EDU_LOG:-}" ]]; then
      PYTHONUNBUFFERED=1 "$@" 2>&1 | { trap "" INT; "$RUN_FILTER"; } | tee -a "$EDU_LOG"
    else
      PYTHONUNBUFFERED=1 "$@" 2>&1 | { trap "" INT; "$RUN_FILTER"; }
    fi
    return "${PIPESTATUS[0]}"
  fi
  if [[ -n "${EDU_LOG:-}" ]]; then
    "$@" 2>&1 | tee -a "$EDU_LOG"
    return "${PIPESTATUS[0]}"
  fi
  "$@"
}

# ── -y / --yes 를 걷어내고 나머지는 EXTRA 로 ──────────────────────
EXTRA=()
parse_args() {
  local a
  for a in "$@"; do
    case "$a" in
      -y|--yes) EDU_YES=1 ;;
      *) EXTRA+=("$a") ;;
    esac
  done
}
