# ---------- Stage 1: Build Aurelia (Go + TS bridge) ----------
FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git ca-certificates nodejs npm

WORKDIR /build

# Clone Aurelia source
RUN git clone --depth 1 https://github.com/Lordymine/aurelia.git .

# Build TS bridge (embedded into Go binary via go:embed)
RUN if [ -d bridge ] && [ -f bridge/package.json ]; then \
      cd bridge && npm install && (npm run build || true); \
    fi

# Build Aurelia binary
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /out/aurelia ./cmd/aurelia

# ---------- Stage 2: Runtime ----------
FROM node:22-alpine

RUN apk add --no-cache ca-certificates tini bash curl git

# Claude Code CLI (the brain)
RUN npm install -g @anthropic-ai/claude-code

# Aurelia binary
COPY --from=builder /out/aurelia /usr/local/bin/aurelia
RUN chmod +x /usr/local/bin/aurelia

# Non-root user
RUN adduser -D -u 1000 -h /home/aurelia aurelia
USER aurelia
WORKDIR /home/aurelia

VOLUME ["/home/aurelia/.aurelia"]

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["aurelia"]
