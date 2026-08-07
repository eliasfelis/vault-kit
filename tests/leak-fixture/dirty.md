# Dirty fixture (FAKE secrets, for the leak-audit self-test)

One sample per SHIPPED pattern in `leak-patterns.txt`, in the same order, each on its own line
and matching exactly ONE pattern. The self-test asserts findings == pattern count, so deleting a
shipped pattern drops a finding and fails the build instead of leaving the positive control green
on the remaining ones. Every value below is fake and belongs to nobody.

Two shapes are deliberately NOT stored here — a Slack bot token and a Stripe live key. A host's
own push protection refuses a commit carrying either, even as test data, and a fixture that
cannot be pushed (or forked by anyone who clones this) is worse than one the test assembles: the
self-test appends both to a temporary copy before it checks coverage. So scanning this file on
its own reports fewer findings than there are patterns — expected. It must still FAIL the gate,
which is the positive control you can run by hand:

    bash plugins/vault-audit/scripts/leak-audit.sh --path tests/leak-fixture/dirty.md   # exits 1

Win path: C:\Users\example\secrets.txt
Win fwd: C:/Users/example/secrets.txt
Git-Bash: /c/Users/example/secrets.txt
macOS home: /Users/example/secrets.txt
Linux home: /home/example/secrets.txt
GitHub PAT: ghp_abcdefghijklmnopqrstuvwxyz0123456789
GitHub OAuth: gho_abcdefghijklmnopqrstuvwxyz0123456789
GitHub server: ghs_abcdefghijklmnopqrstuvwxyz0123456789
GitHub fine-grained: github_pat_abcdefghijklmnopqrstuvwxyz0123456789
AWS key id: AKIAIOSFODNN7EXAMPLE
GitLab PAT: glpat-abcdefghijklmnopqrst
Google API: AIzaSyFAKE01234567890123456789012345678
npm token: npm_abcdefghijklmnopqrstuvwxyz0123456789
OpenAI: sk-proj-abcdefghij0123456789ABCDEFGH
-----BEGIN RSA PRIVATE KEY-----
