-- Server tool: Anthropic executes search on its own infrastructure.
-- No execute function needed — the API handles it.
return {
  definition = {
    type = 'web_search_20260318',
    name = 'web_search',
  },
  mode = 'server',
}
