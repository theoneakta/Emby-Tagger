FROM node:22-alpine

# Run as non-root for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Install dependencies first (better layer caching)
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

# Copy app source
COPY server.mjs .
COPY index.html .

# Create /data directory and give appuser ownership before switching user
# This is where the CSV cache and cron status live (mount a volume here)
RUN mkdir -p /data && chown appuser:appgroup /data

# Switch to non-root user
USER appuser

EXPOSE 3000

CMD ["node", "server.mjs"]