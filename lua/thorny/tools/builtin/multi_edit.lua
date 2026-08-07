return {
  definition = {
    name        = 'MultiEdit',
    description = 'Apply multiple Edit operations to a single file.',
    parameters  = {
      type       = 'object',
      properties = {
        file_path = { type = 'string', description = 'Path to the file to edit' },
        edits     = {
          type  = 'array',
          items = {
            type       = 'object',
            properties = {
              old_string = { type = 'string' },
              new_string = { type = 'string' },
            },
            required = { 'old_string', 'new_string' },
          },
        },
      },
      required = { 'file_path', 'edits' },
    },
  },
  mode = 'pending',
}
