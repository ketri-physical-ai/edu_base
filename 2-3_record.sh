#!/usr/bin/env bash
# 2-3 · 실제 녹화 — 10편씩 묶어 찍고, 묶음이 끝날 때마다 확인한다.
#
#   묶음 하나가 끝나면 :  뷰어가 뜬다 → 이상한 판이 표시된다 → 지울 번호를 넣는다
#                        → 미리보기 → 확인 → 지운다 → 다음 묶음
#
#   이미 찍힌 데이터셋이면 **자동으로 이어 찍는다.** 지우자고 묻지 않는다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

# 녹화 중 Ctrl+C 는 즉시 끝내지 않는다 — lerobot 이 영상을 마저 저장해야 한다.
#   common.sh 의 기본 트랩은 exit 130 이라, 저장이 끝나기 전에 셸이 먼저 죽는다.
#   (2-1 연습본에는 이 보호가 있었는데 진짜 데이터를 찍는 여기엔 없었다)
trap 'echo; echo "중단 신호 — lerobot 이 저장을 마칠 때까지 기다린다. 창을 닫지 마라."' INT

SES="${SESSION_SIZE:-10}"
TOTAL="$NUM_EPISODES"
NSES=$(( (TOTAL + SES - 1) / SES ))

have_eps() {   # 지금까지 찍힌 편수
  [[ -f "$EDU_ROOT/meta/info.json" ]] || { echo 0; return; }
  edu_meta "$EDU_ROOT/meta/info.json" total_episodes
}

