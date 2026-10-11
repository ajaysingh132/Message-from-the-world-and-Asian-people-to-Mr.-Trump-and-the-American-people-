# GBSBFORYOU Social — implementation plan

## Goal
Combine the public conversation feed with the Instagram Academy creator-learning workflow while preserving the original “Asia’s Voice to America — 9 April 2026” letter in `index.html`.

## Current repository state
- `index.html`: original public letter; do not replace.
- `social.html`: mobile-first static UI prototype.
- Academy source of truth remains `ajaysingh132/Gbsbforyou-Instagram-Academy`; its concepts and curriculum are to be integrated, not deleted or blindly copied.
- Development branch: `feature/gbsbforyou-social-platform`.

## Architecture (incremental and provider-aware)
1. **Frontend:** mobile-first web UI/PWA; public visitors can read approved posts and approved comments.
2. **Identity:** Supabase Auth (email/password or email OTP, after project setup). Only authenticated users may submit posts/comments.
3. **Data:** PostgreSQL with row-level security (RLS). See `supabase/migrations/001_social_core.sql`.
4. **Editorial queue:** submissions begin as `pending_review`; AI checks can provide a recommendation, but cannot publish by themselves. Editors make the final decision.
5. **Creator Academy:** modules, learning progress, assignments and creator portfolio will be linked to the same user identity in a later migration.
6. **AI services:** provider-agnostic adapter; begin with a free-tier provider only after its terms, quotas and API access are verified. Never put API keys in frontend code or Git.
7. **External sharing:** initially generate share links. Automated publishing to X, Instagram and Facebook is a later phase requiring eligible APIs, account authorization and server-side token storage.

## Content states
`draft → pending_review → approved → published`
Editors may move content to `rejected` with a reason. A published item can be archived. AI review is advisory and is logged separately from the editor's decision.

## Release stages
- **Stage 1 (current):** static UI prototype and database schema.
- **Stage 2:** configure Supabase project, apply migration, configure Auth and test RLS.
- **Stage 3:** connect frontend to approved-feed and submission APIs; implement editor queue.
- **Stage 4:** add Academy lessons/progress and AI-assisted review.
- **Stage 5:** external platform integrations after permissions and policy review.

## Safety and acceptance criteria
- Anonymous visitors can read only approved/published content.
- Authenticated users can submit new content for review but cannot approve their own submissions or alter moderation status.
- Editorial decisions are attributable and auditable.
- No service-role keys or social access tokens are exposed in browser JavaScript or committed to Git.
- Demo labels must remain explicit until the corresponding backend behavior is live.
