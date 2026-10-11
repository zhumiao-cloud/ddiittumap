#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

MAIN_UNIT=sxy-mmul10-multiome-arc-20261010
RUNNER=/home/h3039/PROJECTS/zhumiao/.multiome_arc_runner
PIPE="$RUNNER/arc_multiome_three_samples.sh"
WORK=/home/h3039/PROJECTS/zhumiao/multiome_arc_work/P10MK1_1
GEX="$WORK/input/GEX"
REMOTE='danxibao3_webdav:P10MK1_1/GEX'
MANIFEST="$GEX/md5.md5"
PROXY='http://127.0.0.1:19324'
CHUNK=8388608
PAR=16

test "$(id -un)" = h3039
test -s "$PIPE"
test -s "$MANIFEST"
ss -ltn | grep -q '127.0.0.1:19324'
export HTTPS_PROXY="$PROXY"
export https_proxy="$PROXY"

echo "RESUME_BEGIN=$(date -Is)"
systemctl --user stop "$MAIN_UNIT" 2>/dev/null || true
sleep 2
if pgrep -f 'rclone copy danxibao3_webdav:P10MK1_1/GEX' >/dev/null 2>&1; then
  echo ERROR_OLD_GEX_COPY_STILL_RUNNING >&2
  exit 30
fi

resume_one() {
  local f="$1" expected remote_size local_size chunkdir
  expected="$(awk -v f="$f" '$2==f{print $1}' "$MANIFEST" | head -n1)"
  test -n "$expected"
  remote_size="$(rclone lsl "$REMOTE/$f" | awk 'NR==1{print $1}')"
  local_size="$(stat -c %s "$GEX/$f")"
  test "$local_size" -le "$remote_size"
  echo "FILE=$f LOCAL=$local_size REMOTE=$remote_size REMAIN=$((remote_size-local_size))"

  if [ "$local_size" -lt "$remote_size" ]; then
    chunkdir="$WORK/.resume_chunks/$f"
    rm -rf "$chunkdir"
    mkdir -p "$chunkdir"
    python3 - "$local_size" "$remote_size" "$CHUNK" "$chunkdir/plan.tsv" <<'PY'
import sys
start,end,chunk=map(int,sys.argv[1:4]); out=sys.argv[4]
with open(out,"w") as h:
    i=0; off=start
    while off<end:
        n=min(chunk,end-off)
        h.write(f"{i:08d}\t{off}\t{n}\n")
        i+=1; off+=n
PY
    export REMOTE_FILE="$REMOTE/$f" CHUNKDIR="$chunkdir"
    xargs -P "$PAR" -n 3 bash -c '
      set -euo pipefail
      idx="$1"; off="$2"; cnt="$3"
      out="$CHUNKDIR/chunk.$idx"
      if [ -s "$out" ] && [ "$(stat -c %s "$out")" = "$cnt" ]; then exit 0; fi
      rm -f "$out" "$out.tmp"
      for try in 1 2 3 4; do
        if timeout 240 rclone cat "$REMOTE_FILE" --offset "$off" --count "$cnt" > "$out.tmp" &&
           [ "$(stat -c %s "$out.tmp")" = "$cnt" ]; then
          mv "$out.tmp" "$out"
          exit 0
        fi
        rm -f "$out.tmp"
        sleep $((try*2))
      done
      exit 41
    ' _ < "$chunkdir/plan.tsv"

    planned="$(awk '{s+=$3} END{print s+0}' "$chunkdir/plan.tsv")"
    got="$(find "$chunkdir" -type f -name 'chunk.*' -printf '%s\n' | awk '{s+=$1} END{print s+0}')"
    test "$planned" = "$got"
    orig="$local_size"
    find "$chunkdir" -type f -name 'chunk.*' -print0 | sort -z | xargs -0 cat >> "$GEX/$f"
    if [ "$(stat -c %s "$GEX/$f")" != "$remote_size" ]; then
      truncate -s "$orig" "$GEX/$f"
      echo ERROR_FINAL_SIZE_MISMATCH="$f" >&2
      exit 42
    fi
  fi

  actual="$(md5sum "$GEX/$f" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "ERROR_MD5_MISMATCH=$f expected=$expected actual=$actual" >&2
    exit 43
  fi
  gzip -t "$GEX/$f"
  echo "GEX_FILE_VERIFIED=$f md5=$actual"
  rm -rf "$WORK/.resume_chunks/$f"
}

