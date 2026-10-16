#!/usr/bin/env bash
# 2-3 · 실제 녹화 — 세션당 에피소드 10개씩 녹화하고, 세션이 끝날 때마다 확인한다.
#
#   세션 하나가 끝나면 :  뷰어가 뜬다 → 이상 에피소드가 표시된다 → 지울 번호를 넣는다
#                        → 미리보기 → 확인 → 삭제 → 다음 세션
#
#   기존 데이터셋이 있으면 **자동으로 이어서 녹화한다.** 삭제 여부를 묻지 않는다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

# 녹화 중 Ctrl+C 는 즉시 끝내지 않는다 — lerobot 이 영상을 마저 저장해야 한다.
#   common.sh 의 기본 트랩은 exit 130 이라, 저장이 끝나기 전에 셸이 먼저 죽는다.
#   (2-1 연습 녹화에는 이 보호가 있었는데 실제 녹화인 여기엔 없었다)
trap 'echo; echo "중단 요청됨 — 저장 중입니다. 완료될 때까지 터미널을 닫지 마세요."' INT

SES="${SESSION_SIZE:-10}"
TOTAL="$NUM_EPISODES"
NSES=$(( (TOTAL + SES - 1) / SES ))

have_eps() {   # 지금까지 녹화된 에피소드 수
  [[ -f "$EDU_ROOT/meta/info.json" ]] || { echo 0; return; }
  edu_meta "$EDU_ROOT/meta/info.json" total_episodes
}

# ── 상태표 ────────────────────────────────────────────────────────
#   녹화 : 그 세션이 몇 % 찼나      상태 : V 완료 · ⚠ 주의 · ·· 녹화 중 · [] 없음
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
_has_flag() {  # 세션 범위 안에 표시된 에피소드가 있나
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
  echo " 2-3 · 실제 녹화 (에피소드 ${TOTAL}개)"
  echo "──────────────────────────────────────────────────────"
  echo "  데이터셋 : $EDU_REPO_ID  (${have}/${TOTAL}) ${pct}%"
  echo "──────────────────────────────────────────────────────"
  board "$have" "$flagged"
  echo "  표기  V 완료   ⚠ 오류   ? 확인   ·· 녹화 중   [] 없음   (세션당 ${SES}개)"
  echo "──────────────────────────────────────────────────────"
  echo "    녹화시간 ${EPISODE_TIME_S}초 · 대기시간 ${RESET_TIME_S}초"
  echo "══════════════════════════════════════════════════════"
}

# 명령 확인을 받은 뒤, 녹화가 시작되기 직전에 뜬다 (common.sh 의 run_cmd 가 쓴다)
RUN_NOTICE="──────────────────────────────────────────────────────
  녹화 중 조작
    →      현재 에피소드 조기 종료
    ←      현재 에피소드 재녹화
    ESC    메뉴로
──────────────────────────────────────────────────────"

# 에피소드 경계 표시 — rec_filter 는 common.sh 에 있다 (2-1 과 같은 형태)
RUN_FILTER=rec_filter

# rt <녹화초> <대기초> — 그 자리에서 시간을 바꾼다 (이번 실행에만 적용)
set_rt() {
  local a="${1:-}" b="${2:-}"
  if [[ ! "$a" =~ ^[0-9]+$ || ! "$b" =~ ^[0-9]+$ ]]; then
    echo "  숫자 두 개를 입력하세요 (예: rt 25 8)" >&2; return 1
  fi
  if (( a < 1 || a > 300 || b < 0 || b > 120 )); then
    echo "  범위 초과 (녹화 1~300초 · 대기 0~120초)" >&2; return 1
  fi
  EPISODE_TIME_S="$a"; RESET_TIME_S="$b"
  echo "  변경됨 — 녹화 ${a}초 · 대기 ${b}초"
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
    echo "  ⚠ 오류 에피소드 : $sug   ← 이 번호를 입력하면 삭제됩니다"
    echo "    (? 확인 에피소드는 영상을 보고 직접 선택하세요)"
  fi
  read -r -p "  삭제할 에피소드 번호 [Enter=건너뛰기] : " del || return 0
  del="${del//[[:space:]]/}"
  [[ -z "$del" ]] && return 0
  DROP_BASE="$(dirname "$EDU_ROOT")" LIST_LO="$lo" LIST_HI="$hi" \
    bash "$EDU_DIR/_drop.sh" "$(basename "$EDU_ROOT")" "$del" || echo "  삭제 안 함"
}

