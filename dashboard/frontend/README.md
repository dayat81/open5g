# Frontend

Next.js scaffold for the Overview and the own-IMSI profile editor. It maps classes from `docs/ux/hifi/` (`tokens.css`, `components.css`). That hi-fi pack is the component reference. This app is not a visual sign-off, and it is not `docs/ux/prototype/`.

Empty `NEXT_PUBLIC_API_BASE` selects isolated demo mode. Demo responses are labeled `data_origin: "demo"`. They are not a session and not lab evidence. A non-empty value, including `/` behind `proxy.mjs`, uses the same-origin API. `/login` posts `{email, password}` to `/api/auth/login` and stores `csrf_token` for later writes. `/profil` lists the caller’s assignments and saves, validates, provisions, and rolls back a profile with `If-Match` and `x-csrf-token`. Immediate Gx apply stays disabled.

Immediate apply is rendered as `rejected`. The result region does not use `badge lifecycle-active`. `badge applied` is reserved for a pushed/installed label. The sample applied version stays on `state-card applied`.

```bash
npm ci
npm test
npm run lint
npm run typecheck
npm run build
```
