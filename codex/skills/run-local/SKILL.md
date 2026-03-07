---
name: run-local
description: Start the project's dev server locally. Auto-detects project type (Node, Python, Rust, Go, etc.), installs deps if needed, starts the server, and reports the URL.
---

**Created:** 2026-03-07-00-00
**Last Updated:** 2026-03-07-00-00

# Run Local

Start the project's development server so the user can test locally.

## Step 1: Detect Project Type and Dev Command

Check for project indicators in order of specificity:

```bash
# Check for explicit dev/start scripts first
if [ -f "package.json" ]; then
    # Node/Bun project — check scripts
    DEV_CMD=$(node -e "
        const pkg = require('./package.json');
        const s = pkg.scripts || {};
        console.log(s.dev || s.start || s.serve || '');
    " 2>/dev/null)

    if command -v bun &>/dev/null && [ -f "bun.lock" ]; then
        RUNNER="bun"
    else
        RUNNER="npm run"
    fi

    if [ -n "$DEV_CMD" ]; then
        # Use the first available script name
        for script in dev start serve; do
            if node -e "process.exit(require('./package.json').scripts?.['$script'] ? 0 : 1)" 2>/dev/null; then
                RUN="$RUNNER $script"
                break
            fi
        done
    fi

    # Fallback: if no standard script found, list available scripts and ask
    if [ -z "$RUN" ] && [ -f "package.json" ]; then
        SCRIPTS=$(node -e "const s=require('./package.json').scripts||{}; console.log(Object.keys(s).join(', '))" 2>/dev/null)
        if [ -n "$SCRIPTS" ]; then
            echo "No dev/start/serve script found. Available scripts: $SCRIPTS"
            echo "Ask user which script to run."
            exit 1
        fi
    fi

elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "Pipfile" ]; then
    # Python project
    if [ -f "manage.py" ]; then
        RUN="python manage.py runserver"
    elif [ -f "app.py" ] || [ -f "main.py" ]; then
        ENTRY=$([ -f "app.py" ] && echo "app.py" || echo "main.py")
        RUN="python $ENTRY"
    elif [ -f "pyproject.toml" ] && grep -q "uvicorn\|fastapi" pyproject.toml 2>/dev/null; then
        RUN="uvicorn app:app --reload"
    else
        RUN="python main.py"
    fi

elif [ -f "Cargo.toml" ]; then
    RUN="cargo run"

elif [ -f "go.mod" ]; then
    RUN="go run ."

elif [ -f "Makefile" ] && grep -q "^run:" Makefile; then
    RUN="make run"
fi

if [ -z "$RUN" ]; then
    echo "Could not detect dev command. Ask user for the start command."
    exit 1
fi

echo "Detected: $RUN"
```

## Step 2: Install Dependencies (if needed)

```bash
# Node
if [ -f "package.json" ] && [ ! -d "node_modules" ]; then
    if [ "$RUNNER" = "bun" ]; then
        bun install
    else
        npm install
    fi
fi

# Python — install if requirements.txt exists and no venv/installed marker
if [ -f "requirements.txt" ]; then
    if [ ! -d "venv" ] && [ ! -d ".venv" ] && [ -z "$VIRTUAL_ENV" ]; then
        pip install -r requirements.txt
    fi
fi
```

Only install if deps appear missing. Don't reinstall every time.

## Step 3: Start the Server

Run the detected command in the background:

```bash
# Start in background, capture output
$RUN &
SERVER_PID=$!

# Wait a moment for startup
sleep 3

# Check if still running
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "Server started (PID: $SERVER_PID)"
else
    echo "Server failed to start. Check output above."
fi
```

## Step 4: Report to User

Tell the user:
```
Dev server running.
Command: {command}
URL: http://localhost:{port}
PID: {pid}

To stop: kill {pid}
```

Detect the port from:
1. Command output (e.g., "listening on port 3000")
2. Common defaults: Next.js/Vite → 3000, Flask → 5000, Django → 8000, FastAPI → 8000, Go → 8080

## Step 5: Optional — Visual Check

If the user wants to verify, offer to run `/webapp-test` against the local URL for a screenshot.

## Notes

- If the port is already in use, detect this from the error output and suggest killing the existing process or using a different port
- If the server crashes on startup, read the error output and try to fix the issue before reporting to the user
- Do NOT open a browser for the user — just report the URL
