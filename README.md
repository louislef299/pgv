# ishi

Embeds your git commit history into a pgvector database for semantic similarity
search. The more you commit, the smarter it gets.

*ishi* means ["within"][Black Speech of Mordor].

## Prerequisites

- Zig (0.15.2)
- Docker Desktop (with [Model Runner][] enabled)
- (Optional) Ollama — alternative model runner (`--runner ollama`)
- (Optional) `psql`

To install the dependencies with [`brew`][] leveraging the `Brewfile`, run a
quick `brew bundle check --all -v` to verify which dependencies you are missing
and `brew bundle install -v` to install all the dependencies.

## Setup

```sh
docker compose up -d   # starts pgvector + pulls the embedding model
zig build
```

## Usage

```sh
./zig-out/bin/ishi init
./zig-out/bin/ishi seed --path src/seed.json
./zig-out/bin/ishi query "what is comptime?"
./zig-out/bin/ishi --help
```

## Ollama (alternative runner)

ishi defaults to [Docker Model Runner][Model Runner] for embeddings. To use
Ollama instead, pass `--runner ollama` and pull the model yourself:

```sh
ollama pull nomic-embed-text
./zig-out/bin/ishi seed --runner ollama --model nomic-embed-text --git
```

ishi also ships with a [Modelfile][] that creates a local LLM tuned for
answering questions about your codebase using context from the vector database.

```sh
ollama create ishi -f ./Modelfile
ollama run ishi
```

| Parameter     | Value    | Rationale   |
|---------------|----------|------------ |
| Base model    | llama3.2 | 3B params, fast local inference, strong instruction-following         |
| temperature   | 0.3      | Low creativity -- favors factual, grounded answers over hallucination |
| num\_ctx      | 4096     | Room for system prompt + retrieved context + question + response      |
| top\_p        | 0.9      | Conservative nucleus sampling, pairs well with low temperature        |

[Black Speech of Mordor]: https://tolkiengateway.net/wiki/Black_Speech
[`brew`]: http://louislefebvre.net/tech/brew-tips/#reproducibility-with-brewfile
[Model Runner]: https://docs.docker.com/desktop/features/model-runner/
[Modelfile]: https://docs.ollama.com/modelfile
