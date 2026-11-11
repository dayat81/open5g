# Build on a host with egress, or point NODE_IMAGE and NPM_CONFIG_REGISTRY at a mirror.
# NEXT_PUBLIC_API_BASE is baked into the browser bundle. "/" sends /api to this
# container, and proxy.mjs forwards it using the runtime OPEN5G_API_INTERNAL_URL.
ARG NODE_IMAGE=node:22-bookworm-slim
FROM ${NODE_IMAGE} AS build

ARG NPM_CONFIG_REGISTRY=https://registry.npmjs.org
ARG NEXT_PUBLIC_API_BASE=/
ENV NEXT_PUBLIC_API_BASE=${NEXT_PUBLIC_API_BASE} \
    NPM_CONFIG_REGISTRY=${NPM_CONFIG_REGISTRY}

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

ARG NODE_IMAGE=node:22-bookworm-slim
FROM ${NODE_IMAGE}

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin nextjs

WORKDIR /app
COPY --from=build /app/public ./public
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY proxy.mjs ./

ENV NODE_ENV=production \
    WEB_PORT=3300 \
    PORT=3300 \
    OPEN5G_API_INTERNAL_URL=http://dashboard-api:8000 \
    NEXT_PUBLIC_API_BASE=/

USER nextjs

EXPOSE 3300

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "const p=process.env.WEB_PORT||process.env.PORT||'3300'; fetch('http://127.0.0.1:'+p+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "proxy.mjs"]
