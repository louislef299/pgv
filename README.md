# ishi

The goal of ishi is to look within your git history to build understanding
alongside you. It embeds your commits, learns what matters, and surfaces
insights as you grow -- AI that lives within your workflow, not outside it.

*ishi* means "within" in the [Black Speech of Mordor][] -- and that's where it
lives. Within your git history, finding patterns across commits. Within your
workflow, learning as you learn. The more you commit, the smarter it gets,
turning your repository into a knowledge base that grows with you and your team.

Whether you store your embeddings locally across projects or isolate your
embeddings to a specific project, each backend instance can be referenced by a
model to quickly understand your programming style.

## Example

```sh
# Seed the database with embeddings
$ git ishi seed

# Query for similar snippets
$ git ishi query "containerized web server with TLS"
1. "Dockerfile for a multi-stage Go build with minimal runtime image" (distance: 0.23)
2. "Nginx reverse proxy config with Let's Encrypt SSL" (distance: 0.31)
3. "Docker Compose stack with Traefik and automatic HTTPS" (distance: 0.35)
```

## Stack

| Component | Technology |
| --------- | ---------- |
| Language | Zig |
| Database | PostgreSQL 18 + pgvector 0.8.2 |
| Embeddings | Ollama with `nomic-embed-text` (768 dimensions, runs locally) |
| Postgres driver | [pg.zig](https://github.com/karlseguin/pg.zig) |
| HTTP client | [zul](https://github.com/karlseguin/zul) |
| JSON | `std.json` (Zig stdlib) |

## Prerequisites

- Zig (0.14+)
- Docker / Docker Compose (for PostgreSQL + pgvector)
- Ollama with `nomic-embed-text` model pulled

## Setup

### 1. Start PostgreSQL with pgvector

```sh
docker compose up -d
```

### 2. Create the database and enable pgvector

```sh
createdb mydb -U postgres -h localhost
psql -U postgres -h localhost mydb -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### 3. Install and run Ollama

```sh
# macOS
brew install ollama
ollama serve  # or it may already be running as a service

# Pull the embedding model
ollama pull nomic-embed-text
```

### 4. Build and run

```sh
zig build
./zig-out/bin/ishi seed
./zig-out/bin/ishi query "your search here"
```

## Implementation steps

These are the milestones to work through:

### Step 1: Zig project setup

- Initialize a Zig project with `zig init`
- Add `pg.zig` and `zul` as dependencies in `build.zig.zon`
- Get a "hello world" compiling

### Step 2: Connect to PostgreSQL

- Use `pg.zig` to connect to the local pgvector database
- Create the snippets table: `CREATE TABLE IF NOT EXISTS snippets (id bigserial
  PRIMARY KEY, content text NOT NULL, embedding vector(768))`
- Run a simple query to verify the connection works

### Step 3: Call Ollama for embeddings

- Use `zul` HTTP client to POST to `http://localhost:11434/api/embed`
- Request body: `{"model": "nomic-embed-text", "input": "your text here"}`
- Parse the response to extract the embedding (an array of 768 floats)

### Step 4: Seed the database

- Define the hardcoded snippet list
- For each snippet, generate its embedding via Ollama
- Insert the snippet text + embedding into the `snippets` table
- Format the embedding as a pgvector literal: `'[0.1, 0.2, ..., 0.768]'`

### Step 5: Query by similarity

- Take a query string from CLI args
- Embed the query using Ollama
- Run: `SELECT content, embedding <-> $1::vector AS distance FROM snippets ORDER
  BY distance LIMIT 5`
- Print the results

### Step 6 (optional): Add an index

- Once it works, add an IVFFlat or HNSW index for faster similarity search
- For ~30 rows this is unnecessary, but good to learn

## Ollama API reference

### Generate embeddings

```sh
curl http://localhost:11434/api/embed -d '{
  "model": "nomic-embed-text",
  "input": "Dockerfile for a multi-stage Go build"
}'
```

Response:

```json
{
  "model": "nomic-embed-text",
  "embeddings": [[0.0123, -0.0456, ...]]
}
```

`nomic-embed-text` produces 768-dimensional vectors.

## pgvector quick reference

```sql
-- Nearest neighbor search (L2 distance)
SELECT * FROM snippets ORDER BY embedding <-> '[0.1, 0.2, ...]' LIMIT 5;

-- Cosine distance
SELECT * FROM snippets ORDER BY embedding <=> '[0.1, 0.2, ...]' LIMIT 5;

-- Inner product (negate for max)
SELECT * FROM snippets ORDER BY embedding <#> '[0.1, 0.2, ...]' LIMIT 5;
```

[Black Speech of Mordor]: https://tolkiengateway.net/wiki/Black_Speech
