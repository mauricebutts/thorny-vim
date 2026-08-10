return {
  definition = {
    name        = 'Edit',
    description = 'Replace exact text in a file. old_string must match exactly (including whitespace).',
    parameters  = {
      type       = 'object',
      properties = {
        file_path  = { type = 'string', description = 'Path to the file to edit' },
        old_string = { type = 'string', description = 'The exact text to replace' },
        new_string = { type = 'string', description = 'The replacement text' },
      },
      required = { 'file_path', 'old_string', 'new_string' },
    },
  },
  mode = 'pending',
}
