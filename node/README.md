# rubycrawl Node Service

Local Playwright-backed HTTP service used by the Ruby gem.

## Run

```
npm install
npm start
```

## Environment

Create a `.env` file (or copy from `.env.example`) if you need custom settings.

## Endpoints

- `POST /crawl` JSON body: `{ "url": "https://example.com" }`
- `GET /health`
