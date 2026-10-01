---
layout: docs
title: Connect an Agent
description: Copy-paste MCP client configurations for the Portfolixir companion, over stdio and over HTTP.
lang: en
lang_en: /integration/connect-an-agent.html
lang_de: /de/integration/connect-an-agent.html
---

# Connect an Agent

The MCP companion in `mcp-server/` gives an agent Portfolixir's tools and two
prompts. It calls the instance's JSON API with `PORTFOLIXIR_API_TOKEN` and
nothing else. Connect it one of two ways: the agent's client starts it as a
local process (stdio), or the client reaches the companion the Compose stack
already runs (HTTP).

The configurations below use the `mcpServers` shape most MCP clients read. The
key names differ a little between clients (the transport key of an HTTP
server, for one), so check your client's documentation for its spelling.

## Pick a profile first

`PORTFOLIXIR_MCP_PROFILE` decides which tools the agent sees and may call:

| Profile | The agent can |
|---|---|
| `read` | read everything and change nothing |
| `book` | read, create, and make the replace-shaped writes (update, upsert, set), which the same write sent the former value undoes; no removal, merge, ISIN change, rule retirement or quote release |
| `full` (the default) | call every tool |

Two of the writes `book` keeps leave a residue their inverse does not clear: a
rename back restores an account's name but keeps the in-between name as a
former name, and an upsert over a date that held provider data leaves a manual
quote there; only the admin tools `remove_former_name` and
`portfolixir.quotes.release` clear them.

`book` suits an agent that sets up an instance and books into it, `read` one
that only reports. A profile narrows the companion, not the API token: an agent
with a shell and the token can still call every route of the API. The admin
set `book` leaves out, and why, is in [API and MCP](api-and-mcp.html#mcp-tools).

## Over stdio: the client starts the companion

Build the companion once, with Node 24:

```bash
npm ci --ignore-scripts --prefix mcp-server
npm run build --prefix mcp-server
```

Then add it to the client's configuration, with the absolute path of your
checkout and the `PORTFOLIXIR_API_TOKEN` from the instance's `.env`:

```json
{
  "mcpServers": {
    "portfolixir": {
      "command": "node",
      "args": ["/absolute/path/to/portfolixir/mcp-server/dist/index.js"],
      "env": {
        "PORTFOLIXIR_API_BASE_URL": "http://127.0.0.1:4000",
        "PORTFOLIXIR_API_TOKEN": "<PORTFOLIXIR_API_TOKEN from .env>",
        "PORTFOLIXIR_MCP_PROFILE": "book"
      }
    }
  }
}
```

stdio is the companion's default transport, so `PORTFOLIXIR_MCP_TRANSPORT`
needs no value. The token now sits in the client's configuration file as well:
keep that file readable by you only.

## Over HTTP: the companion the Compose stack runs

`docker compose up --build` starts the companion with the application, on the
host's loopback interface. Set the profile in `.env`
(`PORTFOLIXIR_MCP_PROFILE=book`), recreate the service with
`docker compose up -d mcp`, and point the client at it:

```json
{
  "mcpServers": {
    "portfolixir": {
      "type": "http",
      "url": "http://127.0.0.1:4001/mcp",
      "headers": {
        "Authorization": "Bearer <PORTFOLIXIR_MCP_TOKEN from .env>"
      }
    }
  }
}
```

The transport is MCP Streamable HTTP: each JSON-RPC message is a `POST` to
`/mcp`, its `Accept` header must list both `application/json` and
`text/event-stream` (a request that lists only one is answered `406`), and the
answer comes back as an event stream. The companion runs it stateless: it
issues no `Mcp-Session-Id`, builds a fresh server for every request, and sends
no notification between requests. An MCP client handles all of this once the
URL and the header are set.

Every request carries the header `Authorization: Bearer
<PORTFOLIXIR_MCP_TOKEN>`. A wrong token answers `401`, and repeated wrong
tokens from one address lock that address out for a growing time; behind the
published port every client on the host is that one address, so
`docker compose restart mcp` clears the count. The companion answers only
under the loopback names with its port (`127.0.0.1:4001`, `localhost:4001`);
behind a reverse proxy, add the proxy's name to
`PORTFOLIXIR_MCP_ALLOWED_HOSTS`.

## The companion's variables

| Variable | Default | What it does |
|---|---|---|
| `PORTFOLIXIR_API_TOKEN` | none, required | The API token the companion calls the instance with. |
| `PORTFOLIXIR_API_BASE_URL` | `http://127.0.0.1:4000` | Where the instance's API answers, without a redirect. |
| `PORTFOLIXIR_MCP_TRANSPORT` | `stdio` | `stdio`, or `http` for the companion's own listener. |
| `PORTFOLIXIR_MCP_TOKEN` | none, required for `http` | The bearer token HTTP clients present: at least 32 bytes and never a placeholder (`openssl rand -base64 48`). |
| `PORTFOLIXIR_MCP_HOST` | `127.0.0.1` | The address the HTTP listener binds. |
| `PORTFOLIXIR_MCP_PORT` | `4001` | The port the HTTP listener binds. |
| `PORTFOLIXIR_MCP_ALLOWED_HOSTS` | empty | Further `Host` names the HTTP listener answers under, comma-separated. |
| `PORTFOLIXIR_MCP_PROFILE` | empty, which is `full` | `read`, `book` or `full`. |
| `PORTFOLIXIR_MCP_READ_ONLY` | `false` | `true` is the `read` profile; beside `book` or `full` it stops the companion. |

The Compose file sets the transport, host and port for its own service; a
companion you start yourself reads them from its environment.

## First steps

Ask the agent to run the `first_setup` prompt: it checks the instance and the
profile, reads what exists, proposes a structure of accounts, depots, buckets
and views, and writes nothing without your confirmation. To bring in a bank or
broker export Portfolixir does not read, use the `import_converter` prompt:
the agent writes a converter that runs on your machine and hands you a file for
the Imports page, where you preview it and apply it.
