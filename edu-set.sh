#!/usr/bin/env bash
# edu-set · 새 PC 맞추기 — 단축 명령을 걸고, 포트·카메라를 잡고, 준비 상태를 점검한다.
#
#   새 PC 에서 **첫 명령**이다 :   bash edu-set.sh
#   그 실행으로 edu-set · edu1-1 … 이 걸리고, 그다음부터는 어디서든 : edu-set
#
#   ⚠ 포트가 어느 팔인지는 **사람이 정한다.** 이 도구는 케이블을 뽑았다 꽂게 해서
#      사라진 포트를 알려줄 뿐이고, 넣기 전에 반드시 미리보기와 확인을 거친다.
# 점검 도구다 — 파이썬 환경이 없어도 끝까지 돌아 무엇이 모자란지 알려줘야 한다.
EDU_ENV_OPTIONAL=1
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

CFG="$EDU_DIR/config.sh"

ports() { ls -1 /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | sort; }



# config.sh 의 기본값 한 줄만 바꾼다 (주석은 그대로 둔다)
set_cfg() {
  local key="$1" val="$2"
  python3 - "$CFG" "$key" "$val" <<'PY'
import re, sys
path, key, val = sys.argv[1:4]
s = open(path).read()
pat = re.compile(rf'^({re.escape(key)}="\$\{{{re.escape(key)}:-)[^}}]*(\}}")', re.M)
if not pat.search(s):
    sys.exit(f"  ✘ config.sh 에서 {key} 를 못 찾았다")
open(path, "w").write(pat.sub(lambda m: m.group(1) + val + m.group(2), s, count=1))
PY
}

find_arm() {   # $1 = 사람이 읽을 이름 →  찾은 포트를 전역 FOUND 에 담는다
  FOUND=""
  local before after gone
  before="$(ports)"
  if [[ -z "$before" ]]; then
    echo "  붙어 있는 포트가 없다. 두 팔을 모두 꽂고 다시 실행한다." >&2; return 1
  fi
  echo
  echo "  ── $1 찾기 ─────────────────────────────────────"
  echo "     지금 보이는 포트 :"; echo "$before" | sed 's/^/       /'
  read -r -p "     $1 의 USB 를 뽑고 [Enter] (건너뛰려면 s) : " a || return 1
  [[ "$a" == "s" ]] && { echo "     건너뛴다."; return 1; }
  sleep 1
  after="$(ports)"
  gone="$(comm -23 <(echo "$before") <(echo "$after"))"
  read -r -p "     다시 꽂고 [Enter] : " _ || true
  sleep 2
  local n; n="$(echo "$gone" | grep -c .)"
  if (( n == 1 )); then
    FOUND="$gone"
    echo "     → $FOUND"
    return 0
  elif (( n == 0 )); then echo "     ✘ 사라진 포트가 없다 — 안 뽑혔거나 다른 케이블이다" >&2
  else                    echo "     ✘ 여러 개가 사라졌다 : $gone" >&2; fi
  return 1
}

banner "edu-set · 새 PC 맞추기" "단축 명령 · 포트 · 카메라 · 준비 점검" \
       "새 PC 에서 첫 명령 :  bash edu-set.sh   (그 뒤로는 edu-set)"
