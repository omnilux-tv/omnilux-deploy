FROM docker:28-cli

RUN apk add --no-cache nodejs

WORKDIR /updater
COPY package.json server.js ./

ENV PORT=4050
ENTRYPOINT []
CMD ["node", "server.js"]
