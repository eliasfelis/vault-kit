#!/usr/bin/env bash
# leak-audit.sh - publish gate: fail if any scanned file matches a forbidden pattern.
# Usage: leak-audit.sh --path P [--pattern-file F] [--extra-patterns X] [--exclude REGEX]
# exit 0 clean / 1 leak(s) found / 2 a named pattern file is missing.
# Scanner is perl (PCRE) so the existing .NET-style patterns (\b, \d, (?:...)) work unchanged.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
path=""
pattern_file="$script_dir/leak-patterns.txt"
extra_patterns=""
exclude='\.git/'

while [ $# -gt 0 ]; do
  case "$1" in
    --path)           path="$2"; shift 2 ;;
    --pattern-file)   pattern_file="$2"; shift 2 ;;
    --extra-patterns) extra_patterns="$2"; shift 2 ;;
    --exclude)        exclude="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

if [ -z "$path" ]; then echo "ERROR: --path is required" >&2; exit 64; fi
if [ ! -f "$pattern_file" ]; then echo "Pattern file not found: $pattern_file" >&2; exit 2; fi

combined="$(mktemp)"
filelist="$(mktemp)"
trap 'rm -f "$combined" "$filelist"' EXIT

# Load patterns (strip comment + blank lines). Fail-loud (exit 2) on a named-but-missing extra file.
grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$pattern_file" >> "$combined" || true
if [ -n "$extra_patterns" ]; then
  if [ ! -f "$extra_patterns" ]; then echo "ExtraPatterns file not found: $extra_patterns" >&2; exit 2; fi
  grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$extra_patterns" >> "$combined" || true
fi

if [ ! -s "$combined" ]; then echo "OK: no patterns loaded - nothing to check"; exit 0; fi

# Build file list: single file as-is, else enumerate by extension and apply --exclude.
if [ -f "$path" ]; then
  printf '%s\n' "$path" > "$filelist"
else
  find "$path" -type f \( \
      -name '*.md' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \
      -o -name '*.ps1' -o -name '*.txt' -o -name '*.js' -o -name '*.ts' -o -name '*.sh' \
    \) 2>/dev/null | grep -vE "$exclude" > "$filelist" || true
fi

# Scan with perl (PCRE).
perl -e '
  my ($pf, $lf) = @ARGV;
  open(my $ph, "<", $pf) or die "patterns: $!";
  my @pats = grep { length } map { my $x = $_; $x =~ s/\r?\n$//; $x } <$ph>;
  close($ph);
  open(my $lh, "<", $lf) or die "filelist: $!";
  my $hits = 0;
  while (my $file = <$lh>) {
    $file =~ s/\r?\n$//;
    next unless length $file;
    open(my $fh, "<", $file) or next;
    while (my $line = <$fh>) {
      for my $p (@pats) {
        if ($line =~ /$p/) {
          my $t = $line; $t =~ s/\r?\n$//;
          print "LEAK $file:$.: $t\n";
          $hits++;
          last;
        }
      }
    }
    close($fh);
  }
  close($lh);
  if ($hits > 0) { print "FAIL: $hits leak(s)\n"; exit 1; }
  print "OK: no leaks\n"; exit 0;
' "$combined" "$filelist"
