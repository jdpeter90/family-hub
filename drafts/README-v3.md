# Family Hub v3.0 — Chores & Rewards (STAGING)

**Status: IN DEVELOPMENT — DO NOT MERGE OR DEPLOY.**

This branch builds on Family Hub v2.1 without rewriting its calendar, meals, groceries or legacy chores. No v3 SQL has been applied to the live Supabase project.

## Branch files

| File | Function |
| --- | --- |
| index.html | Existing v2.1 app, plus a parent-only navigation link |
| parent.html | Parent dashboard for chore/reward setup, reviews, and point adjustments |
| tablet.html | Children's shared tablet interface: choose profile, submit chores, request rewards |
| parent-staging.html / tablet-staging.html | Staging-only pages using the isolated Supabase staging project |
| v3-client.js | Browser client; separate parent/tablet session keys; publishable key plus RLS |
| drafts/v3-security-foundation.sql | APPLIED IN STAGING ONLY; not production |
| drafts/v3-rpc.sql | APPLIED IN STAGING ONLY; not production |
| drafts/v3-regression-tests.sql | VERIFIED rollback-only staging integration checks |

## Staging environment: created and tested

- Separate Supabase staging project: Family Hub v3 Staging (project reference `kytphqpfpchmmmbsmpcz`).
- Supabase quoted **$0/month** for this additional project before creation.
- Staging schema, security policies and v3 RPCs have been installed successfully.
- Both `drafts/v3-regression-tests.sql` and `drafts/v3-isolation-tests.sql` passed using synthetic authenticated principals, RLS, role switching and a final ROLLBACK.
- Checked: approval/deduction accounting, duplicate approvals, overdue once chores, needs-work resubmission, insufficient points, cross-family isolation, tablet forbidden writes/approvals.
- Staging has two named test child profiles, four sample assignments and two test rewards. Two confirmed staging Auth users are attached: one `admin` parent account and one restricted `tablet` account. Their real account IDs passed simulated authenticated-role SQL checks, including tablet denial and parent approval; a true browser sign-in still requires the user to enter their own test passwords.
- `parent-staging.html` and `tablet-staging.html` are wired to the **staging API and staging publishable key** with separate browser storage keys. They are on the feature branch only and not publicly hosted.
- GitHub Actions browser-client smoke tests passed on the feature branch, including staging page wiring.
- Remaining: use the downloadable GitHub Actions staging preview artifact to verify real password login, page rendering and complete parent/tablet handoff; then test on actual devices. No production deployment until approved.

## Security and business rules

- The two existing parent accounts are admins.
- The dedicated tablet login must be a new Supabase Auth user with a family_members role of tablet; it must NOT use a parent's credentials.
- A child profile selection is NOT authentication. Children sharing one device can select each other's profiles. Parent approval is the trust boundary.
- The tablet can only read v3 tables in its family, submit chores and request rewards; no direct modification of the ledger, reviews, catalogs or legacy family data.
- Points are awarded only on parent approval of submitted chores, and deducted only on parent approval of a reward request.
- Parent adjustments require admin authorization and cannot take the balance below zero.
- Chore repeats: daily (up to 5 occurrences/day), weekly (one chosen weekday), once (due date or overdue). All dates use America/Chicago.
- Reward requests take a snapshot of cost/title; at most one identical pending request per child and reward.
- Legacy v2.1 shared data becomes admin-only. This is compatible with the current two-admin setup, but would change permissions for future nonadmin household members.

## Deployment gates — DO NOT SKIP

1. Back up the live database and dashboard JSON; verify both parents have admin membership.
2. Obtain explicit consent before creating a paid Supabase development branch or other billable staging project.
3. Apply BOTH files to an isolated staging database in this order:
   - drafts/v3-security-foundation.sql
   - drafts/v3-rpc.sql
4. Run drafts/v3-regression-tests.sql on STAGING ONLY. It temporarily changes a membership and creates fixture data, then rolls back.
5. Review Supabase advisors; verify that tablet accounts cannot see/edit old events, meals, groceries or legacy chores while parents can still use all v2.1 features.
6. Test daily repeats, weekly day handling, once/overdue chores, submissions and resubmissions, duplicate approval prevention, reward cost/negative balance, concurrent redemptions, session expiry, and mobile/tablet UX.
7. After tests pass, create the dedicated tablet Auth account using the supported Auth admin workflow and assign its role. NEVER put any password, secret key, or service-role key in GitHub or in browser code.
8. Obtain the user's approval before applying migrations to production or merging the GitHub feature branch into main.
9. Test both parent phones and the Fire tablet, with post-launch error monitoring.

## Caveats

- Current v3 code is NOT functioning in production, because the v3 RPCs and RLS are not deployed.
- SQL integration tests in isolated staging passed, but browser sign-ins through Supabase Auth and real device tests are still pending.
- Legacy chores are not automatically migrated. The new v3 assignments live separately, preserving v2.1 behavior during development.
- Backend authorization matters; disabled buttons and a child-selection UI are never security controls.
