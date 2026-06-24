#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; dir="${2:-}"
state="$dir/state.json"
case "$cmd" in
  read)
    slug="$3"
    [ -f "$state" ] || { echo 0; exit 0; }
    perl -0777 -ne 'BEGIN{$slug=shift @ARGV} my %h; while(/"([^"]+)"\s*:\s*\{[^}]*?"last_seen"\s*:\s*(\d+)/g){$h{$1}=$2} print(($h{$slug}//0),"\n")' "$slug" "$state"
    ;;
  write)
    slug="$3"; epoch="$4"; outcome="$5"
    mkdir -p "$dir"; [ -f "$state" ] || echo '{}' > "$state"
    perl -0777 -i -ne '
      BEGIN{($s,$e,$o)=splice(@ARGV,0,3)}
      my %h;
      while(/"([^"]+)"\s*:\s*\{\s*"last_seen"\s*:\s*(\d+)\s*,\s*"outcome"\s*:\s*"(\w+)"\s*\}/g){ $h{$1}=[$2,$3] }
      $h{$s}=[$e,$o];
      my @p = map { "\"$_\":{\"last_seen\":$h{$_}[0],\"outcome\":\"$h{$_}[1]\"}" } sort keys %h;
      print "{".join(",",@p)."}\n";
    ' "$slug" "$epoch" "$outcome" "$state"
    ;;
  summary)
    [ -f "$state" ] || { echo "ok=0 failed=0 failed_slugs="; exit 0; }
    perl -0777 -ne 'my($ok,$f,@fs)=(0,0); while(/"([^"]+)"\s*:\s*\{[^}]*?"outcome"\s*:\s*"(\w+)"/g){ if($2 eq "ok"){$ok++}else{$f++;push @fs,$1} } print "ok=$ok failed=$f failed_slugs=".join(",",@fs)."\n"' "$state"
    ;;
  *) echo "usage: feed-state.sh {read|write|summary} <state_dir> [args]" >&2; exit 2;;
esac
