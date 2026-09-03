#!/usr/bin/env bash
# 1-1 · 텔레옵 — 리더암을 움직이면 팔로워암이 따라온다. 카메라 없음.
#      먼저 팔이 제대로 따라오는지만 본다. 화면이 없어 가볍고 빠르다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

banner "1-1 · 텔레옵 (카메라 없음)" \
        "리더암을 손으로 움직여 본다. 팔로워가 따라오면 성공." \
        "끝낼 때는 Ctrl+C."

need_ports "$FOLLOWER_PORT" "$LEADER_PORT"

run_cmd lerobot-teleoperate \
  --robot.type=so101_follower \
  --robot.port="$FOLLOWER_PORT" \
  --robot.id="$FOLLOWER_ID" \
  --teleop.type=so101_leader \
  --teleop.port="$LEADER_PORT" \
  --teleop.id="$LEADER_ID" \
  "${EXTRA[@]+"${EXTRA[@]}"}"
