#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

SAMPLE="${1:?sample}"
LIB="${2:?library}"
PREFIX="${3:?prefix}"
DEST="${4:?destination}"
REMOTE="danxibao3_webdav:$SAMPLE/$LIB"
PROXY='http://127.0.0.1:19324'
CHUNK=67108864
PAR=24

case "$SAMPLE" in P10MK1_1|P10MK2|P20MK3) ;; *) exit 20;; esac
case "$LIB" in GEX|ATAC) ;; *) exit 21;; esac
mkdir -p "$DEST" "$DEST/.stage_chunks"
export HTTPS_PROXY="$PROXY" https_proxy="$PROXY"
export NO_PROXY=localhost,127.0.0.1 no_proxy=localhost,127.0.0.1

MANIFEST="$DEST/.source_md5.md5"
if timeout 30 rclone cat "$REMOTE/md5.md5" > "$MANIFEST.tmp" 2>/dev/null &&
   grep -Eq '^[0-9a-fA-F]{32}[[:space:]]+' "$MANIFEST.tmp"; then
  mv -f "$MANIFEST.tmp" "$MANIFEST"
  echo "SOURCE_MD5_MANIFEST=YES sample=$SAMPLE lib=$LIB"
else
  rm -f "$MANIFEST.tmp" "$MANIFEST"
  echo "SOURCE_MD5_MANIFEST=NO sample=$SAMPLE lib=$LIB"
fi

stage_one() {
  local source_name="$1" target_name="$2" remote_file target remote_size expected actual chunkdir plan tmp planned got bad
  remote_file="$REMOTE/$source_name"
  target="$DEST/$target_name"
  remote_size="$(timeout 90 rclone lsl "$remote_file" | awk 'NR==1{print $1}')"
  test -n "$remote_size"
  test "$remote_size" -gt 1000000
  expected=""
  if [ -s "$MANIFEST" ]; then
    expected="$(awk -v f="$source_name" '$2==f{print $1}' "$MANIFEST" | head -n1)"
  fi
  echo "STAGE_FILE=$SAMPLE/$LIB/$source_name target=$target_name bytes=$remote_size md5_known=$([ -n "$expected" ] && echo YES || echo NO)"

  if [ -s "$target" ] && [ "$(stat -c %s "$target")" = "$remote_size" ] && gzip -t "$target" 2>/dev/null; then
    if [ -n "$expected" ]; then
      actual="$(md5sum "$target" | awk '{print $1}')"
      if [ "$actual" = "$expected" ]; then echo "STAGE_ALREADY_VERIFIED=$target_name"; return; fi
    else
      echo "STAGE_ALREADY_VERIFIED_SIZE_CRC=$target_name"
      return
    fi
  fi

  chunkdir="$DEST/.stage_chunks/$target_name"
  plan="$chunkdir/plan.tsv"
  mkdir -p "$chunkdir"
  python3 - "$remote_size" "$CHUNK" "$plan" <<'PY'
import sys
end,chunk=map(int,sys.argv[1:3]); out=sys.argv[3]
with open(out,"w") as h:
    for i,off in enumerate(range(0,end,chunk)):
        n=min(chunk,end-off)
        h.write(f"{i:08d}\t{off}\t{n}\n")
PY
  export REMOTE_FILE="$remote_file" CHUNKDIR="$chunkdir"
  xargs -P "$PAR" -n 3 bash -c '
    set -euo pipefail
    idx="$1"; off="$2"; cnt="$3"
    out="$CHUNKDIR/chunk.$idx"
    if [ -s "$out" ] && [ "$(stat -c %s "$out")" = "$cnt" ]; then exit 0; fi
    rm -f "$out" "$out.tmp"
    for try in 1 2 3 4 5 6 7 8; do
      if timeout 600 rclone cat "$REMOTE_FILE" --offset "$off" --count "$cnt" > "$out.tmp" &&
         [ "$(stat -c %s "$out.tmp")" = "$cnt" ]; then
        mv "$out.tmp" "$out"; exit 0
      fi
      rm -f "$out.tmp"
      sleep $((try*3))
    done
    exit 41
  ' _ < "$plan"

  planned="$(awk '{s+=$3} END{print s+0}' "$plan")"
  got="$(find "$chunkdir" -type f -name 'chunk.*' -printf '%s\n' | awk '{s+=$1} END{print s+0}')"
  test "$planned" = "$got"
  tmp="$DEST/$target_name.rebuild"
  rm -f "$tmp"
  find "$chunkdir" -type f -name 'chunk.*' -print0 | sort -z | xargs -0 cat > "$tmp"
  test "$(stat -c %s "$tmp")" = "$remote_size"
  gzip -t "$tmp"
  if [ -n "$expected" ]; then
    actual="$(md5sum "$tmp" | awk '{print $1}')"
    test "$actual" = "$expected"
  fi

  bad="$DEST/$target_name.rejected"
  rm -f "$bad"
  [ -e "$target" ] && mv -f "$target" "$bad"
  mv -f "$tmp" "$target"
  test "$(stat -c %s "$target")" = "$remote_size"
  gzip -t "$target"
  if [ -n "$expected" ]; then
    actual="$(md5sum "$target" | awk '{print $1}')"
    test "$actual" = "$expected"
  fi
  rm -f "$bad"
  rm -rf "$chunkdir"
  echo "STAGE_VERIFIED=$target_name bytes=$remote_size"
}

if [ "$LIB" = GEX ]; then
  stage_one "${PREFIX}_S1_L001_R1_001.fastq.gz" "${PREFIX}_S1_L001_R1_001.fastq.gz"
  stage_one "${PREFIX}_S1_L001_R2_001.fastq.gz" "${PREFIX}_S1_L001_R2_001.fastq.gz"
else
  for L in 001 002 003 004; do
    for R in I1 R1 R2 R3; do
      name="${PREFIX}_S1_L${L}_${R}_001.fastq.gz"
      if [ "$SAMPLE" = P10MK2 ] && [ "$L" = 001 ] && [ "$R" = I1 ]; then
        stage_one '2-ATAC_S1_L001_I1_001.fastq_冲突文件_root_20260415215159.gz' "$name"
      else
        stage_one "$name" "$name"
      fi
    done
  done
fi
echo "FAST_STAGE_LIBRARY_PASS sample=$SAMPLE lib=$LIB"