echo "  설정 파일 : $CFG"
# SMB·FAT 를 거치면 실행 권한이 날아간다. 단축 명령을 걸든 안 걸든 먼저 세운다.
chmod +x "$EDU_DIR"/*.sh 2>/dev/null && echo "  실행 권한을 세웠다 (*.sh)"

# ── 1. 단축 명령 ──────────────────────────────────────────────────
echo
echo "══ 1. 단축 명령 ══"
BIN="${EDU_BIN:-$HOME/.local/bin}"
echo "  지금은 폴더 안에서 bash 로 부르고 있다."
echo "  $BIN 에 걸어두면 앞으로 어느 폴더에서든 edu1-1 처럼 쓸 수 있다."
read -r -p "  걸까? [y/N] " a || a=n
if [[ "$a" =~ ^[Yy]$ ]]; then
  mkdir -p "$BIN"
  n=0
  ln -sfn "$EDU_DIR/edu-set.sh" "$BIN/edu-set" && n=$((n+1))
  for f in "$EDU_DIR"/[1-4]-[1-9]_*.sh; do
    b="$(basename "$f")"; ln -sfn "$f" "$BIN/edu${b%%_*}" && n=$((n+1))
  done
  echo "  $n 개 걸었다 :"
  ls -1 "$BIN"/edu-set "$BIN"/edu[1-4]-* 2>/dev/null | xargs -n1 basename | tr "\n" " " | sed "s|^|    |"; echo
  case ":$PATH:" in
    *":$BIN:"*) echo "  PATH 에 있다 — 바로 쓸 수 있다." ;;
    *) echo "  ⚠ $BIN 이 PATH 에 없다. 셸 설정에 아래를 넣는다 :"
       echo "     export PATH=\"$BIN:\$PATH\"" ;;
  esac
else
  echo "  걸지 않았다. 계속 폴더 안에서 :  bash 1-1_teleop.sh"
fi

# ── 2. 포트 ───────────────────────────────────────────────────────
echo
echo "══ 2. 로봇 포트 ══"
NEW_F=""; NEW_L=""
if find_arm "팔로워(따라 움직이는 팔)"; then NEW_F="$FOUND"; fi
if find_arm "리더(손으로 잡는 팔)";     then NEW_L="$FOUND"; fi
if [[ -n "$NEW_F" && -n "$NEW_L" && "$NEW_F" == "$NEW_L" ]]; then
  echo "  ✘ 둘이 같은 포트로 잡혔다 — 다시 한다." >&2; NEW_F=""; NEW_L=""
fi

# ── 3. 카메라 ─────────────────────────────────────────────────────
echo
echo "══ 3. 카메라 ══"
NEW_T=""; NEW_W=""
if pgrep -f 'lerobot-(record|rollout|teleoperate)' >/dev/null; then
  echo "  ⚠ 카메라를 쓰는 작업이 돌고 있다 — 건너뛴다."
elif [[ -z "$(ls -1 /dev/video* 2>/dev/null)" ]]; then
  echo "  붙어 있는 카메라가 없다 — 건너뛴다."
else
  echo "  각 번호에서 한 장씩 찍어 브라우저에 띄운다..."
  SHOT="$(mktemp -d)"
  LIVE="$(SHOT="$SHOT" python3 <<'PY'
import os, glob, re
import sys, contextlib
os.environ.setdefault("OPENCV_LOG_LEVEL", "SILENT")
import cv2                                   # 진짜 영상이 나오는 번호만 골라낸다
out, live, seen = os.environ["SHOT"], [], {}
idxs = sorted(int(re.sub(r"\D", "", d)) for d in glob.glob("/dev/video*"))
devnull = os.open(os.devnull, os.O_WRONLY)
saved = os.dup(2)
for i in idxs:
    os.dup2(devnull, 2)                      # v4l2 경고를 화면에 안 흘린다
    try:
        # ⚠ 인덱스가 아니라 **장치 경로**로 연다. 인덱스로 열면 /dev/videoN 과
        #   짝이 안 맞아 메타데이터 노드가 영상인 것처럼 잡힌다.
        cap = cv2.VideoCapture(f"/dev/video{i}", cv2.CAP_V4L2)
        ok, frame = (cap.read() if cap.isOpened() else (False, None))
        cap.release()
    except Exception:
        ok, frame = False, None
    finally:
        os.dup2(saved, 2)
    if ok and frame is not None and frame.size:
        cv2.imwrite(f"{out}/cam{i}.jpg", frame)
        live.append(str(i)); seen[i] = frame.shape
cards = "".join(
    f'<figure><img src="cam{i}.jpg"><figcaption>{i} 번</figcaption></figure>' for i in live)
open(f"{out}/index.html", "w").write(
  "<!doctype html><meta charset='utf-8'><title>카메라 확인</title>"
  "<style>body{background:#16181a;color:#e6e6e6;font-family:sans-serif;margin:0;padding:28px}"
  "h1{font-size:1.2em;margin:0 0 6px}p{color:#9aa0a6;margin:0 0 22px}"
  ".row{display:flex;gap:18px;flex-wrap:wrap}figure{margin:0;flex:1 1 380px}"
  "img{width:100%;border-radius:8px;border:1px solid #2e3236;display:block}"
  "figcaption{margin-top:8px;font-size:1.6em;font-weight:700;text-align:center}</style>"
  f"<h1>카메라 확인</h1><p>어느 것이 <b>상단</b>이고 어느 것이 <b>손목</b>인지 보고, "
  f"터미널에 번호를 넣는다.</p><div class='row'>{cards}</div>")
print(" ".join(live))
PY
)"
  if [[ -z "$LIVE" ]]; then
    echo "  ✘ 어느 번호에서도 화면이 안 나온다 — 건너뛴다."
  else
    echo "  영상이 나오는 번호 : $LIVE"
    edu_open "file://$SHOT/index.html"
    read -r -p "  상단(top) 카메라 번호 [엔터=그대로 $CAM_TOP] : "   NEW_T || NEW_T=""
    read -r -p "  손목(wrist) 카메라 번호 [엔터=그대로 $CAM_WRIST] : " NEW_W || NEW_W=""
    for v in "$NEW_T" "$NEW_W"; do
      [[ -z "$v" ]] && continue
      if [[ ! "$v" =~ ^[0-9]+$ ]] || [[ " $LIVE " != *" $v "* ]]; then
        echo "  ✘ 화면이 나온 번호 중에서 고른다 ($LIVE) — 카메라는 건너뛴다"
        NEW_T=""; NEW_W=""; break
      fi
    done
    [[ -n "$NEW_T" && "$NEW_T" == "$NEW_W" ]] && {
      echo "  ✘ 둘이 같은 번호다 — 건너뛴다"; NEW_T=""; NEW_W=""; }
  fi
fi

# ── 4. 미리보기 → 확인 → 반영 ─────────────────────────────────────
echo
echo "══ 4. 바꿀 내용 ══"
CH=0
show() { [[ -n "$2" && "$2" != "$3" ]] && { printf '  %-14s %s  →  %s\n' "$1" "$3" "$2"; CH=1; }; }
show FOLLOWER_PORT "$NEW_F" "$FOLLOWER_PORT"
show LEADER_PORT   "$NEW_L" "$LEADER_PORT"
show CAM_TOP       "$NEW_T" "$CAM_TOP"
show CAM_WRIST     "$NEW_W" "$CAM_WRIST"
if (( CH == 0 )); then
  echo "  바뀌는 게 없다."
else
  read -r -p "  config.sh 에 넣을까? [y/N] " a || a=n
  if [[ "$a" =~ ^[Yy]$ ]]; then
    cp -f "$CFG" "$CFG.bak" && echo "  백업 : config.sh.bak"
    [[ -n "$NEW_F" && "$NEW_F" != "$FOLLOWER_PORT" ]] && set_cfg FOLLOWER_PORT "$NEW_F"
    [[ -n "$NEW_L" && "$NEW_L" != "$LEADER_PORT"   ]] && set_cfg LEADER_PORT   "$NEW_L"
    [[ -n "$NEW_T" && "$NEW_T" != "$CAM_TOP"       ]] && set_cfg CAM_TOP       "$NEW_T"
    [[ -n "$NEW_W" && "$NEW_W" != "$CAM_WRIST"     ]] && set_cfg CAM_WRIST     "$NEW_W"
    echo "  넣었다."
  else
    echo "  넣지 않았다."
  fi
fi

# ── 5. 준비 점검 ──────────────────────────────────────────────────
echo
echo "══ 5. 준비 점검 ══"
OK=0; NG=0
ok()   { printf '  ✔ %-22s %s\n' "$1" "${2:-}"; OK=$((OK+1)); }
ng()   { printf '  ✘ %-22s %s\n' "$1" "${2:-}"; NG=$((NG+1)); }
info() { printf '  ⓘ %-22s %s\n' "$1" "${2:-}"; }


echo "── 파이썬 ──"
if python3 -c 'import pandas, pyarrow' 2>/dev/null; then
  ok "pandas · pyarrow" "$(python3 -V 2>&1)  ($(command -v python3))"
else
  ng "pandas · pyarrow" "환경을 못 잡았다 — 보기·판정·학습이 안 된다"
  echo "       환경을 켜고 :  conda activate <이름>"
  echo "       모자란 것 채우기 :  pip install \"lerobot[dataset,viz,feetech,smolvla]\""
  command -v conda >/dev/null && {
    echo "       이 PC 의 conda 환경 :"
    conda env list 2>/dev/null | awk '!/^#/ && NF {print "         "$0}'; }
fi

python3 -c 'import rerun' 2>/dev/null \
  && ok "rerun (화면 표시)" "$(python3 -c 'import rerun;print(rerun.__version__)' 2>/dev/null)" \
  || { ng "rerun (화면 표시)" "없다 — 1-2·2-x·4-x 가 화면을 못 띄운다"
       echo "       고치는 두 길 :"
       echo "         python3 -m pip install \"lerobot[viz]\"   (또는 rerun-sdk)"
       echo "         또는 화면 없이 :  DISPLAY_DATA=false edu1-2"; }

echo "── lerobot 명령 ──"
MISS=""
for c in lerobot-teleoperate lerobot-record lerobot-train lerobot-rollout \
         lerobot-edit-dataset lerobot-find-port lerobot-find-cameras; do
  command -v "$c" >/dev/null || MISS="$MISS $c"
done
[[ -z "$MISS" ]] && ok "7개 모두 있음" || ng "빠짐" "$MISS"

echo "── 데이터 위치 ──"
if [[ -d "$LEROBOT_HOME" ]]; then
  [[ -w "$LEROBOT_HOME" ]] && ok "데이터 루트" "$LEROBOT_HOME" \
                           || ng "데이터 루트" "쓰기 권한 없음: $LEROBOT_HOME"
else
  info "데이터 루트" "$LEROBOT_HOME (없다 — 처음 녹화할 때 만들어진다)"
fi
[[ -f "$EDU_ROOT/meta/info.json" ]] \
  && ok "녹화본" "$(grep -o '"total_episodes":[^,]*' "$EDU_ROOT/meta/info.json"|cut -d: -f2)편" \
  || info "녹화본" "아직 없음 (edu2-3 으로 찍는다)"

echo "── 로봇 ──"
# 보정값(텔레옵 파일)은 폴더 안이 아니라 데이터 루트 밑에 있다. 경로를 그대로 보여준다 —
# 옛 PC 에서 복사해 오거나, 없으면 1-1 이 그 자리에서 새로 잡는다.
CAL="$LEROBOT_HOME/calibration"
CAL_F="$CAL/robots/so_follower/$FOLLOWER_ID.json"
CAL_L="$CAL/teleoperators/so_leader/$LEADER_ID.json"
[[ -f "$CAL_F" ]] && ok "팔로워 보정값" "$CAL_F" \
                  || ng "팔로워 보정값" "없다 → 1-1 이 새로 잡는다. 옮겨오려면 :"
[[ -f "$CAL_F" ]] || echo "       $CAL_F"
[[ -f "$CAL_L" ]] && ok "리더 보정값" "$CAL_L" \
                  || ng "리더 보정값" "없다 → 1-1 이 새로 잡는다. 옮겨오려면 :"
[[ -f "$CAL_L" ]] || echo "       $CAL_L"
for p in "$FOLLOWER_PORT:팔로워 포트" "$LEADER_PORT:리더 포트"; do
  [[ -e "${p%%:*}" ]] && ok "${p#*:}" "${p%%:*}" \
                      || ng "${p#*:}" "${p%%:*} 없음 → lerobot-find-port 로 확인 후 config.sh"
done
for c in "$CAM_TOP:상단" "$CAM_WRIST:손목"; do
  [[ -e "/dev/video${c%%:*}" ]] && ok "${c#*:} 카메라" "/dev/video${c%%:*}" \
    || ng "${c#*:} 카메라" "/dev/video${c%%:*} 없음 → lerobot-find-cameras 후 config.sh"
done

echo "── 학습·롤아웃 ──"
if nvidia-smi >/dev/null 2>&1; then
  ok "GPU" "$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader)"
else
  ng "GPU" "nvidia-smi 실패 — 학습이 매우 느리거나 안 된다"
fi
[[ -f "${CKPT%/}/config.json" ]] && ok "학습 결과" "$OUT_NAME" \
                                 || info "학습 결과" "아직 없음 (edu3-1 로 만든다)"
if [[ -n "$STABLE_CKPT" ]]; then
  [[ -f "${STABLE_CKPT%/}/config.json" ]] && ok "안정본" "$STABLE_CKPT" \
                                          || ng "안정본" "경로가 틀렸다: $STABLE_CKPT"
else
  info "안정본" "미지정 (edu4-2 를 쓰려면 config.sh 의 STABLE_CKPT)"
fi

echo "── 모델 캐시 ──"
# ACT 는 ResNet18 백본을 torch 캐시에서 가져온다. 없으면 첫 실행 때 받으러 나간다 —
# 인터넷이 없는 교육장에서 그러면 롤아웃·학습이 그대로 죽는다.
TORCH_CK="${TORCH_HOME:-$HOME/.cache/torch}/hub/checkpoints"
if compgen -G "$TORCH_CK/resnet18-*.pth" >/dev/null; then
  ok "ResNet18 백본" "$(basename "$(compgen -G "$TORCH_CK/resnet18-*.pth" | head -1)")"
else
  if getent hosts download.pytorch.org >/dev/null 2>&1; then
    info "ResNet18 백본" "없음 — 첫 실행 때 받는다 (인터넷 필요, 약 45MB)"
  else
    ng "ResNet18 백본" "없고 인터넷도 안 된다 → 옛 PC 의 ~/.cache/torch 를 복사"
  fi
fi
if [[ -n "$STABLE_CKPT" && -f "${STABLE_CKPT%/}/config.json" ]] \
   && grep -q '"type": *"smolvla"' "${STABLE_CKPT%/}/config.json" 2>/dev/null; then
  VLM="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('vlm_model_name',''))" \
         "${STABLE_CKPT%/}/config.json" 2>/dev/null)"
  VDIR="${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${VLM//\//--}"
  [[ -d "$VDIR" ]] && ok "SmolVLA 백본" "${VLM##*/}" \
                   || ng "SmolVLA 백본" "$VLM 캐시 없음 → 4-2 가 인터넷을 찾는다"
