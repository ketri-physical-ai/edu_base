#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
#  교육용 도구 설정 — 고치는 자리는 이 파일 하나뿐이다
#
#  스크립트 본문은 건드리지 않는다. 값이 바뀌면 여기만 고친다.
#  환경변수로도 덮어쓸 수 있다 :  STEPS=10000 edu3-1
# ══════════════════════════════════════════════════════════════════

# ── 경로 ──────────────────────────────────────────────────────────
# 이 파일이 있는 폴더. models/ 안의 번들을 이 기준으로 찾는다.
EDU_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 폴더 안에 모델 캐시를 같이 옮겼으면 그걸 쓴다.
#   ⚠ 없으면 실행할 때 인터넷으로 받으러 나간다 — 교육장에 인터넷이 없으면 죽는다.
[[ -d "$EDU_HOME/models/hf-cache"    ]] && export HF_HOME="$EDU_HOME/models/hf-cache"
[[ -d "$EDU_HOME/models/torch-cache" ]] && export TORCH_HOME="$EDU_HOME/models/torch-cache"

# 인터넷 없이 돌리기.
#   ⚠ 캐시가 있어도 오프라인 표시를 안 켜면 파일이 그대로인지 **서버에 다시 물으러 나간다.**
#      인터넷이 끊긴 곳에서는 그 확인이 실패해 4-2(SmolVLA)가 죽는다 — 실측으로 확인했다.
#   auto = 번들 캐시가 있으면 켠다 · 1 = 항상 켬 · 0 = 끔(받아올 게 있을 때)
OFFLINE="${OFFLINE:-auto}"
if [[ "$OFFLINE" == "1" ]] || { [[ "$OFFLINE" == "auto" ]] && [[ -d "$EDU_HOME/models" ]]; }; then
  export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 HF_DATASETS_OFFLINE=1
fi

#   ⚠ 다른 PC 로 옮기면 이 두 줄만 고치면 된다. 나머지는 전부 폴더 안에서 해결된다.
#   lerobot 기본 경로를 그대로 쓴다 — 새로 설치한 PC 면 고칠 필요가 없다.
LEROBOT_HOME="${HF_LEROBOT_HOME:-$HOME/.cache/huggingface/lerobot}"          # 데이터·모델이 쌓이는 곳

# ⚠ 여기서 바로 내보낸다. lerobot 은 HF_LEROBOT_HOME 이 없으면 **HF_HOME 밑**을 쓴다.
#   HF_HOME 을 models/hf-cache 로 돌려놨으므로, 안 내보내면 데이터셋·보정값이
#   그 캐시 폴더 안에 생긴다 (보정이 안 되는 것처럼 보이던 원인).
# ⚠ 옛 이름 LEROBOT_HOME 이 **환경에 export 돼 있으면 lerobot 이 거부한다**
#    (utils/constants.py 가 ValueError 를 던진다). 옛 설정이 남은 PC 에서
#    모든 명령이 시작도 못 하므로, 우리 쪽 값만 남기고 걷어낸다.
export -n LEROBOT_HOME 2>/dev/null || true
export HF_LEROBOT_HOME="$LEROBOT_HOME"
export HF_LEROBOT_CALIBRATION="$LEROBOT_HOME/calibration"
CONDA_SH="${CONDA_SH:-$HOME/miniforge3/etc/profile.d/conda.sh}"
CONDA_ENV="${CONDA_ENV:-lerobot}"                                            # conda 환경 이름              # conda 초기화 스크립트

# ── 로봇 포트·ID ──────────────────────────────────────────────────
#   포트가 바뀌면 여기만 고친다.  lerobot-find-port 로 확인
#   ⚠ 꽂는 순서에 따라 0·1 이 뒤바뀔 수 있다. 팔이 반대로 움직이면 두 줄을 맞바꾼다.
FOLLOWER_PORT="${FOLLOWER_PORT:-/dev/ttyACM0}"
LEADER_PORT="${LEADER_PORT:-/dev/ttyACM1}"
FOLLOWER_ID="${FOLLOWER_ID:-my_awesome_follower_arm}"
LEADER_ID="${LEADER_ID:-my_awesome_leader_arm}"

