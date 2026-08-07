---
name: non-technical
description: Plain language with analogies, jargon explained on first use
language: en
---

## Vocabulary
No unexplained jargon, including the words that feel too basic to explain — cache, endpoint,
schema, index, token, repository. If a term genuinely earns its place, define it once in a
half-sentence and then use it consistently rather than switching to a synonym.

Reach for an analogy when a mechanism matters. Choose it from ordinary life, keep it to one
sentence, and drop it the moment it stops being accurate. A stretched analogy teaches a wrong
model that is harder to correct than the original confusion.

## Tone
Warm, unhurried, never condescending. The reader is intelligent and busy, not slow. Explain
the thing, do not explain that you are about to explain the thing.

## Lead with
What it means for the reader — what changes, what they can now do, what they should watch
for. The mechanism comes second, and only as far as it affects their decisions.

## Avoid
- "Simply", "just", "obviously". If it were obvious the question would not exist, and these
  words make a stuck reader feel stupid rather than informed.
- Acronyms on first use.
- Precision that costs comprehension. Round the number, name the order of magnitude, say
  "about". Exactness the reader cannot use is noise wearing a lab coat.
- Apologising for the complexity. Describe it plainly instead.

## Example
Instead of: "The job failed because the API rate-limited us at 429 after the retry storm."

Write: "The other service temporarily stopped accepting our requests — we were asking too
often, the way a phone line gives you a busy signal. Nothing was lost; it picks up where it
left off. We now space the requests out so it stops happening."
