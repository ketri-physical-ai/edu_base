#!/usr/bin/env bash
# =============================================================================
#  drum3-view.sh — 녹화한 에피소드를 Chrome 탭에서 확인한다
#
#  사용:
#    bash _view.sh red_a1          # 세션 전체 (판별로 나열)
#    bash _view.sh red_a1 9        # 9번 판만
#    bash _view.sh red_a1 3-6      # 3~6번 판
#    bash _view.sh red_a1_old      # 백업 폴더도 그대로 열린다
#    bash _view.sh red_a1 --no-open
#
#  ⚠ v3 데이터셋은 여러 판이 mp4 하나에 이어붙어 있다. 판마다 파일이 따로 있지 않다.
#    그래서 meta/episodes 의 from_timestamp~to_timestamp 를 읽어 그 구간만 반복 재생한다.
#    (인코딩을 다시 하지 않으므로 즉시 뜨고 원본을 건드리지 않는다)
#
#  · 전부 로컬 처리. 결과 HTML 은 /tmp/drum3view/ 에 생성
#  · 카메라 두 대(top · wrist)를 나란히 놓는다
# =============================================================================

set -euo pipefail

# 같은 폴더의 config.sh 에서 값을 받는다 — 폴더째 옮겨도 돈다.
_SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck disable=SC1091
source "$_SELF_DIR/config.sh"
# 다른 조각 폴더도 볼 수 있게 열어둔다 — slot-record.sh 가 여기를 바꿔 부른다.
#   VIEW_BASE=<폴더> bash _view.sh so101_slot_p1_red
BASE="${VIEW_BASE:-$LEROBOT_HOME/data}"

NAME="${1:?사용법: drum3-view.sh <이름꼬리> [판번호|시작-끝] [--no-open]}"
shift

SEL=""
OPEN=1
for a in "$@"; do
    case "$a" in
        --no-open) OPEN=0 ;;
        *)         SEL="$a" ;;
    esac
done

# 이름꼬리(red_a1)로도, 폴더 이름 그대로(so101_drum3_red_a1_old)로도 받는다
if   [ -d "$BASE/so101_drum3_$NAME" ]; then ROOT="$BASE/so101_drum3_$NAME"
elif [ -d "$BASE/$NAME" ];             then ROOT="$BASE/$NAME"
else
    echo "❌ 그런 세션이 없다 : $NAME" >&2
    echo "   있는 것 :" >&2
    ls -1 "$BASE" 2>/dev/null | sed 's/^/     /' >&2
    exit 1
fi

OUT_DIR="/tmp/drum3view"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$(basename "$ROOT")${SEL:+_$SEL}.html"

# shellcheck disable=SC1091
source "$_SELF_DIR/_env.sh"; edu_activate || exit 1

ROOT="$ROOT" OUT="$OUT" SEL="$SEL" EP_TIME_S="${EPISODE_TIME_S:-0}" python3 <<'PY'
import os, json, glob, html
from pathlib import Path
import pandas as pd

root = Path(os.environ["ROOT"])
out  = os.environ["OUT"]
sel  = os.environ.get("SEL", "").strip()

info = json.load(open(root / "meta" / "info.json"))
fps  = info["fps"]
vpat = info["video_path"]          # videos/{video_key}/chunk-{chunk_index:03d}/file-{file_index:03d}.mp4

df = pd.concat(
    [pd.read_parquet(p) for p in sorted(glob.glob(str(root / "meta/episodes/**/*.parquet"), recursive=True))]
).sort_values("episode_index")

vkeys = [k for k in info["features"] if k.startswith("observation.images.")]

# ── 모터 데이터 (관절 6개 · 명령 vs 실제) ─────────────────────────
JOINTS = [n.replace(".pos", "") for n in
          info["features"].get("observation.state", {}).get("names", [])]
MOT = None
if JOINTS:
    try:
        _mp = sorted(glob.glob(str(root / "data/**/*.parquet"), recursive=True))
        if _mp:
            MOT = pd.concat(
                [pd.read_parquet(f, columns=["episode_index", "timestamp",
                                             "action", "observation.state"]) for f in _mp]
            )
    except Exception:
        MOT = None            # 데이터가 없거나 형식이 다르면 그래프만 건너뛴다

