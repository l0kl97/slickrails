# Review learnings (.slickrails/review-learnings.md)

The team's accumulated review preferences. Every AI review (the PR
workflow, the local pre-push review, /code-review sessions) reads this
file and honors it — adaptive review without a SaaS in the loop.

Append a dated line whenever a review decision should stick, in either
direction:

- Waive: "don't flag X here, it's deliberate"
- Tighten: "always flag Y in this repo, even at low risk"

A waived finding type is never reported again; a tightened one always is.
Keep entries short and specific — this file is read verbatim by reviewers.

## Learnings

<!-- - 2026-08-24: console.log in scripts/ is fine — don't flag it. -->
<!-- - 2026-08-24: any new SQL string concatenation is a high-risk finding, no exceptions. -->
