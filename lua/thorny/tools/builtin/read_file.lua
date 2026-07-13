local context = require('thorny.context')

return {
  definition = {
    name        = 'ReadFile',
    description = 'Read the full contents of a file. Call this before editing a file or answering questions about its contents.',
    input_schema = {
      type       = 'object',
      properties = {
        file_path = { type = 'string', description = 'Path to the file, relative to the project root' },
      },
      required = { 'file_path' },
    },
  },
  mode = 'auto',
  -- execute(input, ctx) → string result sent back as tool_result content
  -- ctx = { cwd = string }
  execute = function(input, ctx)
    local path = input.file_path or ''
    local abs  = path:sub(1, 1) == '/' and path or (ctx.cwd .. '/' .. path)
    local content = context.read_file(abs)
    return content or 'Error: file not found or unreadable'
  end,
}
