FROM node:22-alpine

# Run as non-root for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Install dependencies first (better layer caching)
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

# Copy app source
COPY server.mjs .
COPY public/ public/

# Switch to non-root user
USER appuser

EXPOSE 3000

CMD ["node", "server.mjs"]
