#!/usr/bin/env python3
"""_camview.py — 화면이 top 인지 wrist 인지 그림으로 판별한다.

  왜 필요한가 : 이름만 맞으면 대조를 통과하지만, 카메라를 반대로 꽂으면
  `top` 키에 손목 화면이 들어간다. 학습·롤아웃이 조용히 망가진다.

  근거 : 상단은 책상·종이·물체·배선이 다 보여 윤곽이 복잡하고(1700~1900),
  손목은 흰 종이 클로즈업이라 거의 밋밋하다(130 안팎). 10배 넘게 벌어진다.

  쓰기 :  _camview.py dataset <루트>        데이터셋의 카메라별 복잡도
          _camview.py image <파일...>       사진 파일별 복잡도
  나오는 것 : `<이름> <복잡도>` 한 줄씩, 마지막에 `SUGGEST_TOP=<이름>`
"""
import sys, os, json, glob, subprocess, tempfile

def complexity(paths):
    import cv2, numpy as np
    v = []
    for p in paths:
        im = cv2.imread(p, cv2.IMREAD_GRAYSCALE)
        if im is None: continue
        v.append(cv2.Laplacian(im, cv2.CV_64F).var())
    return float(np.mean(v)) if v else 0.0

def from_dataset(root):
    info = json.load(open(f"{root}/meta/info.json"))
    vp = info["video_path"]
    out = {}
    for k in [k for k in info["features"] if k.startswith("observation.images.")]:
        cam = k.rsplit(".", 1)[-1]
        src = os.path.join(root, vp.format(video_key=k, chunk_index=0, file_index=0))
        if not os.path.exists(src): continue
        with tempfile.TemporaryDirectory() as d:
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", "2", "-i", src,
                            "-vf", "fps=4,scale=160:120", "-frames:v", "12", f"{d}/%03d.png"],
                           check=False)
            out[cam] = complexity(sorted(glob.glob(f"{d}/*.png")))
    return out

def main():
    if len(sys.argv) < 3: print(__doc__); return 2
    mode = sys.argv[1]
    if mode == "dataset":
        res = from_dataset(sys.argv[2])
    else:
        res = {os.path.basename(p): complexity([p]) for p in sys.argv[2:]}
    for k, v in res.items(): print(f"{k} {v:.1f}")
    if res: print("SUGGEST_TOP=" + max(res, key=res.get))
    return 0

if __name__ == "__main__":
    sys.exit(main())