# ── 상태표 ────────────────────────────────────────────────────────
#   녹화 : 그 묶음이 몇 % 찼나      상태 : V 완료 · ⚠ 주의 · ·· 찍는 중 · [] 없음
board() {
  local have="$1" flagged="${2:-}"
  local i s e st line1="" line2="" line3=""
  for ((i=1; i<=NSES; i++)); do
    s=$(( (i-1)*SES )); e=$(( s + SES - 1 ))
    (( e > TOTAL-1 )) && e=$(( TOTAL-1 ))
    local n=$(( e - s + 1 )) got=$(( have - s ))
    (( got < 0 )) && got=0; (( got > n )) && got=$n
    if   (( got == 0 ));  then st="[]"
    elif (( got < n ));   then st="··"
    elif _has_flag "$s" "$e" "$flagged"; then st="⚠"
    elif _has_flag "$s" "$e" "$NOTED";   then st="?"
    else st="V"
    fi
    line1+=$(printf '%-5s' "S$i")
    line2+=$(printf '%-5s' "$got")
    # printf 는 바이트로 폭을 세서 한글·기호가 밀린다 — 칸을 직접 채운다.
    case "$st" in
      "⚠")  line3+="⚠   " ;;
      "··") line3+="··   " ;;
      *)     line3+=$(printf '%-5s' "$st") ;;
    esac
  done
  printf '      %s\n' "$line1"
  printf '  녹화 %s\n' "$line2"
  printf '  상태 %s\n' "$line3"
  echo "──────────────────────────────────────────────────────"
}
_has_flag() {  # 묶음 범위 안에 표시된 판이 있나
  local s="$1" e="$2" f="$3" x
  [[ -z "$f" ]] && return 1
  for x in ${f//,/ }; do (( x >= s && x <= e )) && return 0; done
  return 1
}

header() {
  local have="$1" flagged="${2:-}"
  local pct=$(( TOTAL > 0 ? have * 100 / TOTAL : 0 ))
  echo
  echo "══════════════════════════════════════════════════════"
  echo " 2-3 · 실제 녹화 (${TOTAL}편)"
  echo "──────────────────────────────────────────────────────"
  echo "  데이터셋 : $EDU_REPO_ID  (${have}/${TOTAL}) ${pct}%"
  echo "──────────────────────────────────────────────────────"
  board "$have" "$flagged"
  echo "  표기  V 완료   ⚠ 오류   ? 확인   ·· 찍는 중   [] 없음   (한 묶음 ${SES}편)"
  echo "──────────────────────────────────────────────────────"
  echo "    녹화시간 ${EPISODE_TIME_S}초 · 대기시간 ${RESET_TIME_S}초"
  echo "══════════════════════════════════════════════════════"
}

# 명령 확인을 받은 뒤, 녹화가 시작되기 직전에 뜬다 (common.sh 의 run_cmd 가 쓴다)
RUN_NOTICE="──────────────────────────────────────────────────────
  녹화 중 조작
    →      한 편 일찍 끝내기
    ←      다시 찍기
    ESC    메뉴로
──────────────────────────────────────────────────────"

# ── 편 사이 경계 표시 ─────────────────────────────────────────────
#   common.sh 의 run_cmd 가 RUN_FILTER 로 부른다. lerobot 출력을 통과시킨다.
#   ⚠ lerobot 이 낸 줄은 **하나도 지우지 않는다.** 경계에 표시만 얹는다.
#
#   경계 신호 (lerobot_record.py 의 실제 실행 순서)
#     Recording episode N    편 시작.  N 이 직전과 같으면 재녹화,
#                            직전보다 크면 그때 비로소 직전 편 저장이 확정된다
#     Reset the environment  녹화 끝·리셋 시작
#                            ⚠ 재녹화일 때도 뜬다 — 여기서 "저장" 을 단정하면 거짓말이 된다
#     Re-record episode      직전 편 폐기 확정 (Reset **뒤**에 온다)
#     Stop recording         묶음 끝. 마지막 편은 Reset 이 없어 여기서 닫힌다
#
#   ⚠ save_episode() 에는 로그가 없다. 그래서 저장 여부는 다음 편 번호로만 안다.
RUN_FILTER=rec_filter
rec_filter() {
  local line ep prev="" t0=$SECONDS dur i n msg
  local C1="" C2="" C3="" C0=""
  # 터미널이 아니면 색을 끈다 (로그 파일에 제어문자가 박히지 않게)
  if [[ -t 1 ]]; then C1=$'\033[1;36m'; C2=$'\033[1;33m'; C3=$'\033[1;32m'; C0=$'\033[0m'; fi
  local RULE="══════════════════════════════════════════════════════"
  while IFS= read -r line; do
    case "$line" in
      *"Recording episode "*)
        ep="${line##*Recording episode }"; ep="${ep%%[!0-9]*}"
        if [[ -n "$prev" ]]; then
          if [[ "$ep" == "$prev" ]]; then msg="버렸다 (재녹화)"; else msg="저장됨"; fi
          printf '%s\n' "${C3}└─ ep ${prev} ${msg}${C0}"
        fi
        printf '\n%s\n' "${C1}${RULE}${C0}"
        if [[ "$ep" == "$prev" ]]; then
          printf '%s\n' "${C1}┌─ ↺ ep ${ep} 다시 찍는다   (녹화 ${EPISODE_TIME_S:-?}초)${C0}"
        else
          n=$(( ${TO:-0} - ${FROM:-0} + 1 )); i=$(( ep - ${FROM:-0} + 1 ))
          printf '%s\n' "${C1}┌─ ● ep ${ep} 시작   S${SNO:-?} ${i}/${n}   전체 ${ep}/${TOTAL:-?}   (녹화 ${EPISODE_TIME_S:-?}초)${C0}"
        fi
        printf '%s\n' "${C1}${RULE}${C0}"
        prev="$ep"; t0=$SECONDS
        printf '%s\n' "$line"
        ;;
      *"Reset the environment"*)
        dur=$(( SECONDS - t0 ))
        printf '%s\n' "${C2}├─ ep ${prev} 녹화 끝 (${dur}초) · 리셋 ${RESET_TIME_S:-?}초 — 원통을 제자리로${C0}"
        printf '%s\n' "$line"
        ;;
      *"Re-record episode"*)
        printf '%s\n' "${C2}├─ ↺ 직전 편을 버린다${C0}"
        printf '%s\n' "$line"
        ;;
      *"Stop recording"*)
        [[ -n "$prev" ]] && printf '%s\n' "${C3}└─ ep ${prev} 저장됨${C0}"
        printf '\n%s\n' "${C1}${RULE}${C0}"
        printf '%s\n'   "${C1}■ 묶음 끝${C0}"
        printf '%s\n'   "${C1}${RULE}${C0}"
        prev=""
        printf '%s\n' "$line"
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}

# rt <녹화초> <대기초> — 그 자리에서 시간을 바꾼다 (이번 실행에만 적용)
set_rt() {
  local a="${1:-}" b="${2:-}"
  if [[ ! "$a" =~ ^[0-9]+$ || ! "$b" =~ ^[0-9]+$ ]]; then
    echo "  숫자 두 개를 준다 —  rt 25 8" >&2; return 1
  fi
  if (( a < 1 || a > 300 || b < 0 || b > 120 )); then
    echo "  범위를 벗어났다 (녹화 1~300초 · 대기 0~120초)" >&2; return 1
  fi
  EPISODE_TIME_S="$a"; RESET_TIME_S="$b"
  echo "  바꿨다 — 녹화 ${a}초 · 대기 ${b}초"
  return 0
}

