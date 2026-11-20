FAMILY HUB V3.0 — STAGING TEST PACKAGE
======================================

This package connects ONLY to the separate Family Hub v3 Staging Supabase project.
It DOES NOT connect to your family's production database.

FILES:
- parent-staging.html    Parent dashboard, using the STAGING parent test account.
- tablet-staging.html    Children's chore and reward screen, using the STAGING tablet test account.
- v3-client.js          Browser client; both pages need this file beside them.

HOW TO TEST:
1. Download this archive from your own GitHub repository's Actions workflow.
2. Unzip it. Keep all three files together in one folder.
3. Double-click parent-staging.html. Sign in with your STAGING parent test email/password.
4. Confirm you see the two test children, four sample chores, and two rewards.
5. Add a low-value test chore and return to the list to see it.
6. Open tablet-staging.html (in a different tab), sign in with the STAGING tablet
   account, choose a test child, and tap "I did it!".
7. Return to the parent page, refresh, and approve the submitted chore.
8. Return to the tablet, refresh, and verify the point balance increased.
9. The least expensive example reward costs 15 points. If your child has only
   10 points after the first chore, use the parent dashboard's Manual point
   adjustment to add a 20-point TEST bonus (reason: "Staging test bonus").
10. On the tablet, tap "Request reward". Back on the parent page, refresh,
    approve the reward, and confirm the child's point balance decreases.

SECURITY:
- NEVER sign in to these testing pages with your real production parent account.
- No secret keys are included. Only a public Supabase publishable key is present.
- Do not email or share these test HTML files with other people.
- If your browser refuses to open local HTML files or blocks fetch/session storage,
  tell ChatGPT what the error says. We can switch to an HTTP-hosted preview.

ADVANCED FALLBACK ON MAC (only if opening local files directly fails):
Open Terminal and enter: cd [drag the extracted folder from Finder here]
Then run: python3 -m http.server 8765
Open: http://localhost:8765/parent-staging.html
This runs locally on YOUR computer; don't expose it to the internet.

These screens are a development preview, not a production release.
