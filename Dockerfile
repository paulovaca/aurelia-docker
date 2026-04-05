# ---------- Stage 1: Build Aurelia (Go + TS bridge) ----------
FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git ca-certificates nodejs npm python3 patch

WORKDIR /build

# Clone Aurelia source (upstream main has 2 compile errors we patch below)
RUN git clone --depth 1 https://github.com/Lordymine/aurelia.git .

# Create the no-op MemoryStore used by patch 2
RUN cat > internal/cron/memory_noop.go <<'EOF'
package cron

import "context"

// NoopMemoryStore is a MemoryStore that does nothing.
// Used when the memory system is disabled.
type NoopMemoryStore struct{}

func (NoopMemoryStore) Inject(ctx context.Context, query string, limit int) (string, error) {
	return "", nil
}

func (NoopMemoryStore) Save(ctx context.Context, content, category, agent string) error {
	return nil
}
EOF

# PATCH 1: input_pipeline.go references removed bootstrapStepAssistant symbols.
# The "remove dead code stubs" refactor (0693ebf) deleted bootstrapStepAssistant
# and completeBootstrapAssistant but left input_pipeline.go still calling them.
# Collapse the switch — correct path is always completeBootstrapProfile.
#
# PATCH 2: cmd/aurelia/app.go:193 calls cron.NewBridgeCronRuntime with 3 args,
# but it now requires 4 (MemoryStore). Pass our NoopMemoryStore.
RUN python3 <<'PYEOF'
import pathlib

# --- Patch 1: removed bootstrapStepAssistant symbols ---
p = pathlib.Path('internal/telegram/input_pipeline.go')
s = p.read_text()
old1 = ("\tif state, ok := bc.popPendingBootstrap(c.Sender().ID); ok {\n"
        "\t\tswitch state.Step {\n"
        "\t\tcase bootstrapStepAssistant:\n"
        "\t\t\treturn bc.completeBootstrapAssistant(c, state, text)\n"
        "\t\tdefault:\n"
        "\t\t\treturn bc.completeBootstrapProfile(c, state, text)\n"
        "\t\t}\n"
        "\t}")
new1 = ("\tif state, ok := bc.popPendingBootstrap(c.Sender().ID); ok {\n"
        "\t\treturn bc.completeBootstrapProfile(c, state, text)\n"
        "\t}")
assert old1 in s, 'PATCH 1 anchor not found'
p.write_text(s.replace(old1, new1))
print('PATCH 1 applied')

# --- Patch 2: NewBridgeCronRuntime missing MemoryStore arg ---
p = pathlib.Path('cmd/aurelia/app.go')
s = p.read_text()
old2 = ("\tcronRuntime := cron.NewBridgeCronRuntime(\n"
        "\t\t&cron.BridgeAdapter{B: br},\n"
        "\t\tagentReg,\n"
        "\t\tpersonaSvc,\n"
        "\t)")
new2 = ("\tcronRuntime := cron.NewBridgeCronRuntime(\n"
        "\t\t&cron.BridgeAdapter{B: br},\n"
        "\t\tagentReg,\n"
        "\t\tpersonaSvc,\n"
        "\t\tcron.NoopMemoryStore{},\n"
        "\t)")
assert old2 in s, 'PATCH 2 anchor not found'
p.write_text(s.replace(old2, new2))
print('PATCH 2 applied')

# --- Patch 3: setup.go writes bundle.ts but app.go looks for bundle.js ---
# The bridge auto-setup writes the embedded TS source as bundle.ts, but
# setupBridge then checks for bundle.js — never finds it — and falls back
# to `npx tsx index.ts` which doesn't exist in the bridge dir.
# Fix: make app.go look for bundle.ts (matching what setup.go actually writes).
p = pathlib.Path('cmd/aurelia/app.go')
s = p.read_text()
old3 = 'bundlePath := filepath.Join(bridgeDir, "bundle.js")'
new3 = 'bundlePath := filepath.Join(bridgeDir, "bundle.ts")'
assert old3 in s, 'PATCH 3 anchor not found'
p.write_text(s.replace(old3, new3))
print('PATCH 3 applied')
PYEOF

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

# Use the pre-existing `node` user (UID 1000) from node:22-alpine
USER node
WORKDIR /home/node

VOLUME ["/home/node/.aurelia"]

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["aurelia"]