NOTED=""
scan_flags() {   # 전체를 훑어 오류 번호를 돌려주고, 참고 번호는 NOTED 에 담는다
  [[ -f "$EDU_ROOT/meta/info.json" ]] || { NOTED=""; return; }
  local out; out="$(bash "$EDU_DIR/_scan.sh" "$EDU_ROOT" 2>/dev/null)"
  NOTED="$(echo "$out" | sed -n 's/^NOTED=//p')"
  echo "$out" | sed -n 's/^FLAGGED=//p'
}

# ── 확인 → 지우기 ─────────────────────────────────────────────────
#   $1,$2 = 볼 범위(비우면 전체). 뷰어를 띄우고, 화면에도 표시하고,
#   지울 번호를 받아 _drop.sh 로 넘긴다. **여기서 직접 지우지 않는다.**
review() {
  local lo="${1:-}" hi="${2:-}" rng=() scan sug del
  [[ -n "$lo" ]] && rng=("${lo}-${hi}")
  VIEW_BASE="$(dirname "$EDU_ROOT")" \
    bash "$EDU_DIR/_view.sh" "$(basename "$EDU_ROOT")" "${rng[@]+"${rng[@]}"}" || true
  scan="$(bash "$EDU_DIR/_scan.sh" "$EDU_ROOT" ${lo:+"$lo" "$hi"} 2>/dev/null)"
  echo "$scan" | grep -v '^FLAGGED='
  sug="$(echo "$scan" | sed -n 's/^FLAGGED=//p')"
  echo
  if [[ -n "$sug" ]]; then
    echo "  ⚠ 오류로 잡힌 판 : $sug   ← 이대로 넣으면 지운다"
    echo "    (? 확인 로 잡힌 판은 영상을 보고 직접 고른다)"
  fi
  read -r -p "  지울 판 번호 [엔터=그냥 두기] : " del || return 0
  del="${del//[[:space:]]/}"
  [[ -z "$del" ]] && return 0
  DROP_BASE="$(dirname "$EDU_ROOT")" LIST_LO="$lo" LIST_HI="$hi" \
    bash "$EDU_DIR/_drop.sh" "$(basename "$EDU_ROOT")" "$del" || echo "  지우지 않았다."
}

# ── 묶음 고르기 → 확인 ────────────────────────────────────────────
pick_review() {
  local have="$1" flagged="$2" i s e n got st ans
  echo
  echo "  ── 어느 묶음을 볼까 ────────────────────────────"
  for ((i=1; i<=NSES; i++)); do
    s=$(( (i-1)*SES )); e=$(( s + SES - 1 ))
    (( e > TOTAL-1 )) && e=$(( TOTAL-1 ))
    n=$(( e - s + 1 )); got=$(( have - s ))
    (( got < 0 )) && got=0; (( got > n )) && got=$n
    (( got == 0 )) && continue
    if _has_flag "$s" "$e" "$flagged"; then st="⚠ 주의"
    elif (( got < n ));                  then st="·· 찍는 중"
    else                                      st="V 완료"
    fi
    printf '    S%-3d ep %d~%d   %d편   %s\n' "$i" "$s" "$((s+got-1))" "$got" "$st"
  done
  echo "    a    전체"
  echo "  ────────────────────────────────────────────────"
  read -r -p "  → " ans || return 0
  ans="${ans//[[:space:]]/}"
  case "$ans" in
    ""|q|Q) return 0 ;;
    a|A) review ;;
    [sS][0-9]*|[0-9]*)
      local no="${ans#[sS]}"
      [[ "$no" =~ ^[0-9]+$ ]] || { echo "  S1 ~ S${NSES} 또는 a 를 준다."; return 0; }
      (( no >= 1 && no <= NSES )) || { echo "  S1 ~ S${NSES} 또는 a 를 준다."; return 0; }
      local lo=$(( (no-1)*SES )) hi=$(( no*SES - 1 ))
      (( hi > have-1 )) && hi=$(( have-1 ))
      (( lo > hi )) && { echo "  그 묶음은 아직 비어 있다."; return 0; }
      review "$lo" "$hi" ;;
    *) echo "  S1 ~ S${NSES} 또는 a 를 준다." ;;
  esac
}

FLAGGED="$(scan_flags)"
HAVE="$(have_eps)"
header "$HAVE" "$FLAGGED"

if (( HAVE >= TOTAL )); then
  echo
  echo "  ${TOTAL}편을 다 찍었다."
  [[ -n "$FLAGGED" ]] && echo "  ⚠ 다시 볼 판 : $FLAGGED   →  edu2-2 로 확인한다."
  echo "  더 찍으려면 :  NUM_EPISODES=$((TOTAL+SES)) edu2-3"
  exit 0
fi

need_ports "$FOLLOWER_PORT" "$LEADER_PORT"

