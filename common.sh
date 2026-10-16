#!/usr/bin/env bash
# 교육용 도구 공통부 — 설정을 읽고, 안전장치와 실행기를 제공한다.
# 이 파일을 직접 실행하지 않는다. 각 스크립트가 source 한다.

set -uo pipefail

EDU_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$EDU_DIR/config.sh"

EDU_CANCEL=42
trap 'echo; echo "중단됨 (Ctrl+C)"; exit 130' INT

# ── 파이썬 환경 ───────────────────────────────────────────────────
# shellcheck disable=SC1091
source "$EDU_DIR/_env.sh"
# 진단 도구(edu-set)는 환경을 못 잡아도 멈추지 않는다 — 그걸 알려주는 게 그 도구의 일이다.
if ! edu_activate; then
  [[ "${EDU_ENV_OPTIONAL:-0}" == "1" ]] || exit 1
  EDU_ENV_BAD=1
fi
command -v lerobot-record >/dev/null || \
  echo "  ⓘ lerobot 명령 없음 — 확인·판정만 가능, 녹화·학습 불가" >&2
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
      echo "포트 없음: $p" >&2
      echo "  붙어 있는 포트 :" >&2
      ls -1 /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | sed 's/^/    /' >&2 || echo "    (없음)" >&2
      echo "  → config.sh 의 FOLLOWER_PORT / LEADER_PORT 를 확인하세요." >&2
      exit 1
    fi
    if command -v lsof >/dev/null 2>&1 && [[ -n "$(lsof -t "$p" 2>/dev/null)" ]]; then
      echo "포트 사용 중: $p" >&2
      echo "  → 사용 중인 프로그램을 종료한 뒤 다시 실행하세요 (LeLab UI 도 포트를 사용합니다)." >&2
      exit "$EDU_CANCEL"
    fi
  done
}

# ── GPU 확인 ──────────────────────────────────────────────────────
gpu_guard() {
  if ! nvidia-smi >/dev/null 2>&1; then
    echo "nvidia-smi 실패 — GPU 상태 확인 불가" >&2
    echo "  GPU 상태를 확인할 수 없어 실행하지 않습니다." >&2
    exit 1
  fi
  local busy
  busy="$(pgrep -af 'lerobot-(train|rollout|record)' 2>/dev/null)"
  if [[ -n "$busy" ]]; then
    echo "⚠ GPU 사용 작업 실행 중 :" >&2
    printf '    %s\n' "$busy" >&2
    echo "  동시에 실행하면 진행 중인 학습이 중단될 수 있습니다." >&2
    read -r -p "계속할까요? [y/N] " a || exit "$EDU_CANCEL"
    [[ "$a" =~ ^[Yy]$ ]] || { echo "취소됨"; exit "$EDU_CANCEL"; }
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
    *) echo "안전 범위 밖 — 삭제 안 함: $real" >&2; return 1 ;;
  esac
  if [[ "$real" == "$home_real/data" || "$real" == "$home_real/outputs/train" ]]; then
    echo "상위 폴더 — 삭제 안 함: $real" >&2; return 1
  fi
  echo
  echo "── 이미 있는 $what ────────────────────────────────"
  echo "  $real"
  echo "  크기 : $(du -sh "$real" 2>/dev/null | cut -f1)"
  if [[ -f "$real/meta/info.json" ]]; then
    echo "  에피소드 : $(edu_meta "$real/meta/info.json" total_episodes)"
  fi
  echo "───────────────────────────────────────────────────"
  local prompt="[Y/n]"; [[ "$def" == "N" ]] && prompt="[y/N]"
  read -r -p "삭제하고 새로 시작할까요? $prompt " a || { echo "입력 없음 — 삭제 안 함" >&2; return 1; }
  [[ -z "$a" ]] && a="$def"
  if [[ "$a" =~ ^[Yy]$ ]]; then
    rm -rf -- "$real" && echo "삭제 완료: $real" && return 0
  fi
  echo "삭제 안 함"
  return 1
}

