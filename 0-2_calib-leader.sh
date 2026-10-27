#!/usr/bin/env bash
# 0-2 · 리더 보정 — 리더암(손으로 잡는 팔)의 관절 범위를 잡는다.
#      0-1 다음, 1-1 앞. 건너뛰어도 1-1 이 보정 파일이 없으면 그 자리에서 보정한다.
#      ⚠ 같은 팔을 옛 PC 에서 쓰던 거라면 보정하지 말고 그 파일을 복사한다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

CAL_FILE="$HF_LEROBOT_CALIBRATION/teleoperators/so_leader/$LEADER_ID.json"

banner "0-2 · 리더 보정" \
        "리더 포트 : $LEADER_PORT   ID : $LEADER_ID" \
        "보정 파일 : $CAL_FILE"

if [[ -f "$CAL_FILE" ]]; then
  echo "  ✔ 보정 파일 있음 — 실행하면 먼저 묻는다 :"
  echo "      [Enter] = 그대로 사용 (모터에만 다시 써 넣음)   c [Enter] = 새로 보정"
else
  echo "  ⓘ 보정 파일 없음"
  echo "     같은 팔을 다른 PC 에서 쓰던 거라면 보정하지 말고 그 파일을 위 경로로 복사하세요."
fi

need_ports "$LEADER_PORT"

RUN_NOTICE="  ── 보정 순서 ──────────────────────────────────────
  0. 리더 전원 연결 확인
  1. 모든 관절을 움직일 수 있는 범위의 가운데 자세로 두고 [Enter]
  2. 관절을 하나씩 끝에서 끝까지 천천히 움직인다 (화면의 MIN·MAX 가 바뀐다)
     손목 회전(wrist_roll)은 한 바퀴 전체를 쓰므로 범위를 잡지 않는다
  3. 모두 움직였으면 [Enter] — 보정 파일이 저장된다
  ───────────────────────────────────────────────────"

run_cmd lerobot-calibrate \
  --teleop.type=so101_leader \
  --teleop.port="$LEADER_PORT" \
  --teleop.id="$LEADER_ID" \
  "${EXTRA[@]+"${EXTRA[@]}"}"
rc=$?

echo
if (( rc == 0 )) && [[ -f "$CAL_FILE" ]]; then
  echo "  ✔ 리더 보정 완료 : $CAL_FILE"
  echo "  다음 : edu1-1 (텔레옵으로 두 팔이 같이 움직이는지 확인)"
else
  echo "  ✘ 보정이 끝나지 않음 (종료코드 $rc) — 전원·케이블 확인 후 다시 edu0-2" >&2
fi
exit "$rc"
