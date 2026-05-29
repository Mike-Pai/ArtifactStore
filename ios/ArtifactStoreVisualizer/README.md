# ArtifactStore Visualizer

SwiftUI presentation app for the ArtifactStore demo flow. The app connects to
the Mac-side FastAPI backend, starts or replays demo runs, and visualizes the
supervisor/subagent/tool-use flow for an iPad or iPhone audience.

The app is intentionally display-only:

- It does not run LLM calls.
- It does not read SQLite directly.
- It does not store provider API keys.
- It only displays sanitized JSON events emitted by the backend.

## Screens

- **Architecture Board** shows the three main actors: User, Supervisor Agent,
  and Subagent. Supervisor/Subagent cards distinguish LLM decisions from
  harness execution and show the tool calls chosen by each LLM.
- **Flow Conversation** converts backend events into a paced, high-level
  workflow. This is the main presentation surface.
- **Raw Events** keeps the full backend event telemetry available for technical
  inspection without dominating the demo.
- **Sidebar** shows backend connection, selected scenario/model, run summary,
  token counts, and final diagnosis.

## Running

1. Start the backend on the Mac:

   ```bash
   uv run python -m uvicorn demo.visual_server:app --host 0.0.0.0 --port 8765
   ```

2. Put the iPad/iPhone and Mac on the same LAN or Tailscale network.

3. Open the project in Xcode:

   ```text
   ios/ArtifactStoreVisualizer/ArtifactStoreVisualizer.xcodeproj
   ```

4. Confirm the backend URL in the app. The default is:

   ```text
   http://100.110.13.83:8765
   ```

5. Use the app flow:

   ```text
   Connect -> Configure -> Start Demo
   ```

   `Replay Latest` reloads the latest saved JSON trace from the backend.

## Current Limits

- v1 uses HTTP polling, not WebSocket or SSE.
- v1 visualizes demo flow only; it does not browse the ArtifactStore SQLite DB.
- Raw model text is not shown in the visualizer. The backend emits only safe
  summaries such as text length, tool name, artifact id, grant id, citation
  status, and token counts.
- `Replay Latest` depends on `visual_traces/*.json`. The companion
  `visual_traces/*.sqlite` files are reserved for future DB viewer work.