# ── 카메라 ────────────────────────────────────────────────────────
#   인덱스가 바뀌면 여기만 고친다.  lerobot-find-cameras 로 확인
CAM_TOP="${CAM_TOP:-0}"
CAM_WRIST="${CAM_WRIST:-2}"
CAM_W="${CAM_W:-640}"
CAM_H="${CAM_H:-480}"
CAM_FPS="${CAM_FPS:-30}"

# ── 과제 문장 ─────────────────────────────────────────────────────
#   ⚠ 한 데이터셋 안에서는 절대 바꾸지 않는다.
#      이어서 녹화할 때 문장이 다르면 데이터셋이 두 과제로 갈라진다.
TASK="${TASK:-Put the red cylinder into the cup}"

# 로봇 화면(rerun) 을 띄울지. rerun-sdk 가 없는 PC 면 false 로 두면 그대로 돈다.
DISPLAY_DATA="${DISPLAY_DATA:-true}"

# ── 데이터셋 ──────────────────────────────────────────────────────
EDU_NAME="${EDU_NAME:-so101_edu}"                 # 실제 녹화본 이름
EDU_TEST_NAME="${EDU_TEST_NAME:-so101_edu_test}"  # 연습 녹화본 이름

EDU_REPO_ID="${EDU_REPO_ID:-data/$EDU_NAME}"
EDU_ROOT="${EDU_ROOT:-$LEROBOT_HOME/$EDU_REPO_ID}"
EDU_TEST_REPO_ID="${EDU_TEST_REPO_ID:-data/$EDU_TEST_NAME}"
EDU_TEST_ROOT="${EDU_TEST_ROOT:-$LEROBOT_HOME/$EDU_TEST_REPO_ID}"

# ── 녹화 값 ───────────────────────────────────────────────────────
NUM_EPISODES="${NUM_EPISODES:-100}"       # 2-3 실제 녹화 에피소드 수 (1차)
ADD_EPISODES="${ADD_EPISODES:-30}"        # 2-3 추가 녹화로 보강할 에피소드 수 (2차)
SESSION_SIZE="${SESSION_SIZE:-10}"        # 2-3 세션당 에피소드 수

# ── 골든 데이터셋 (2-4 병합용) ────────────────────────────────────
#   미리 녹화해 둔 기준 데이터. 2-3 녹화본에 병합해 학습 데이터를 보강한다.
#   ⚠ 합치려면 **fps · 카메라 구성 · 과제 문장이 같아야** 한다.
GOLDEN_NAME="${GOLDEN_NAME:-so101_golden}"
GOLDEN_ROOT="${GOLDEN_ROOT:-$EDU_HOME/golden/$GOLDEN_NAME}"

# ── 골든 학습 로그 (3-2 로 기준 곡선을 보여줄 때) ─────────────────
#   골든 모델을 만든 그 학습의 stdout 로그.  edu3-2 --golden 으로 이걸 그린다.
#   ⚠ 비워두거나 파일이 없으면 3-2 가 평소대로 내 학습 로그(OUT_NAME)를 찾는다.
GOLDEN_LOG="${GOLDEN_LOG:-$EDU_HOME/golden/act_edu3_100-golden.log}"

#   병합 결과가 저장될 자리 (데이터 루트 밑 — 폴더 안이 아니다)
MERGED_NAME="${MERGED_NAME:-${EDU_NAME}_merged}"
MERGED_REPO_ID="${MERGED_REPO_ID:-data/$MERGED_NAME}"
MERGED_ROOT="${MERGED_ROOT:-$LEROBOT_HOME/$MERGED_REPO_ID}"
TEST_EPISODES="${TEST_EPISODES:-2}"       # 2-1 연습 녹화 에피소드 수
EPISODE_TIME_S="${EPISODE_TIME_S:-20}"    # 에피소드당 녹화시간(초)
RESET_TIME_S="${RESET_TIME_S:-5}"         # 에피소드 사이 리셋 대기시간(초)