# ── 세션 선택 → 확인 ──────────────────────────────────────────────
pick_review() {
  local have="$1" flagged="$2" i s e n got st ans
  echo
  echo "  ── 확인할 세션 선택 ────────────────────────────"
  for ((i=1; i<=NSES; i++)); do
    s=$(( (i-1)*SES )); e=$(( s + SES - 1 ))
    (( e > TOTAL-1 )) && e=$(( TOTAL-1 ))
    n=$(( e - s + 1 )); got=$(( have - s ))
    (( got < 0 )) && got=0; (( got > n )) && got=$n
    (( got == 0 )) && continue
    if _has_flag "$s" "$e" "$flagged"; then st="⚠ 주의"
    elif (( got < n ));                  then st="·· 녹화 중"
    else                                      st="V 완료"
    fi
    printf '    S%-3d ep %d~%d   %d개   %s\n' "$i" "$s" "$((s+got-1))" "$got" "$st"
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
      [[ "$no" =~ ^[0-9]+$ ]] || { echo "  S1 ~ S${NSES} 또는 a 를 입력하세요."; return 0; }
      (( no >= 1 && no <= NSES )) || { echo "  S1 ~ S${NSES} 또는 a 를 입력하세요."; return 0; }
      local lo=$(( (no-1)*SES )) hi=$(( no*SES - 1 ))
      (( hi > have-1 )) && hi=$(( have-1 ))
      (( lo > hi )) && { echo "  빈 세션"; return 0; }
      review "$lo" "$hi" ;;
    *) echo "  S1 ~ S${NSES} 또는 a 를 입력하세요." ;;
  esac
}

FLAGGED="$(scan_flags)"
HAVE="$(have_eps)"
header "$HAVE" "$FLAGGED"

if (( HAVE >= TOTAL )); then
  echo
  echo "  에피소드 ${TOTAL}개 녹화 완료."
  [[ -n "$FLAGGED" ]] && echo "  ⚠ 재확인 필요 에피소드 : $FLAGGED   →  edu2-2 로 확인하세요."
  echo "  추가 녹화 :  NUM_EPISODES=$((TOTAL+SES)) edu2-3"
  exit 0
fi

need_ports "$FOLLOWER_PORT" "$LEADER_PORT"

# 현재 에피소드 수(HAVE)로부터 이번에 녹화할 세션을 정한다.
#   ⚠ 세션이 덜 찼으면 **모자란 만큼만** 녹화한다. 매번 SES 개를 녹화하면
#      S1 에 14개가 들어가는 식으로 세션 경계가 어긋난다.
next_session() {
  SNO=$(( HAVE / SES + 1 ))
  N=$(( SES - HAVE % SES ))
  (( N > TOTAL - HAVE )) && N=$(( TOTAL - HAVE ))
  FROM=$HAVE; TO=$(( HAVE + N - 1 ))
}

# ── 세션 반복 ─────────────────────────────────────────────────────
while (( HAVE < TOTAL )); do
  next_session

  echo
  echo "▶ S${SNO} — 에피소드 ${N}개 (ep ${FROM}~${TO})"

  # 시작 전 : 엔터로 바로 시작하거나, rt 로 시간을 바꾸거나, q 로 그만둔다
  while true; do
    echo "  [Enter] 시작          [v]  영상 확인"
    echo "  [rt] 시간 변경        [q] 종료"
    if ! read -r -p "  → " ANS; then ANS="q"; fi
    case "$ANS" in
      ""|y|Y|Y*) break ;;
      q|Q) echo "  종료. 이어서 녹화 :  edu2-3"; exit 0 ;;
      v|V)
        if [[ -f "$EDU_ROOT/meta/info.json" ]]; then
          pick_review "$HAVE" "$FLAGGED"
          HAVE="$(have_eps)"; FLAGGED="$(scan_flags)"
          header "$HAVE" "$FLAGGED"
          next_session
        else
          echo "  녹화된 에피소드 없음"
        fi
        echo; echo "▶ S${SNO} — 에피소드 ${N}개 (ep ${FROM}~${TO})"
        ;;
      rt|RT)
        echo "  시간입력  —    25 8   (녹화 25초 대기 8초)"
        if read -r -p "  → " RTA; then
          # shellcheck disable=SC2086
          set -- $RTA
          if [[ -n "${1:-}" ]]; then
            set_rt "${1:-}" "${2:-}" && { header "$HAVE" "$FLAGGED"
                                          echo; echo "▶ S${SNO} — 에피소드 ${N}개 (ep ${FROM}~${TO})"; }
          fi
        fi
        ;;
      rt\ *|RT\ *)
        # shellcheck disable=SC2086
        set -- $ANS; shift
        set_rt "${1:-}" "${2:-}" && { header "$HAVE" "$FLAGGED"
                                      echo; echo "▶ S${SNO} — 에피소드 ${N}개 (ep ${FROM}~${TO})"; }
        ;;
      *) echo "  Enter · rt · q 중 하나를 입력하세요." ;;
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
  # ESC 로 끊어도 녹화된 에피소드는 남아 있다 — 오류가 아니라 「메뉴로」다.
  # 에피소드가 하나도 늘지 않고 실패한 경우에만 오류로 본다.
  if (( rc != 0 )) && (( NEW <= HAVE )); then
    echo; echo "녹화 시작 실패 (코드 $rc)"; exit "$rc"
  fi
  (( rc == 0 )) || echo "  녹화 중단됨 — 녹화된 에피소드 ${NEW}개 확인 단계로 이동"

  # ── 확인 : 뷰어 + 화면 표시 ────────────────────────────────────
  echo
  echo "── S${SNO} 확인 ────────────────────────────────────────"
  review "$FROM" "$((NEW-1))"
  HAVE="$(have_eps)"

  FLAGGED="$(scan_flags)"
  header "$HAVE" "$FLAGGED"
done

echo
echo "에피소드 확인 :  edu2-2"
echo "학습         :  edu3-1"
