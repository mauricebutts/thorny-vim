return {
  definition = {
    name        = 'Write',
    description = 'Write complete contents to a file, creating it if it does not exist.',
    parameters  = {
      type       = 'object',
      properties = {
        file_path = { type = 'string', description = 'Path to the file to write' },
        content   = { type = 'string', description = 'The full file contents' },
      },
      required = { 'file_path', 'content' },
    },
  },
  mode = 'pending',
}
