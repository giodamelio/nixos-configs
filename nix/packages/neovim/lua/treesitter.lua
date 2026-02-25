local rainbow_delimiters = require('rainbow-delimiters')
local rainbowsetup = require('rainbow-delimiters.setup')

rainbowsetup({
  strategy = {
    [''] = rainbow_delimiters.strategy['global'],
    vim = rainbow_delimiters.strategy['local'],
  },
  query = {
    [''] = 'rainbow-delimiters',
    lua = 'rainbow-blocks',
  },
  highlight = {
    'RainbowDelimiterRed',
    'RainbowDelimiterYellow',
    'RainbowDelimiterBlue',
    'RainbowDelimiterOrange',
    'RainbowDelimiterGreen',
    'RainbowDelimiterViolet',
    'RainbowDelimiterCyan',
  },
})

-- Enable Hurl
vim.filetype.add({
  extension = {
    hurl = 'hurl',
  },
})