# ── 학습 값 ───────────────────────────────────────────────────────
#   ACT 기준 실측(RTX 5080) : 배치 8 = 11.34 step/s · 배치 16 = 5.95 step/s
#   아래 두 값은 분당 스텝수 — GPU 가 바뀌면 여기만 고치면 3-1 예상시간이 따라간다.
RATE_B8="${RATE_B8:-680}"
RATE_B16="${RATE_B16:-357}"
POLICY_TYPE="${POLICY_TYPE:-act}"
STEPS="${STEPS:-30000}"
BATCH_SIZE="${BATCH_SIZE:-8}"
NUM_WORKERS="${NUM_WORKERS:-4}"
SAVE_FREQ="${SAVE_FREQ:-5000}"            # 중간 체크포인트 주기 (기본 20000이면 안 남는다)

# 회차 — 2차 학습은 RUN=2 로 돌린다. 1차 결과가 남아 비교할 수 있다.
#        롤아웃(4-1)의 체크포인트도 회차를 따라간다.
RUN="${RUN:-1}"
OUT_NAME="${OUT_NAME:-act_edu_r${RUN}}"
OUT_DIR="${OUT_DIR:-$LEROBOT_HOME/outputs/train/$OUT_NAME}"
LOG_DIR="${LOG_DIR:-$LEROBOT_HOME/outputs/train/_logs}"

# ── 롤아웃 공통 (4-1 · 4-2) ───────────────────────────────────────
DURATION="${DURATION:-0}"                 # 0 = 무제한 (Ctrl+C 로 끝낸다)
#   RTC 값 — inference_type 이 rtc 일 때만 쓰인다.
#   공식 기본 : horizon 10 / interp 1.  아래는 이 프로젝트 실측 권장값
#   max_guidance_weight 는 건드리지 않는다 — 기본 10.0 이 맞다
RTC_HORIZON="${RTC_HORIZON:-30}"
RTC_INTERP="${RTC_INTERP:-3}"

# ── 롤아웃 4-1 (방금 학습한 모델) ─────────────────────────────────
CKPT="${CKPT:-$OUT_DIR/checkpoints/last/pretrained_model}"
INFERENCE_TYPE="${INFERENCE_TYPE:-sync}"  # ACT=sync · SmolVLA 등 느린 VLA=rtc

# ── 롤아웃 (4-2 · 안정본) ─────────────────────────────────────────
#   ⚠ 교육 전에 이 세 줄을 채운다. 비워두면 4-2 가 안내만 하고 멈춘다.
#   폴더 안에 같이 옮긴 안정본. 다른 모델로 바꾸려면 아래 세 줄만 고친다.
#     · ACT   → INFERENCE_TYPE=sync · RENAME_MAP 은 비운다
#     · SmolVLA → INFERENCE_TYPE=rtc  · RENAME_MAP 을 채운다 (카메라 이름이 다르다)
#   지금 들어 있는 것 : act_edu3_100 의 060000 체크포인트
#     골든 데이터 so101_edu3(에피소드 100개·fps 30·top/wrist) 로 ACT 60,000 step.
#     같은 학습의 곡선이 golden/act_edu3_100-golden.log (edu3-2 --golden).
STABLE_CKPT="${STABLE_CKPT:-$EDU_HOME/models/act_golden}"
STABLE_INFERENCE_TYPE="${STABLE_INFERENCE_TYPE:-sync}"
STABLE_TASK="${STABLE_TASK:-$TASK}"

STABLE_RENAME_MAP="${STABLE_RENAME_MAP:-}"
#   SmolVLA 로 되돌릴 때 쓰는 값 :
#   STABLE_RENAME_MAP='{"observation.images.top":"observation.images.camera1","observation.images.wrist":"observation.images.camera2"}'

# ── 여기부터는 위 값으로 자동 조립된다 (고치지 않는다) ────────────
CAMERAS="{top: {type: opencv, index_or_path: ${CAM_TOP}, width: ${CAM_W}, height: ${CAM_H}, fps: ${CAM_FPS}}, wrist: {type: opencv, index_or_path: ${CAM_WRIST}, width: ${CAM_W}, height: ${CAM_H}, fps: ${CAM_FPS}}}"
