local wk = require('which-key')

wk.register({
  ['<Tab>'] = { '<cmd>edit #<cr>', 'Switch to last buffer' },
}, { prefix = '<leader>' })