resume_one P10-zc_S1_L001_R1_001.fastq.gz
resume_one P10-zc_S1_L001_R2_001.fastq.gz
echo GEX_RESUME_VERIFIED=PASS

backup="$PIPE.pre_proxy_resume_20261011"
[ -e "$backup" ] || cp -p "$PIPE" "$backup"
python3 - "$PIPE" <<'PY'
import sys
p=sys.argv[1]
s=open(p,encoding="utf-8").read()
marker='REMOTE=danxibao3_webdav:\n'
if 'MULTIOME_PROXY_PATCH_20261011' not in s:
    assert marker in s
    s=s.replace(marker, marker+'# MULTIOME_PROXY_PATCH_20261011\nexport HTTPS_PROXY=http://127.0.0.1:19324\nexport https_proxy=http://127.0.0.1:19324\n',1)

old='''  if [ -e "$TARGET" ]; then
    echo "存在未完成的临时目录，停止以避免覆盖：$TARGET" >&2
    exit 24
  fi
  # 只允许本脚本独占其特定新目录。
  mkdir -m 700 "$TARGET"
  mkdir -p "$TARGET/input/GEX" "$TARGET/input/ATAC" "$TARGET/pipeline"'''
new='''  if [ -e "$TARGET" ]; then
    test -d "$TARGET"
    test "$(stat -c %U "$TARGET")" = h3039
    echo "RESUME_EXISTING_TARGET=$TARGET"
  else
    mkdir -m 700 "$TARGET"
  fi
  mkdir -p "$TARGET/input/GEX" "$TARGET/input/ATAC" "$TARGET/pipeline"'''
if old in s: s=s.replace(old,new,1)

s=s.replace('rclone copy "${REMOTE}$SAMPLE/GEX" "$TARGET/input/GEX" --transfers 3 --checkers 6 --retries 5',
'''rclone copy "${REMOTE}$SAMPLE/GEX" "$TARGET/input/GEX" --size-only --transfers 8 --checkers 16 \\
    --multi-thread-streams 8 --multi-thread-cutoff 64M --multi-thread-chunk-size 16M --retries 5''')
s=s.replace('rclone copy "${REMOTE}$SAMPLE/ATAC" "$TARGET/input/ATAC" --transfers 3 --checkers 6 --retries 5',
'''rclone copy "${REMOTE}$SAMPLE/ATAC" "$TARGET/input/ATAC" --size-only --transfers 8 --checkers 16 \\
    --multi-thread-streams 8 --multi-thread-cutoff 64M --multi-thread-chunk-size 16M --retries 5''')

old2='''    test -f "$ZERO" && test ! -s "$ZERO" && test -s "$CONFLICT" || {
      echo "P10MK2 index 文件状态与历史盘点不符，禁止自动修复" >&2; exit 26;
    }
    rm -- "$ZERO"            # 仅删除临时拷贝中的 0 字节占位文件
    mv -- "$CONFLICT" "$ZERO" # 仅修改临时拷贝文件名'''
new2='''    if [ -s "$ZERO" ] && [ ! -e "$CONFLICT" ]; then
      echo "P10MK2_I1_ALREADY_REPAIRED=YES"
    elif [ -f "$ZERO" ] && [ ! -s "$ZERO" ] && [ -s "$CONFLICT" ]; then
      rm -- "$ZERO"
      mv -- "$CONFLICT" "$ZERO"
      echo "P10MK2_I1_REPAIRED=YES"
    else
      echo "P10MK2 index 文件状态与预期不符，停止" >&2
      exit 26
    fi'''
if old2 in s: s=s.replace(old2,new2,1)

open(p,"w",encoding="utf-8").write(s)
PY
bash -n "$PIPE"
grep -q MULTIOME_PROXY_PATCH_20261011 "$PIPE"
grep -q -- '--multi-thread-streams 8' "$PIPE"
grep -q 'RESUME_EXISTING_TARGET' "$PIPE"
echo PIPE_PATCH_VALIDATED=PASS

systemctl --user reset-failed "$MAIN_UNIT" 2>/dev/null || true
systemctl --user restart "$MAIN_UNIT"
sleep 5
systemctl --user show "$MAIN_UNIT" -p ActiveState -p SubState -p Result -p ExecMainStatus --no-pager
journalctl --user -u "$MAIN_UNIT" --no-pager --output=cat -n 35 | tail -n 35
echo "RESUME_SERVICE_COMPLETE=$(date -Is)"
