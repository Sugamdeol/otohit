# otohit

Run the [OtoHits](https://www.otohits.net) traffic-exchange client on [Render](https://render.com) as a container.

## What it does

The [`otohits/app`](https://hub.docker.com/r/otohits/app) Docker image is the official OtoHits client. It runs in the background and exchanges traffic for your account using an application key. Its only required setting is:

| Variable        | Description                                                            |
| --------------- | ---------------------------------------------------------------------- |
| `APPLICATION_KEY` | Your application key from https://www.otohits.net/account/app |

## Deploy to Render (Blueprint)

1. Push this repository to GitHub.
2. In Render, click **New → Blueprint** and select the repo.
3. When prompted for `APPLICATION_KEY`, paste your key
   (`a6c4c312-c270-42c8-8ae5-31759f337ecc`).
4. Click **Apply**. Render pulls `otohits/app:latest` from Docker Hub and
   starts the service.

The `render.yaml` blueprint deploys the image as a **Background Worker**
because the OtoHits client does not serve HTTP. Render reserves "Web Service"
for processes that must bind the `$PORT` environment variable.

## Run locally with Docker

```bash
docker run -e APPLICATION_KEY=a6c4c312-c270-42c8-8ae5-31759f337ecc otohits/app:latest
```

## Notes

- Render's free tier may suspend instances; use a paid instance type if you
  need the client running 24/7 without interruption.
- Keep your application key private. The blueprint uses `sync: false` so the
  key is stored as a Render secret rather than committed to Git.
