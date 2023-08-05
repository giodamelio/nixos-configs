local wk = require('which-key')

wk.register({
  ['<Tab>'] = { '<cmd>bprevious<cr>', 'Switch to last buffer' },
}, { prefix = '<leader>' })
