# Frontend

Next.js scaffold for the Overview and the own-IMSI profile editor. It maps classes from `docs/ux/hifi/` (`tokens.css`, `components.css`). That hi-fi pack is the component reference. This app is not a visual sign-off, and it is not `docs/ux/prototype/`.

Empty `NEXT_PUBLIC_API_BASE` selects isolated demo mode. Demo responses are labeled `data_origin: "demo"`. They are not a session and not lab evidence. Setting the variable selects the FastAPI client, which calls `/api/profiles/{id}/validate` and `/api/profiles/{id}/apply` only when a profile id, `If-Match`, and CSRF token already exist. This UI does not invent a login.

Immediate apply is rendered as `rejected`. The result region does not use `badge lifecycle-active`. `badge applied` is reserved for a pushed/installed label. The sample applied version stays on `state-card applied`.

```bash
npm ci
npm test
npm run lint
npm run typecheck
npm run build
```
