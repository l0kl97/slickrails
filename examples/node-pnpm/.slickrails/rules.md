# Project review rules (.slickrails/rules.md)

Project-specific focus areas for reviews (locally via /code-review and
on PRs via claude-review.yml). Keep it short — only what goes beyond
the standard. Examples:

- No `node:` imports in client code (it runs in the browser!).
- All DB access goes through the repository layer, never directly in handlers.

Default rules (apply until deliberately removed here):

- Every external call (HTTP, DB, queue) has a timeout + error handling + logging.
- Don't introduce deprecated APIs; replace existing ones when touching them.
- New inputs (API, forms) are validated before being processed.

<!-- Add project-specific rules below: -->
