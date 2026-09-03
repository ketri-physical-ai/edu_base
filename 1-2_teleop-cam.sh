#!/usr/bin/env bash
# 1-2 · 텔레옵 + 카메라 — 1-1 에 카메라 두 대와 화면을 붙인다.
#      녹화 때 저장될 그림이 바로 이 화면이다. 원통이 잘 보이는지 여기서 맞춘다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

banner "1-2 · 텔레옵 + 카메라" \
        "카메라 top(${CAM_TOP}) · wrist(${CAM_WRIST})" \
        "창이 두 개 뜬다. 원통과 컵이 화면 안에 들어오게 카메라를 맞춘다." \
        "끝낼 때는 Ctrl+C."

need_ports "$FOLLOWER_PORT" "$LEADER_PORT"

run_cmd lerobot-teleoperate \
  --robot.type=so101_follower \
  --robot.port="$FOLLOWER_PORT" \
  --robot.id="$FOLLOWER_ID" \
  --robot.cameras="$CAMERAS" \
  --teleop.type=so101_leader \
  --teleop.port="$LEADER_PORT" \
  --teleop.id="$LEADER_ID" \
  --display_data="$DISPLAY_DATA" \
  "${EXTRA[@]+"${EXTRA[@]}"}"