fi

# 인터넷 없이 진짜 도는지 — 안정본을 실제로 올려 본다 (약 10초).
# 캐시가 있어도 오프라인 표시가 없으면 서버에 다시 물으러 나가 실패한다.
if [[ -n "$STABLE_CKPT" && -f "${STABLE_CKPT%/}/config.json" && "${EDU_SKIP_DEEP:-0}" != "1" ]]; then
  echo "── 오프라인 실전 확인 (약 10초) ──"
  if [[ "${HF_HUB_OFFLINE:-0}" == "1" ]]; then ok "오프라인 표시" "HF_HUB_OFFLINE=1"
  else ng "오프라인 표시" "꺼져 있다 — 인터넷 끊기면 4-2 가 죽는다 (config.sh 의 OFFLINE)"; fi
  if HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9 \
     no_proxy= NO_PROXY= python3 - "$STABLE_CKPT" >/dev/null 2>&1 <<'PY'
import sys, json
p = sys.argv[1]
t = json.load(open(p.rstrip("/") + "/config.json")).get("type", "")
if t == "smolvla":
    from lerobot.policies.smolvla.modeling_smolvla import SmolVLAPolicy as P
else:
    from lerobot.policies.act.modeling_act import ACTPolicy as P
m = P.from_pretrained(p, device_map=None); m.to("cpu")
PY
  then ok "안정본 오프라인 로드" "모델을 인터넷 없이 올렸다 (실제 롤아웃은 별개)"
  else ng "안정본 오프라인 로드" "인터넷을 끊으면 4-2 가 모델부터 못 올린다"; fi
fi

echo "── 보기 ──"
B=""
for b in ${EDU_BROWSER:-} google-chrome chromium chromium-browser firefox xdg-open; do
  command -v "$b" >/dev/null && { B="$b"; break; }
done
[[ -n "$B" ]] && ok "브라우저" "$B" || info "브라우저" "없음 — 파일 경로만 알려준다"

echo
echo "══════════════════════════════════════════════════════"
if (( NG == 0 )); then
  echo "  전부 준비됐다.  →  edu1-1 부터 순서대로"
else
  echo "  모자란 것 ${NG}개 — 위 ✘ 를 먼저 해결한다."
  echo "  ✘ 가 로봇·카메라뿐이면 보기·판정·학습은 지금도 된다."
fi
echo "══════════════════════════════════════════════════════"