# ── 미리보기 → Y/n → 실행 ─────────────────────────────────────────
run_cmd() {
  echo
  echo "── 실행할 명령 ────────────────────────────────────"
  printf '  %s\n' "$@"
  echo "───────────────────────────────────────────────────"
  if [[ "${EDU_YES:-0}" != "1" ]]; then
    if ! read -r -p "실행? [Y/n] " a; then
      echo "입력 불가 — 실행 안 함. 터미널에서 직접 실행하세요." >&2
      exit 1
    fi
    [[ -z "$a" || "$a" =~ ^[Yy]$ ]] || { echo "취소됨"; exit "$EDU_CANCEL"; }
  fi
  # 명령 확인을 받은 뒤, 실행 직전에 한 번 더 알릴 것이 있으면 여기서 보여준다.
  # (녹화 중 조작법처럼 "읽고 시작해야 하는" 안내가 여기 온다)
  if [[ -n "${RUN_NOTICE:-}" ]]; then
    echo
    printf '%s\n' "$RUN_NOTICE"
    if [[ "${EDU_YES:-0}" != "1" ]]; then
      if ! read -r -p "  확인했으면 [Enter] · 취소 [q] : " a; then
        echo "입력 불가 — 실행 안 함" >&2; exit 1
      fi
      [[ "$a" =~ ^[qQ]$ ]] && { echo "취소됨"; exit "$EDU_CANCEL"; }
    fi
  fi

  # ⚠ conda 를 안 쓰는 PC(venv·시스템 파이썬)에는 CONDA_PREFIX 가 없다.
  #    무조건 참조하면 set -u 에서 "unbound variable" 로 **명령이 시작도 못 한다.**
  #    (torchcodec 이 ffmpeg 라이브러리를 찾게 하려는 것이니, 있을 때만 붙인다)
  local _cp="${CONDA_PREFIX:-}"
  if [[ -n "$_cp" && -d "$_cp/lib" ]]; then
    export LD_LIBRARY_PATH="$_cp/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
  # 출력 필터(RUN_FILTER) — 출력을 함수 하나에 통과시킨다. 에피소드 경계를 표시하는 데 쓴다.
  #   ⚠ 필터는 INT 를 무시한다. Ctrl+C 로 필터가 먼저 죽으면, 아직 영상을 저장 중인
  #      lerobot 이 broken pipe 를 맞는다. EOF 까지 받아 흘려보내야 한다.
  #   ⚠ 파이프에 물리면 파이썬 stdout 이 블록 버퍼가 되어 늦게 몰려 나온다.
  #      정작 중요한 줄(logging)은 stderr 라 줄 단위로 나오지만, 나머지도 맞춘다.
  #   ⚠ 종료코드는 파이프 맨 앞(=실제 명령) 것을 돌려준다. 필터 것이 아니다.
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

# ── 에피소드 경계 표시 ────────────────────────────────────────────
#   2-1 · 2-3 이 RUN_FILTER=rec_filter 로 지정하면 run_cmd 가 부른다. lerobot 출력을 통과시킨다.
#   ⚠ lerobot 이 낸 줄은 **하나도 지우지 않는다.** 경계에 표시만 얹는다.
#
#   경계 신호 (lerobot_record.py 의 실제 실행 순서)
#     Recording episode N    에피소드 시작.  N 이 직전과 같으면 재녹화,
#                            직전보다 크면 그때 비로소 직전 에피소드 저장이 확정된다
#     Reset the environment  녹화 끝·리셋 시작
#                            ⚠ 재녹화일 때도 뜬다 — 여기서 "저장" 을 단정하면 거짓말이 된다
#     Re-record episode      직전 에피소드 폐기 확정 (Reset **뒤**에 온다)
#     Stop recording         녹화 종료(2-3 은 세션 종료). 마지막 에피소드는 Reset 이 없어 여기서 닫힌다
#
#   ⚠ save_episode() 에는 로그가 없다. 그래서 저장 여부는 다음 에피소드 번호로만 안다.
rec_filter() {
  local line ep prev="" t0=$SECONDS dur i n msg pos
  local C1="" C2="" C3="" C0=""
  # 터미널이 아니면 색을 끈다 (로그 파일에 제어문자가 박히지 않게)
  if [[ -t 1 ]]; then C1=$'\033[1;36m'; C2=$'\033[1;33m'; C3=$'\033[1;32m'; C0=$'\033[0m'; fi
  local RULE="══════════════════════════════════════════════════════"
  while IFS= read -r line; do
    case "$line" in
      *"Recording episode "*)
        ep="${line##*Recording episode }"; ep="${ep%%[!0-9]*}"
        if [[ -n "$prev" ]]; then
          if [[ "$ep" == "$prev" ]]; then msg="폐기 (재녹화)"; else msg="저장됨"; fi
          printf '%s\n' "${C3}└─ ep ${prev} ${msg}${C0}"
        fi
        printf '\n%s\n' "${C1}${RULE}${C0}"
        if [[ "$ep" == "$prev" ]]; then
          printf '%s\n' "${C1}┌─ ↺ ep ${ep} 재녹화   (녹화 ${EPISODE_TIME_S:-?}초)${C0}"
        else
          n=$(( ${TO:-0} - ${FROM:-0} + 1 )); i=$(( ep - ${FROM:-0} + 1 ))
          # SNO(세션 번호)는 2-3 에만 있다. 2-1 은 진행 개수만 보인다.
          if [[ -n "${SNO:-}" ]]; then pos="S${SNO} ${i}/${n}   전체 ${ep}/${TOTAL:-?}"
          else                         pos="${i}/${n}"; fi
          printf '%s\n' "${C1}┌─ ● ep ${ep} 시작   ${pos}   (녹화 ${EPISODE_TIME_S:-?}초)${C0}"
        fi
        printf '%s\n' "${C1}${RULE}${C0}"
        prev="$ep"; t0=$SECONDS
        printf '%s\n' "$line"
        ;;
      *"Reset the environment"*)
        dur=$(( SECONDS - t0 ))
        printf '%s\n' "${C2}├─ ep ${prev} 녹화 종료 (${dur}초) · 리셋 ${RESET_TIME_S:-?}초 — 원통을 제자리로${C0}"
        printf '%s\n' "$line"
        ;;
      *"Re-record episode"*)
        printf '%s\n' "${C2}├─ ↺ 직전 에피소드 폐기${C0}"
        printf '%s\n' "$line"
        ;;
      *"Stop recording"*)
        [[ -n "$prev" ]] && printf '%s\n' "${C3}└─ ep ${prev} 저장됨${C0}"
        printf '\n%s\n' "${C1}${RULE}${C0}"
        if [[ -n "${SNO:-}" ]]; then printf '%s\n' "${C1}■ 세션 종료${C0}"
        else                         printf '%s\n' "${C1}■ 녹화 종료${C0}"; fi
        printf '%s\n'   "${C1}${RULE}${C0}"
        prev=""
        printf '%s\n' "$line"
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
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
