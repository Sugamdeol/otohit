# otohit

Deploy the official [OtoHits](https://www.otohits.net) traffic-exchange client as a **Render Web Service**.

The upstream `otohits/app` image is a background client and does not listen on an HTTP port. Render Web Services require a process that binds to `$PORT`, including on the free plan. This repository adds a tiny, public status endpoint while preserving the upstream client as the main process:

- `GET /` or `GET /healthz` returns a non-sensitive JSON status response.
- The OtoHits client still receives your `APPLICATION_KEY` normally.
- No account data or application key is exposed by the endpoint.

## Deploy on Render's free tier

1. Push this repository to GitHub.
2. In Render, select **New → Blueprint**, then choose this repository.
3. At the `APPLICATION_KEY` prompt, enter the application key from your [OtoHits Application page](https://www.otohits.net/account/app).
4. Apply the blueprint. Render builds `Dockerfile`, starts a **Web Service**, and checks `GET /healthz`.

The key is declared with `sync: false`, so Render stores it as a secret instead of committing it to the repository.

## Verify the deployment

Once the service is live, open its Render URL:

```text
https://your-service.onrender.com/healthz
```

Expected response:

```json
{"status":"ok","service":"otohits-client"}
```

## Important free-tier limitation

Free web services can spin down after inactivity and take time to wake on the next request. That means this client is **not suitable for uninterrupted 24/7 traffic exchange on a free instance**. Use a paid always-on instance if continuous operation is required. Do not rely on automated keep-alive requests to work around hosting limits.

## Local Docker run

```bash
docker build -t otohit-web .
docker run --rm -p 10000:10000 \
  -e PORT=10000 \
  -e APPLICATION_KEY="your-application-key" \
  otohit-web
```

Then visit `http://localhost:10000/healthz`.

## Files

- `render.yaml` — Render Blueprint configured as a free Web Service.
- `Dockerfile` — wraps the official `otohits/app` image.
- `healthcheck.go` — minimal port/health endpoint.
- `docker-entrypoint.sh` — starts the listener, then launches the OtoHits client.

## Troubleshooting

Every startup step is logged with a `[docker-entrypoint-web]` prefix — check
**Logs** in the Render dashboard first.

- **`Application exited early` right after `Deploying...`** — the previous
  version of this repository replaced the upstream image's `ENTRYPOINT`, and
  because `otohits/app:latest` is normally started with no container command
  (`docker run -e APPLICATION_KEY=... otohits/app:latest`), nothing was left
  to execute and the container exited immediately. The current entrypoint
  locates the client binary inside the image when no command is inherited.
- **Warning that `APPLICATION_KEY` is not set** — add it under your service's
  **Environment** tab in Render (get it from your
  [OtoHits Application page](https://www.otohits.net/account/app)) and
  redeploy. The client exits immediately without it.
- **"could not find the OtoHits client binary"** — the upstream image layout
  changed. Run
  `docker image inspect otohits/app:latest --format '{{json .Config}}'` to see
  the image's original `Entrypoint`/`Cmd`, then set that command (without the
  entrypoint parts) as the service's **Docker Command** override in Render, or
  update the candidate list in `docker-entrypoint.sh`.
