FROM node:18-alpine AS builder
WORKDIR /build
COPY server/rooms.ts .
RUN npm init -y && npm install @heroiclabs/nakama-runtime
RUN npx esbuild rooms.ts --bundle --platform=node --target=es2020 --outfile=rooms.js

FROM heroiclabs/nakama:3.22.0
COPY nakama-start.sh /nakama-start.sh
COPY nakama-config.yml /nakama-config.yml
COPY --from=builder /build/rooms.js /nakama/data/modules/rooms.js
RUN chmod +x /nakama-start.sh
EXPOSE 7350
ENTRYPOINT ["/nakama-start.sh"]
