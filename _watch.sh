#!/usr/bin/env bash
# =============================================================================
#  train-watch.sh — 학습 로그를 그래프로 본다 (Chrome 탭, 전부 로컬)
#
#  사용:
#    bash _watch.sh <학습로그파일>
#    bash _watch.sh <로그> --follow      # 20초마다 갱신
#    bash _watch.sh <로그> --no-open     # HTML 만 생성
#
#  ⚠ W&B 는 학습을 **시작할 때** --wandb.enable=true 를 줘야 붙는다.
#    이미 도는 학습에는 못 붙이므로, stdout 로그에서 뽑는 이 도구가 대안이다.
#    다음부터 처음부터 W&B 를 쓸 거면 학습 명령에 그 플래그를 넣으면 된다.
#
#  읽는 것 : lerobot-train 이 log_freq(기본 200)마다 출력하는 INFO 줄
#    step:200 smpl:3K ep:7 epch:0.04 loss:0.360 grdn:4.323 lr:1.0e-05 ...
#    같은 물리 줄 앞에 tqdm 이 "| 200/60000 [00:35<2:51:36, 5.81step/s]" 를 붙인다.
#    step 값은 10000 을 넘으면 "10K" 로 뭉개지므로 **tqdm 쪽 숫자를 우선** 쓴다.
#
#  색은 dataviz 규격서의 검증된 카테고리 슬롯 1(파랑)을 그대로 인용했다.
#  차트마다 계열이 하나라 인접 쌍 검사가 걸릴 자리가 없다.
# =============================================================================

set -euo pipefail

# 같은 폴더의 config.sh 에서 값을 받는다 — 폴더째 옮겨도 돈다.
_SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck disable=SC1091
source "$_SELF_DIR/config.sh"

OPEN=1
FOLLOW=0
INTERVAL=20
LOGS=()
for a in "$@"; do
    case "$a" in
        --no-open) OPEN=0 ;;
        --follow)  FOLLOW=1 ;;
        --interval=*) INTERVAL="${a#*=}" ;;
        -*) echo "❌ 알 수 없는 옵션 : $a" >&2; exit 2 ;;
        *)  [ -f "$a" ] || { echo "❌ 파일 없음 : $a" >&2; exit 2; }
            LOGS+=("$a") ;;
    esac
done