def motor_svg(ep_i):
    """한 편의 관절 6개를 작은 그래프 6장으로. 실선=실제, 점선=명령."""
    if MOT is None:
        return ""
    d = MOT[MOT.episode_index == ep_i]
    if d.empty:
        return ""
    t = d["timestamp"].to_numpy(dtype=float)
    A = [list(v) for v in d["action"]]
    S = [list(v) for v in d["observation.state"]]
    n = len(t)
    step = max(1, n // 220)                     # 220점으로 솎는다
    idx = list(range(0, n, step))
    t0, t1 = t[0], t[-1] if t[-1] > t[0] else t[0] + 1

    W, H, PAD = 250, 74, 15
    panels = []
    for j, name in enumerate(JOINTS):
        av = [A[i][j] for i in idx]
        sv = [S[i][j] for i in idx]
        lo, hi = min(min(av), min(sv)), max(max(av), max(sv))
        if hi - lo < 1e-6:
            lo, hi = lo - 1, hi + 1
        pad = (hi - lo) * 0.12
        lo, hi = lo - pad, hi + pad
        def pts(vals):
            return " ".join(
                f"{PAD + (t[i]-t0)/(t1-t0)*(W-PAD-6):.1f},"
                f"{H-14 - (v-lo)/(hi-lo)*(H-14-8):.1f}"
                for i, v in zip(idx, vals))
        err = sum(abs(a-b) for a, b in zip(av, sv)) / len(av)
        panels.append(
            f'<div class="mp"><svg viewBox="0 0 {W} {H}" preserveAspectRatio="none">'
            f'<polyline class="cmd" points="{pts(av)}"/>'
            f'<polyline class="act" points="{pts(sv)}"/>'
            f'<text x="{PAD}" y="10" class="jn">{html.escape(name)}</text>'
            f'<text x="{W-6}" y="10" class="je" text-anchor="end">Δ{err:.1f}</text>'
            f'<line class="ph" x1="{PAD}" x2="{PAD}" y1="4" y2="{H-4}"/>'
            f'</svg></div>')
    return (f'<details class="mot"{MOT_OPEN}><summary>모터 그래프 — 관절 6개 '
            '<span class="lg"><i class="k-act"></i>실제 '
            '<i class="k-cmd"></i>명령(리더)</span></summary>'
            f'<div class="mgrid" data-x0="{PAD}" data-x1="{W-6}">{"".join(panels)}</div>'
            '<p class="mnote">Δ 는 명령과 실제의 평균 차이(도). '
            '무거운 관절일수록 크다 — 팔이 명령을 뒤따라간다는 뜻이다. '
            '<b>세로선이 영상 재생 위치다. 그래프를 누르면 그 시점으로 영상이 넘어간다.</b>'
            '</p></details>')

# ── 이상한 판 자동 표시 (지우지 않는다 — 표시만) ─────────────────
#   기준은 이 데이터셋 자신의 중앙값이다. 과제마다 길이가 달라 고정값을 못 쓴다.
SHORT_R = float(os.environ.get("VIEW_SHORT_RATIO", "0.55"))
LONG_R  = float(os.environ.get("VIEW_LONG_RATIO",  "1.45"))

_len = df["length"].astype(float)
MED  = float(_len.median()) if len(_len) else 0.0
FLAGS = {}                                   # ep -> [사유, ...]

def _flag(i, why, lvl="err"):
    # err  = 데이터가 깨졌거나 과제를 못 끝냄 — 지우는 쪽을 권한다
    # note = 길이 편차일 뿐 — 영상을 보고 사람이 판단한다
    FLAGS.setdefault(int(i), [])
    if (why, lvl) not in FLAGS[int(i)]:
        FLAGS[int(i)].append((why, lvl))

lens = {int(r.episode_index): int(r.length) for _, r in df.iterrows()}
# 시간상한 판정 — 두 갈래로 본다.
#   ① 녹화 설정을 아는 경우 : 상한 프레임에 닿은 판이 상한이다.
#   ② 모르는 경우 : 최대 길이를 두 판 이상이 공유하고, **그 값이 중앙값보다
#      뚜렷이 클 때만** 상한으로 본다. 우연히 길이가 겹친 것을 상한이라 부르면
#      멀쩡한 판이 걸린다 (실제로 7.8초를 20초 상한이라 오판한 적이 있다).
_EPT  = float(os.environ.get("EP_TIME_S", "0") or 0)
_CAPF = round(_EPT * fps) if _EPT > 0 else 0
CAPPED = set()
#   상한에 걸린 판은 그 값을 **넘지 않고 정확히 닿는다**. 넘었으면 그 설정이 아니다.
if _CAPF and lens and any(abs(L - _CAPF) <= 2 for L in lens.values()):
    CAPPED = {i for i, L in lens.items() if abs(L - _CAPF) <= 2}
if not CAPPED and lens:
    _mx = max(lens.values())
    if list(lens.values()).count(_mx) >= 2 and MED and _mx > MED * LONG_R:
        CAPPED = {i for i, L in lens.items() if L == _mx}
_lens = lens

if MED > 0:
    for i, L in _lens.items():
        if i in CAPPED:
            _flag(i, f"시간상한에 걸림 ({L/fps:.1f}초 — 끝까지 못 끝냈다)")
        elif L < MED * SHORT_R:
            _flag(i, f"너무 짧다 ({L/fps:.1f}초 · 보통 {MED/fps:.1f}초)", "note")
        elif L > MED * LONG_R:
            _flag(i, f"너무 길다 ({L/fps:.1f}초 · 보통 {MED/fps:.1f}초)", "note")

# 어긋난 판 : 데이터 행 수와 영상 구간 길이가 안 맞는다 (녹화 중 끊김·인코딩 오류).
#   카메라마다 값이 다르면 두 스트림이 서로 틀어진 것이라 더 나쁘다.
for _, r in df.iterrows():
    i, n = int(r.episode_index), int(r.length)
    hits = {}
    for k in vkeys:
        try:
            seg = round((float(r[f"videos/{k}/to_timestamp"])
                         - float(r[f"videos/{k}/from_timestamp"])) * fps)
        except KeyError:
            continue
        if abs(seg - n) > 1:
            hits[k.rsplit(".", 1)[-1]] = seg
    if not hits:
        continue
    segs = set(hits.values())
    if len(segs) == 1 and len(hits) == len(vkeys):
        seg = segs.pop()
        _flag(i, f"어긋난 판 — 데이터 {n}행 / 영상 {seg}프레임 ({seg-n:+d})")
    else:
        detail = " · ".join(f"{c} {v}프레임({v-n:+d})" for c, v in sorted(hits.items()))
        _flag(i, f"어긋난 판 — 카메라마다 다르다 (데이터 {n}행 · {detail})")

# 영상 구간 겹침 = 녹화 오류로 같은 장면이 두 판에 들어간 것.
#   카메라별로 따로 찍으면 같은 말이 두 번 나오므로 판 짝마다 하나로 합친다.
_dup = {}                                    # (ep1, ep2) -> {cam: (겹침초, 완전동일)}
for key in vkeys:
    try:
        seg = [(int(r.episode_index),
                int(r[f"videos/{key}/chunk_index"]), int(r[f"videos/{key}/file_index"]),
                float(r[f"videos/{key}/from_timestamp"]), float(r[f"videos/{key}/to_timestamp"]))
               for _, r in df.iterrows()]
    except KeyError:
        continue
    seg.sort(key=lambda x: (x[1], x[2], x[3]))
    cam = key.rsplit(".", 1)[-1]
    for (i1, c1, f1, a1, b1), (i2, c2, f2, a2, b2) in zip(seg, seg[1:]):
        if (c1, f1) != (c2, f2):
            continue
        ov = min(b1, b2) - max(a1, a2)
        if ov > 0.05:
            _dup.setdefault((i1, i2), {})[cam] = (ov, abs(a1-a2) < 0.02 and abs(b1-b2) < 0.02)

for (i1, i2), cams in _dup.items():
    allsame = all(v[1] for v in cams.values())
    ov = max(v[0] for v in cams.values())
    what = "완전히 같다" if allsame else f"{ov:.1f}초 겹친다"
    who = "영상" if len(cams) == len(vkeys) else " · ".join(sorted(cams))
    _flag(i1, f"영상 중복 — {who} 구간이 ep {i2} 와 {what}")
    _flag(i2, f"영상 중복 — {who} 구간이 ep {i1} 와 {what}")

# 판 고르기 : "9" 또는 "3-6"
if sel:
    if "-" in sel:
        lo, hi = (int(x) for x in sel.split("-", 1))
        df = df[(df.episode_index >= lo) & (df.episode_index <= hi)]
    else:
        df = df[df.episode_index == int(sel)]
    if df.empty:
        raise SystemExit(f"❌ 그 범위에 판이 없다 : {sel}")

# ⚠ 판을 고른 뒤에 센다 — 거르기 전에 세면 묶음만 열어도 접힌다.
# 편이 많은데 그래프를 다 펼치면 브라우저가 멈춘다 (117편 = 5MB · polyline 1400개).
# 묶음 단위로 볼 때만 펼치고, 많이 열면 접어 둔다.
OPEN_MAX = int(os.environ.get("VIEW_OPEN_MAX", "12"))
BIG      = len(df) > OPEN_MAX
MOT_OPEN = "" if BIG else " open"
VPRELOAD = "none" if BIG else "metadata"

def vpath(key, ep):
    rel = vpat.format(video_key=key,
                      chunk_index=int(ep[f"videos/{key}/chunk_index"]),
                      file_index=int(ep[f"videos/{key}/file_index"]))
    return (root / rel).as_uri()

cards = []
for _, ep in df.iterrows():
    i     = int(ep.episode_index)
    n     = int(ep.length)
    tasks = ", ".join(ep.tasks) if hasattr(ep.tasks, "__iter__") and not isinstance(ep.tasks, str) else str(ep.tasks)

    vids = []
    for key in vkeys:
        a = float(ep[f"videos/{key}/from_timestamp"])
        b = float(ep[f"videos/{key}/to_timestamp"])
        cam = key.rsplit(".", 1)[-1]
        vids.append(
            f'<figure><figcaption>{html.escape(cam)} '
            f'<span class="t">{a:.2f}s → {b:.2f}s</span></figcaption>'
            f'<video controls muted playsinline preload="{VPRELOAD}" '
            f'data-a="{a}" data-b="{b}" src="{vpath(key, ep)}"></video></figure>'
        )

    whys = FLAGS.get(i, [])
    nerr = sum(1 for _, lv in whys if lv == "err")
    odd_cls = ' class="odd"' if nerr else (' class="note"' if whys else '')
    badges = "".join('<span class="flag %s">%s</span>' % (lv, html.escape(w))
                     for w, lv in whys)

    chk = ' checked' if nerr else ''
    cards.append(
        f'<section data-ep="{i}"{odd_cls}><h2>ep {i}{badges}'
        f'<label class="pick"><input type="checkbox" class="ck" value="{i}"{chk}> 지울 판</label>'
        f'</h2>'
        f'<p class="meta">{n} 프레임 · {n / fps:.1f}초 · <code>{html.escape(tasks)}</code></p>'
        f'<div class="row">{"".join(vids)}</div>'
        f'{motor_svg(i)}</section>'
    )

CSS = """
:root{--bg:#fff;--fg:#1a1a1a;--muted:#666;--line:#e3e3e3;--code-bg:#f6f7f8;--accent:#2b6cb0}
@media (prefers-color-scheme:dark){
  :root{--bg:#16181a;--fg:#e6e6e6;--muted:#9aa0a6;--line:#2e3236;--code-bg:#1f2225;--accent:#7db3f0}
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
  font-family:-apple-system,'Noto Sans KR','Malgun Gothic',sans-serif;line-height:1.6}
main{max-width:1100px;margin:0 auto;padding:40px 24px 120px}
h1{font-size:1.7em;margin:0 0 .2em}
.sub{color:var(--muted);margin:0 0 2em;font-size:.95em}
section{border-top:1px solid var(--line);padding:20px 0}
h2{font-size:1.15em;margin:0 0 .2em}
.meta{color:var(--muted);font-size:.9em;margin:0 0 .8em}
.row{display:flex;gap:14px;flex-wrap:wrap}
figure{margin:0;flex:1 1 340px;min-width:280px}
figcaption{font-size:.85em;color:var(--muted);margin-bottom:4px}
.t{opacity:.7}
video{width:100%;border-radius:8px;border:1px solid var(--line);background:#000}
code{background:var(--code-bg);padding:.12em .4em;border-radius:4px;font-size:.9em}

/* 모터 그래프 */
.mot{margin-top:12px}
.mot summary{cursor:pointer;font-size:.88em;color:var(--muted);
  padding:5px 0;user-select:none}
.mot summary::marker{color:var(--muted)}
.lg{margin-left:10px;font-size:.92em}
.lg i{display:inline-block;width:14px;height:0;vertical-align:middle;margin:0 4px 0 10px}
.k-act{border-top:2px solid var(--accent)}
.k-cmd{border-top:2px dashed var(--muted)}
.mgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));
  gap:10px;margin-top:6px}
.mp{border:1px solid var(--line);border-radius:6px;background:var(--code-bg);
  padding:4px 2px}
.mp svg{display:block;width:100%;height:74px}
.mp polyline{fill:none;vector-effect:non-scaling-stroke}
.mp .act{stroke:var(--accent);stroke-width:1.6}
.mp .cmd{stroke:var(--muted);stroke-width:1.1;stroke-dasharray:3 2;opacity:.85}
.mp .jn{font-size:9px;fill:var(--muted)}
.mp .je{font-size:9px;fill:var(--muted);opacity:.8}
.mp .ph{stroke:#d64545;stroke-width:1.2;opacity:0;transition:opacity .15s}
.mot.live .mp .ph{opacity:.9}
.mp{cursor:crosshair}
.mnote{font-size:.8em;color:var(--muted);margin:8px 0 0}
section.odd .mot{opacity:1}

/* 이상한 판 표시 — 지우지 않는다 */
h2{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.pick{margin-left:auto;font-size:.72em;font-weight:400;color:var(--muted);cursor:pointer;
  border:1px solid var(--line);border-radius:6px;padding:2px 9px;user-select:none;white-space:nowrap}
.pick input{vertical-align:-1px;margin-right:5px}
section.sel{background:rgba(214,69,69,.10)}
section.sel .pick{color:#d64545;border-color:#d64545}
.flag{font-size:.68em;font-weight:600;border-radius:6px;padding:2px 8px;white-space:nowrap}
.flag.err{color:#b03030;background:rgba(214,69,69,.12);border:1px solid rgba(214,69,69,.45)}
.flag.note{color:#8a6100;background:rgba(214,158,46,.14);border:1px solid rgba(214,158,46,.5)}
@media (prefers-color-scheme:dark){ .flag.err{color:#ff9d9d} .flag.note{color:#f0c674} }
section.odd{background:rgba(220,60,60,.06)}
section.note{background:rgba(214,158,46,.06)}
body.onlyodd section[data-ep]:not(.odd):not(.note){display:none}

/* 아래 고정 막대 */
#bar{position:fixed;left:0;right:0;bottom:0;z-index:9;
  background:var(--bg);border-top:1px solid var(--line);
  padding:10px 24px;display:flex;gap:18px;align-items:center;flex-wrap:wrap;
  font-size:.92em;box-shadow:0 -2px 10px rgba(0,0,0,.08)}
#bar .grow{flex:1 1 auto}
#sel{font-family:ui-monospace,monospace;background:var(--code-bg);
  padding:.15em .5em;border-radius:4px}
#bar button{font:inherit;padding:5px 12px;border-radius:6px;cursor:pointer;
  border:1px solid var(--line);background:var(--code-bg);color:var(--fg)}
#bar button:hover{border-color:var(--accent);color:var(--accent)}
#bar select{font:inherit;padding:4px 6px;border-radius:6px;
  border:1px solid var(--line);background:var(--code-bg);color:var(--fg)}
#done{color:var(--accent)}
"""

# 이어붙은 mp4 에서 그 판 구간만 반복 재생한다.
# 미디어 프래그먼트(#t=) 대신 JS 로 잡는 이유 : 로컬 파일에서 더 확실하다.
JS = """
// 재생속도 기본 1.5배. 검수는 「이상한 판을 찾는」 작업이라 1배는 느리다.
// playbackRate 는 요소마다 걸어야 하고, 소스를 다시 읽으면 초기화되므로
// loadedmetadata 에서도 한 번 더 건다.
let RATE = 1.5;
const applyRate = () => document.querySelectorAll('video').forEach(v=>v.playbackRate=RATE);

document.querySelectorAll('video').forEach(v=>{
  const a=parseFloat(v.dataset.a), b=parseFloat(v.dataset.b);
  const rewind=()=>{ if(v.currentTime<a-0.05||v.currentTime>b) v.currentTime=a; };
  v.addEventListener('loadedmetadata',()=>{ v.currentTime=a; v.playbackRate=RATE; });
  v.addEventListener('timeupdate',()=>{ if(v.currentTime>=b){ v.currentTime=a; v.pause(); } });
  v.addEventListener('seeked',rewind);
  v.playbackRate = RATE;
});

// ── 이상한 판 ────────────────────────────────────────────────────
// **여기서 아무것도 지우지 않는다.** 찾아서 표시하고 번호를 알려줄 뿐이다.
// 다시 찍을지 그냥 둘지는 사람이 판단한다.
const out  = document.getElementById('sel');
const done = document.getElementById('done');
const picks = () => [...document.querySelectorAll('.ck:checked')]
                      .map(x=>+x.value).sort((a,b)=>a-b);
function refresh(){
  const p = picks();
  out.textContent = p.length ? p.join(',') : '없음';
  document.querySelectorAll('section[data-ep]').forEach(s=>{
    const c = s.querySelector('.ck');
    s.classList.toggle('sel', !!(c && c.checked));
  });
  done.textContent = '';
}
document.addEventListener('change', e=>{ if(e.target.classList.contains('ck')) refresh(); });
refresh();   // 이상한 판은 미리 켜져 있다

document.getElementById('clear').onclick = ()=>{
  document.querySelectorAll('.ck').forEach(x=>x.checked=false); refresh();
};

document.getElementById('copy').onclick = async ()=>{
  const odd = picks();
  if(!odd.length){ done.textContent = '고른 판이 없다'; return; }
  const t = odd.join(',');
  try { await navigator.clipboard.writeText(t); done.textContent = '번호 복사됨'; }
  catch(_) {
    const e=document.createElement('textarea'); e.value=t; document.body.appendChild(e);
    e.select(); try{document.execCommand('copy'); done.textContent='번호 복사됨';}
    catch(__){ done.textContent='복사 실패 — 위 번호를 직접 옮겨라'; }
    e.remove();
  }
};
const only = document.getElementById('only');
only.onclick = ()=>{
  document.body.classList.toggle('onlyodd');
  only.textContent = document.body.classList.contains('onlyodd') ? '전체 보기' : '표시된 판만';
  done.textContent = '';
};
if(!document.querySelector('section.odd, section.note')) only.disabled = true;

document.getElementById('rate').onchange = e=>{ RATE = +e.target.value; applyRate(); };

// ── 두 카메라 영상 묶기 ─────────────────────────────────────────
// 한쪽을 재생하면 다른 쪽도 같은 시점에서 같이 돈다.
// 카메라마다 mp4 안의 구간(a~b)이 달라 진행률(0~1)로 맞춘다.
// 서로 고쳐대는 것을 막으려고 **재생을 시작한 쪽만 기준**으로 삼는다.
document.querySelectorAll('section[data-ep]').forEach(sec=>{
  const vs = [...sec.querySelectorAll('video')];
  if(vs.length < 2) return;
  const rng = v => { const a = parseFloat(v.dataset.a), b = parseFloat(v.dataset.b);
                     return [a, (b - a) || 1]; };
  let lead = null;
  const at = v => { const [a, s] = rng(v); return (v.currentTime - a) / s; };
  const put = (o, p) => { const [a, s] = rng(o); o.currentTime = a + p * s; };

  vs.forEach(v=>{
    v.addEventListener('play', ()=>{
      lead = v;
      const p = at(v);
      vs.forEach(o=>{ if(o===v) return;
        put(o, p); o.playbackRate = RATE; o.play().catch(()=>{}); });
    });
    v.addEventListener('pause', ()=>{
      if(lead !== v) return;
      vs.forEach(o=>{ if(o!==v && !o.paused) o.pause(); });
    });
    v.addEventListener('seeking', ()=>{
      if(lead && lead !== v && !v.paused) return;   // 따라가는 쪽의 seek 는 무시
      lead = v;
      const p = at(v);
      vs.forEach(o=>{ if(o!==v) put(o, p); });
    });
    // 재생 중 어긋나면 되돌린다 (인코딩 차이로 조금씩 밀린다)
    v.addEventListener('timeupdate', ()=>{
      if(lead !== v || v.paused) return;
      const p = at(v);
      vs.forEach(o=>{ if(o===v) return;
        const [a, s] = rng(o); const want = a + p * s;
        if(Math.abs(o.currentTime - want) > 0.25) o.currentTime = want; });
    });
  });
});

// ── 모터 그래프 ↔ 영상 동기 ─────────────────────────────────────
// 영상은 긴 mp4 의 한 구간(a~b)이고 그래프는 그 편의 전체 길이다.
// 둘 다 같은 편을 담으므로 진행률(0~1)로 바로 이어 붙는다.
document.querySelectorAll('section[data-ep]').forEach(sec=>{
  const mot  = sec.querySelector('.mot');
  const grid = sec.querySelector('.mgrid');
  if(!mot || !grid) return;
  const x0 = +grid.dataset.x0, x1 = +grid.dataset.x1;
  const heads = grid.querySelectorAll('.ph');
  const vids  = sec.querySelectorAll('video');

  const move = p => {
    const x = x0 + Math.min(1, Math.max(0, p)) * (x1 - x0);
    heads.forEach(h=>{ h.setAttribute('x1', x); h.setAttribute('x2', x); });
  };

  vids.forEach(v=>{
    const a = parseFloat(v.dataset.a), b = parseFloat(v.dataset.b);
    const span = (b - a) || 1;
    v.addEventListener('timeupdate', ()=>{
      mot.classList.add('live');
      move((v.currentTime - a) / span);
    });
    v.addEventListener('pause', ()=> mot.classList.add('live'));
  });

  // 그래프를 누르면 그 시점으로 영상이 넘어간다.
  grid.querySelectorAll('.mp').forEach(mp=>{
    mp.addEventListener('click', e=>{
      const r = mp.getBoundingClientRect();
      // 패널 안쪽 여백(x0~x1)을 화면 좌표로 환산
      const l = r.left + r.width * (x0 / 250), w = r.width * ((x1 - x0) / 250);
      const p = Math.min(1, Math.max(0, (e.clientX - l) / w));
      mot.classList.add('live');
      move(p);
      vids.forEach(v=>{
        const a = parseFloat(v.dataset.a), b = parseFloat(v.dataset.b);
        v.currentTime = a + p * ((b - a) || 0);
      });
    });
  });
});
refresh();
"""

BAR = ("<div id='bar'>"
       "<span>고른 판 <span id='sel'>없음</span></span>"
       "<button id='copy'>번호 복사</button>"
       "<button id='clear'>선택 해제</button>"
       "<button id='only'>표시된 판만</button>"
       "<span id='done'></span>"
       "<span class='grow'></span>"
       "<label>속도 <select id='rate'>"
       "<option value='1'>1.0x</option>"
       "<option value='1.5' selected>1.5x</option>"
       "<option value='2'>2.0x</option>"
       "<option value='3'>3.0x</option>"
       "</select></label>"
       "</div>")

title = f"{root.name}{f'  ep {sel}' if sel else ''}"
open(out, "w", encoding="utf-8").write(
    f"<!doctype html><html lang='ko'><head><meta charset='utf-8'>"
    f"<meta name='viewport' content='width=device-width,initial-scale=1'>"
    f"<title>{html.escape(title)}</title><style>{CSS}</style></head><body><main>"
    f"<h1>{html.escape(root.name)}</h1>"
    f"<p class='sub'>{'⚠ 편이 많아 모터 그래프를 접어 두었다 (제목을 누르면 펼쳐진다) · ' if BIG else ''}{len(df)}판 표시 · 전체 {info['total_episodes']}판 / {info['total_frames']:,}프레임 · {fps}fps"
    f" · <code>{html.escape(str(root))}</code></p>"
    f"{''.join(cards)}</main>{BAR}<script>{JS}</script></body></html>"
)
print(f"렌더링 완료: {out}  ({len(df)}판)")
PY

if [[ $OPEN -eq 1 ]]; then
  # ⚠ 그냥 열면 Chrome 이 "Opening in existing browser session" 으로 **기존 창에 탭만
  #   만들고 끝난다.** 그 창이 VS Code 뒤에 있으면 열린 줄 모른다 (2026-08-07).
  #   --new-window 는 새 창이라 대개 포커스를 가져온다.
  #   그래도 안 뜨면 VS Code 안에서 보는 쪽을 쓴다 → slot_web (localhost 로 내보낸다)
  edu_open "file://$OUT"
  fi
