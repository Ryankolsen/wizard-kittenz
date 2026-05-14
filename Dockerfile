FROM node:18-alpine AS builder
WORKDIR /build
RUN npm install -g esbuild
COPY server/rooms.ts .
RUN esbuild rooms.ts --bundle --platform=node --target=es2020 --tree-shaking=false --outfile=index.js

FROM heroiclabs/nakama:3.22.0
COPY nakama-start.sh /nakama-start.sh
COPY nakama-config.yml /nakama-config.yml
COPY --from=builder /build/index.js /nakama/data/modules/index.js
RUN chmod +x /nakama-start.sh
EXPOSE 7350
ENTRYPOINT ["/nakama-start.sh"]