if [ ${#LOGS[@]} -eq 0 ]; then
    echo "사용법 : train-watch.sh <학습로그파일...> [--follow] [--no-open] [--interval=N]" >&2
    echo "  이어학습이면 로그 여러 개를 순서대로 지정하세요 :" >&2
    echo "    train-watch.sh 1차.log 재개.log --follow" >&2
    exit 2
fi

# 마지막 로그가 현재 실행 중인 학습이다 — 갱신 감시와 파일명은 이걸 기준으로 한다
LOG="${LOGS[${#LOGS[@]}-1]}"

OUT_DIR="/tmp/trainwatch"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$(basename "${LOG%.*}").html"

# shellcheck disable=SC1091
source "$_SELF_DIR/_env.sh"; edu_activate || exit 1

render() {
LOGS="$(printf '%s\n' "${LOGS[@]}")" OUT="$OUT" FOLLOW="$FOLLOW" INTERVAL="$INTERVAL" python3 <<'PY'
import os, re, json, html
from pathlib import Path

logs     = [Path(p) for p in os.environ["LOGS"].splitlines() if p]
out      = os.environ["OUT"]
follow   = os.environ["FOLLOW"] == "1"
interval = int(os.environ["INTERVAL"])

# tqdm 진행부 : "| 12345/60000 [01:23<2:51:36,  5.81step/s]"
PROG = re.compile(r"\|\s*(\d+)/(\d+)\s*\[([\d:]+)<([\d:?]+),\s*([\d.]+)\s*step/s")
NUM  = re.compile(r"(?<![\w.])(step|epch|loss|grdn|lr|mem_gb|smp/s|updt_s|data_s):"
                  r"([0-9]*\.?[0-9]+(?:[eE][-+]?\d+)?[KMG]?)")
CFG_STEPS = re.compile(r"'steps':\s*(\d+)")

def num(v):
    m = {"K": 1e3, "M": 1e6, "G": 1e9}
    return float(v[:-1]) * m[v[-1]] if v and v[-1] in m else float(v)

# ⚠ 이어학습(--resume)이면 tqdm 이 **이번 실행분만** 센다 (예: 832/10000 인데 실제는 20,832).
#   INFO 의 step: 은 전역 값이지만 10,000 을 넘으면 "21K" 로 뭉개져 못 쓴다.
#   설정의 steps 와 tqdm 총량의 차가 곧 시작 지점이다 — 반올림 없이 정확하다.
#     1차   : 설정 60,000 · tqdm 총량 60,000 → 보정 0
#     재개  : 설정 30,000 · tqdm 총량 10,000 → 보정 20,000
rows, total, eta, rate, elapsed, cur = [], None, None, None, None, 0
for log in logs:
    raw = log.read_bytes().decode("utf-8", "replace").replace("\r", "\n")
    lines = raw.split("\n")

    cfg = CFG_STEPS.search(raw)
    tq  = None
    for line in reversed(lines):
        m = PROG.search(line)
        if m:
            tq = m
            break
    offset = int(cfg.group(1)) - int(tq.group(2)) if (cfg and tq) else 0

    for line in lines:
        if "loss:" not in line:
            continue
        d = {k: num(v) for k, v in NUM.findall(line)}
        p = PROG.search(line)
        if not p:
            continue
        d["step"] = float(offset + int(p.group(1)))
        if "loss" in d:
            rows.append(d)

    if tq:   # 진행 상황은 마지막 로그의 마지막 tqdm 줄이 최신이다
        cur   = offset + int(tq.group(1))
        total = int(cfg.group(1)) if cfg else int(tq.group(2))
        elapsed, eta, rate = tq.group(3), tq.group(4), float(tq.group(5))

# 같은 step 이 여러 로그에 겹치면 (재개 지점 근처) 나중 것을 남긴다
seen = {}
for r in rows:
    seen[r["step"]] = r
rows = [seen[k] for k in sorted(seen)]

# 학습률 설명은 정책마다 다르다 — 로그에 출력된 값으로 판단한다.
#   ACT 는 스케줄러가 없어(get_scheduler_preset -> None) 값이 고정이다.
#   SmolVLA 등은 warmup + cosine decay 라 올랐다 내려간다.
_lrv = sorted({r["lr"] for r in rows if "lr" in r})
if not _lrv:
    _lrnote = "기록 없음"
elif len(_lrv) == 1:
    _lrnote = f"고정 {_lrv[0]:.1e} — 스케줄러가 없어 평평한 게 정상 (ACT 기본값)"
else:
    _lrnote = "warmup 뒤 cosine decay — 올랐다 내려가는 게 정상"

SERIES = [
    ("loss",   "손실 (loss)",            "낮을수록 좋다. 평평해지면 더 돌려도 크게 안 나아진다"),
    ("grdn",   "기울기 크기 (grad norm)", "치솟으면 학습이 불안정하다는 신호"),
    ("lr",     "학습률 (learning rate)",  _lrnote),
]
data = {k: [[r["step"], r[k]] for r in rows if k in r] for k, _, _ in SERIES}

def fmt_num(v, k):
    if k == "lr":
        return f"{v:.2e}"
    return f"{v:,.3f}" if abs(v) < 1000 else f"{v:,.0f}"

last = rows[-1] if rows else {}
tiles = [
    ("진행",     f"{cur:,} / {total:,}" if total else f"{cur:,}",
                 f"{cur/total*100:.1f}%" if total else ""),
    ("에폭",     f"{last.get('epch', 0):.2f}", "데이터를 몇 번 훑었나"),
    ("손실",     fmt_num(last.get("loss", 0), "loss"), "최근 기록"),
    ("남은 시간", eta or "—", f"경과 {elapsed}" if elapsed else ""),
    ("속도",     f"{rate:.2f} step/s" if rate else "—",
                 f"{last.get('smp/s', 0):.0f} smp/s" if "smp/s" in last else ""),
    ("VRAM",     f"{last.get('mem_gb', 0):.2f} GB", "학습 프로세스 기준"),
]

CSS = """
*{box-sizing:border-box}
.viz-root{
  color-scheme:light;
  --plane:#f9f9f7; --surface-1:#fcfcfb;
  --text-primary:#0b0b0b; --text-secondary:#52514e; --muted:#898781;
  --grid:#e1e0d9; --axis:#c3c2b7; --border:rgba(11,11,11,0.10);
  --series-1:#2a78d6;
}
@media (prefers-color-scheme:dark){
  :root:where(:not([data-theme="light"])) .viz-root{
    color-scheme:dark;
    --plane:#0d0d0d; --surface-1:#1a1a19;
    --text-primary:#fff; --text-secondary:#c3c2b7; --muted:#898781;
    --grid:#2c2c2a; --axis:#383835; --border:rgba(255,255,255,0.10);
    --series-1:#3987e5;
  }
}
:root[data-theme="dark"] .viz-root{
  color-scheme:dark;
  --plane:#0d0d0d; --surface-1:#1a1a19;
  --text-primary:#fff; --text-secondary:#c3c2b7; --muted:#898781;
  --grid:#2c2c2a; --axis:#383835; --border:rgba(255,255,255,0.10);
  --series-1:#3987e5;
}
body{margin:0;background:var(--plane);color:var(--text-primary);
  font-family:system-ui,-apple-system,"Segoe UI","Noto Sans KR",sans-serif;line-height:1.6}
main{max-width:1040px;margin:0 auto;padding:36px 24px 96px}
h1{font-size:1.5em;margin:0 0 .15em}
.sub{color:var(--text-secondary);font-size:.9em;margin:0 0 28px}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:28px}
.tile{background:var(--surface-1);border:1px solid var(--border);border-radius:10px;padding:14px 16px}
.tile .k{font-size:.78em;color:var(--text-secondary);letter-spacing:.02em}
.tile .v{font-size:1.55em;font-weight:600;margin:.1em 0 .05em}
.tile .n{font-size:.78em;color:var(--text-secondary)}
figure{background:var(--surface-1);border:1px solid var(--border);border-radius:10px;
  padding:18px 18px 8px;margin:0 0 18px}
figcaption{font-size:1em;font-weight:600;margin-bottom:.1em}
figcaption .why{display:block;font-weight:400;font-size:.82em;color:var(--text-secondary);margin-top:.15em}
svg{display:block;width:100%;height:auto;overflow:visible}
.gl{stroke:var(--grid);stroke-width:1}
.ax{stroke:var(--axis);stroke-width:1}
/* 눈금 글자는 muted(#898781) 가 아니라 secondary 를 쓴다.
   규격서가 #898781 을 "축·라벨" 역할로 배정해 뒀지만, 실제로 재보면
   라이트 표면에서 3.50:1 로 텍스트 기준 4.5:1 에 못 미친다(검증기 실측).
   격자·축 '선'은 recessive 해야 맞지만 눈금 '글자'는 읽으라고 있는 것이라
   대비를 우선했다. secondary = 7.73:1(light) / 9.72:1(dark) 로 통과. */
.tk{fill:var(--text-secondary);font-size:11px;font-variant-numeric:tabular-nums}
.ln{fill:none;stroke:var(--series-1);stroke-width:2;stroke-linejoin:round;stroke-linecap:round}
.hit{fill:transparent}
.cross{stroke:var(--axis);stroke-width:1;visibility:hidden}
.dot{fill:var(--series-1);stroke:var(--surface-1);stroke-width:2;visibility:hidden}
.tip{position:fixed;pointer-events:none;background:var(--surface-1);color:var(--text-primary);
  border:1px solid var(--border);border-radius:8px;padding:7px 10px;font-size:.82em;
  box-shadow:0 4px 14px rgba(0,0,0,.14);visibility:hidden;z-index:9;white-space:nowrap}
details{background:var(--surface-1);border:1px solid var(--border);border-radius:10px;padding:12px 16px}
summary{cursor:pointer;font-weight:600}
table{border-collapse:collapse;width:100%;font-size:.86em;margin-top:12px;
  font-variant-numeric:tabular-nums}
th,td{border-bottom:1px solid var(--grid);padding:6px 10px;text-align:right}
th:first-child,td:first-child{text-align:left}
th{color:var(--text-secondary);font-weight:600;text-align:right}
.foot{color:var(--text-secondary);font-size:.8em;margin-top:24px}
svg:focus{outline:2px solid var(--series-1);outline-offset:3px}
"""

JS = """
const D = window.__D__;
const tip = document.createElement('div');
tip.className='tip'; document.body.appendChild(tip);

function draw(key, el){
  const pts = D[key]; if(!pts || pts.length<2){ el.innerHTML=''; return; }
  const W=940,H=210,L=62,R=14,T=12,B=30;
  const xs=pts.map(p=>p[0]), ys=pts.map(p=>p[1]);
  const x0=Math.min(...xs), x1=Math.max(...xs);
  let y0=Math.min(...ys), y1=Math.max(...ys);
  // 값이 내내 같으면(ACT 의 lr) 0~1 로 벌리지 않는다 — 선이 바닥에 붙어 버린다.
  if(y1===y0){ const v=Math.abs(y0)||1; y0-=v*0.1; y1+=v*0.1; }
  else { const pad=(y1-y0)*0.12; y0-=pad; y1+=pad; }
  if(key!=='lr' && y0<0) y0=0;
  const X=v=>L+(v-x0)/(x1-x0||1)*(W-L-R);
  const Y=v=>T+(1-(v-y0)/(y1-y0||1))*(H-T-B);
  const fy=v=> key==='lr'? v.toExponential(1) : (Math.abs(v)<10? v.toFixed(3): v.toLocaleString());
  const fx=v=> v>=1000? (v/1000).toFixed(v%1000?1:0)+'k' : String(v);

  let g='';
  for(let i=0;i<=4;i++){ const v=y0+(y1-y0)*i/4, y=Y(v);
    g+=`<line class="gl" x1="${L}" y1="${y}" x2="${W-R}" y2="${y}"/>`;
    g+=`<text class="tk" x="${L-8}" y="${y+4}" text-anchor="end">${fy(v)}</text>`; }
  for(let i=0;i<=5;i++){ const v=x0+(x1-x0)*i/5, x=X(v);
    g+=`<text class="tk" x="${x}" y="${H-8}" text-anchor="middle">${fx(Math.round(v))}</text>`; }
  g+=`<line class="ax" x1="${L}" y1="${H-B}" x2="${W-R}" y2="${H-B}"/>`;
  g+=`<path class="ln" d="${pts.map((p,i)=>(i?'L':'M')+X(p[0])+' '+Y(p[1])).join(' ')}"/>`;
  g+=`<line class="cross" y1="${T}" y2="${H-B}"/><circle class="dot" r="4"/>`;
  g+=`<rect class="hit" x="${L}" y="${T}" width="${W-L-R}" height="${H-T-B}"/>`;
  el.setAttribute('viewBox',`0 0 ${W} ${H}`);
  el.innerHTML=g;

  const cross=el.querySelector('.cross'), dot=el.querySelector('.dot');
  const hit=el.querySelector('.hit');
  let cur=pts.length-1;

  // 마우스와 키보드가 **같은 표시**를 낸다. 좌표를 안 주면(키보드) 점 위치에서 계산한다.
  const mark=(i,cx,cy)=>{
    cur=Math.max(0,Math.min(pts.length-1,i));
    const p=pts[cur], r=el.getBoundingClientRect();
    const px=r.left+X(p[0])/W*r.width, py=r.top+Y(p[1])/H*r.height;
    cross.setAttribute('x1',X(p[0])); cross.setAttribute('x2',X(p[0]));
    cross.style.visibility='visible';
    dot.setAttribute('cx',X(p[0])); dot.setAttribute('cy',Y(p[1]));
    dot.style.visibility='visible';
    tip.innerHTML=`step ${p[0].toLocaleString()}<br><b>${fy(p[1])}</b>`;
    tip.style.visibility='visible';
    tip.style.left=Math.min((cx??px)+14, innerWidth-140)+'px';
    tip.style.top=((cy??py)-46)+'px';
    el.setAttribute('aria-label',`${el.dataset.t} — step ${p[0].toLocaleString()}, ${fy(p[1])}`);
  };
  const nearest=e=>{
    const r=el.getBoundingClientRect(), sx=(e.clientX-r.left)/r.width*W;
    const v=x0+(sx-L)/(W-L-R)*(x1-x0);
    let best=0,bd=Infinity;
    pts.forEach((p,i)=>{const d=Math.abs(p[0]-v); if(d<bd){bd=d;best=i;}});
    mark(best,e.clientX,e.clientY);
  };
  const hide=()=>{cross.style.visibility='hidden';dot.style.visibility='hidden';
                  tip.style.visibility='hidden';};
  hit.addEventListener('mousemove',nearest);
  hit.addEventListener('mouseleave',hide);
  el.addEventListener('focus',()=>mark(cur));
  el.addEventListener('blur',hide);
  el.addEventListener('keydown',ev=>{
    const k=ev.key, n=pts.length;
    if(k==='ArrowRight')      mark(cur+1);
    else if(k==='ArrowLeft')  mark(cur-1);
    else if(k==='Home')       mark(0);
    else if(k==='End')        mark(n-1);
    else if(k==='Escape')   { hide(); return; }
    else return;
    ev.preventDefault();
  });
}
document.querySelectorAll('svg[data-k]').forEach(el=>draw(el.dataset.k, el));
"""

figs = "".join(
    f'<figure><figcaption>{html.escape(t)}'
    f'<span class="why">{html.escape(w)}</span></figcaption>'
    f'<svg data-k="{k}" data-t="{html.escape(t)}" tabindex="0" role="img"'
    f' aria-label="{html.escape(t)}"></svg></figure>'
    for k, t, w in SERIES
)
tile_html = "".join(
    f'<div class="tile"><div class="k">{html.escape(k)}</div>'
    f'<div class="v">{html.escape(str(v))}</div>'
    f'<div class="n">{html.escape(str(n))}</div></div>'
    for k, v, n in tiles
)
tail = rows[-40:]
table = (
    "<table><thead><tr><th>step</th><th>epoch</th><th>loss</th><th>grad norm</th>"
    "<th>lr</th><th>VRAM(GB)</th></tr></thead><tbody>"
    + "".join(
        f"<tr><td>{int(r.get('step',0)):,}</td><td>{r.get('epch',0):.2f}</td>"
        f"<td>{r.get('loss',0):.4f}</td><td>{r.get('grdn',0):.3f}</td>"
        f"<td>{r.get('lr',0):.2e}</td><td>{r.get('mem_gb',0):.2f}</td></tr>"
        for r in tail)
    + "</tbody></table>"
)

meta = f'<meta http-equiv="refresh" content="{interval}">' if follow else ""
Path(out).write_text(
    "<!doctype html><html lang='ko'><head><meta charset='utf-8'>"
    "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    f"{meta}<title>학습 감시 — {html.escape(logs[-1].stem)}</title>"
    f"<style>{CSS}</style></head><body class='viz-root'><main>"
    f"<h1>학습 감시</h1>"
    f"<p class='sub'>로그 {len(logs)}개 ({html.escape(' · '.join(l.stem for l in logs))}) "
    f"· 지표 {len(rows)}개 "
    f"{'· 20초마다 자동 갱신' if follow else '· 정지 화면'}</p>"
    f"<div class='tiles'>{tile_html}</div>{figs}"
    f"<details><summary>표로 보기 (최근 40개)</summary>{table}</details>"
    f"<p class='foot'>lerobot-train 이 log_freq 마다 출력하는 stdout 을 읽는다. "
    f"W&amp;B 없이 동작하며 전부 로컬 처리다.</p>"
    f"</main><script>window.__D__={json.dumps(data)};{JS}</script></body></html>",
    encoding="utf-8")
print(f"지표 {len(rows)}개 · step {cur:,}/{total:,} → {out}" if total
      else f"지표 {len(rows)}개 → {out}")
PY
}

render
if [ "$OPEN" -eq 1 ]; then
    # --new-window 로 연다. 그냥 열면 기존 창에 탭만 만들고 끝나서, 그 창이 뒤에 있으면
    # 열린 줄 모른다 (2026-08-07 drum3-view.sh 에서 같은 문제가 났다).
    # ⚠ 뒤에 ?t=… 를 붙인다. 안 붙이면 같은 file:// 주소라 **Chrome 이 캐시된 옛 화면을
    #   그대로 보여준다** — 스크립트가 파일을 다시 써도 갱신이 안 된 것처럼 보인다
    #   (2026-08-11 실제로 그랬다).
    edu_open "file://$OUT?t=$(date +%s)"
        [ "$FOLLOW" -eq 1 ] \
        && echo "  ${INTERVAL:-20}초마다 자동 갱신" \
        || echo "  ⚠ 정지 화면 — 자동 갱신 : --follow · 수동 갱신 : 해당 탭에서 F5"
fi

if [ "$FOLLOW" -eq 1 ]; then
    echo "${INTERVAL}초마다 갱신 · 종료 : Ctrl+C"
    echo "로그가 ${IDLE_STOP:-5}회 연속 늘지 않으면 (학습 종료로 판단) 자동 종료"
    # 갱신 비용은 실측 무시할 수준이다 — 60초에 198회를 때려박아도 학습이 3% 느려졌고,
    # 20초 간격이면 그 3분의 1이라 스텝 편차에 묻힌다. GPU 는 전혀 쓰지 않는다.
    # 그래도 루프를 영원히 두지는 않는다. 학습이 끝나면 로그가 안 늘므로 그때 빠져나간다.
    idle=0
    prev=$(stat -c %s "$LOG")
    while sleep "$INTERVAL"; do
        now=$(stat -c %s "$LOG" 2>/dev/null || echo "$prev")
        if [ "$now" = "$prev" ]; then
            idle=$(( idle + 1 ))
            if [ "$idle" -ge "${IDLE_STOP:-5}" ]; then
                render >/dev/null
                echo "로그가 $(( IDLE_STOP_S = ${IDLE_STOP:-5} * INTERVAL ))초 동안 늘지 않음 — 갱신 종료"
                echo "마지막 상태 : file://$OUT"
                break
            fi
        else
            idle=0
        fi
        prev=$now
        render >/dev/null
    done
fi