# 지금 편수(HAVE)로부터 이번에 찍을 묶음을 정한다.
#   ⚠ 묶음이 덜 찼으면 **모자란 만큼만** 찍는다. 매번 SES 편을 찍으면
#      S1 에 14편이 들어가는 식으로 묶음 경계가 어긋난다.
next_session() {
  SNO=$(( HAVE / SES + 1 ))
  N=$(( SES - HAVE % SES ))
  (( N > TOTAL - HAVE )) && N=$(( TOTAL - HAVE ))
  FROM=$HAVE; TO=$(( HAVE + N - 1 ))
}

# ── 묶음 반복 ─────────────────────────────────────────────────────
while (( HAVE < TOTAL )); do
  next_session

  echo
  echo "▶ S${SNO} — ${N}편 (ep ${FROM}~${TO})"

  # 시작 전 : 엔터로 바로 시작하거나, rt 로 시간을 바꾸거나, q 로 그만둔다
  while true; do
    echo "  [Enter] 시작          [v]  영상 확인"
    echo "  [rt] 시간 변경        [q] 종료"
    if ! read -r -p "  → " ANS; then ANS="q"; fi
    case "$ANS" in
      ""|y|Y|Y*) break ;;
      q|Q) echo "  여기서 멈춘다. 이어 찍으려면 :  edu2-3"; exit 0 ;;
      v|V)
        if [[ -f "$EDU_ROOT/meta/info.json" ]]; then
          pick_review "$HAVE" "$FLAGGED"
          HAVE="$(have_eps)"; FLAGGED="$(scan_flags)"
          header "$HAVE" "$FLAGGED"
          next_session
        else
          echo "  아직 찍은 것이 없다."
        fi
        echo; echo "▶ S${SNO} — ${N}편 (ep ${FROM}~${TO})"
        ;;
      rt|RT)
        echo "  시간입력  —    25 8   (녹화 25초 대기 8초)"
        if read -r -p "  → " RTA; then
          # shellcheck disable=SC2086
          set -- $RTA
          if [[ -n "${1:-}" ]]; then
            set_rt "${1:-}" "${2:-}" && { header "$HAVE" "$FLAGGED"
                                          echo; echo "▶ S${SNO} — ${N}편 (ep ${FROM}~${TO})"; }
          fi
        fi
        ;;
      rt\ *|RT\ *)
        # shellcheck disable=SC2086
        set -- $ANS; shift
        set_rt "${1:-}" "${2:-}" && { header "$HAVE" "$FLAGGED"
                                      echo; echo "▶ S${SNO} — ${N}편 (ep ${FROM}~${TO})"; }
        ;;
      *) echo "  엔터 · rt · q 중 하나를 준다." ;;
    esac
  done

  RES=()
  # 폴더만 있고 meta 가 없으면 데이터셋이 아니다 — 그때 --resume 을 붙이면 죽는다.
  [[ -f "$EDU_ROOT/meta/info.json" ]] && RES=(--resume=true)

  run_cmd lerobot-record \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID" \
    --robot.cameras="$CAMERAS" \
    --teleop.type=so101_leader \
    --teleop.port="$LEADER_PORT" \
    --teleop.id="$LEADER_ID" \
    --display_data="$DISPLAY_DATA" \
    --dataset.repo_id="$EDU_REPO_ID" \
    --dataset.root="$EDU_ROOT" \
    --dataset.push_to_hub=false \
    --dataset.fps="$CAM_FPS" \
    --dataset.num_episodes="$N" \
    --dataset.single_task="$TASK" \
    --dataset.episode_time_s="$EPISODE_TIME_S" \
    --dataset.reset_time_s="$RESET_TIME_S" \
    "${RES[@]+"${RES[@]}"}" "${EXTRA[@]+"${EXTRA[@]}"}"
  rc=$?
  NEW="$(have_eps)"
  # ESC 로 끊어도 찍힌 데까지는 살아 있다 — 그건 오류가 아니라 「메뉴로」다.
  # 한 편도 안 늘었는데 실패한 경우에만 진짜 오류로 본다.
  if (( rc != 0 )) && (( NEW <= HAVE )); then
    echo; echo "녹화가 시작되지 못했다 (코드 $rc)."; exit "$rc"
  fi
  (( rc == 0 )) || echo "  중간에 끊겼다 — 찍힌 ${NEW}편까지 확인한다."

  # ── 확인 : 뷰어 + 화면 표시 ────────────────────────────────────
  echo
  echo "── S${SNO} 확인 ────────────────────────────────────────"
  review "$FROM" "$((NEW-1))"
  HAVE="$(have_eps)"

  FLAGGED="$(scan_flags)"
  header "$HAVE" "$FLAGGED"
done

echo
echo "찍은 것을 보려면 :  edu2-2"
echo "학습을 걸려면   :  edu3-1"
