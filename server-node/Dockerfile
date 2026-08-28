FROM node:20-alpine

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json* ./
RUN npm ci --production --ignore-scripts 2>/dev/null || npm install --production

# Copy source code and entrypoint script
COPY src/ ./src/
COPY docker-entrypoint.sh ./docker-entrypoint.sh

# Ensure entrypoint is executable
RUN chmod +x ./docker-entrypoint.sh

# Container health probe
HEALTHCHECK --interval=15s --timeout=5s --retries=3 --start-period=10s \
  CMD wget -qO- http://localhost:3000/api/health || exit 1

EXPOSE 3000

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["node", "src/server.js"]
