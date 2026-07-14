vim.pack.add {
  'https://github.com/ravsii/nvim-dap-envfile',
  'https://github.com/nicholasmata/nvim-dap-cs',
  'https://github.com/mfussenegger/nvim-dap-python',
}

require('nvim-dap-envfile').setup {}

require('dap-cs').setup({
    dap_configurations = {
        {
          type = 'coreclr',
          name = 'Attach remote',
          mode = 'remote',
          request = 'attach',
        },
      },
      netcoredbg = {
        path = vim.fn.expand '~/netcoredbg/netcoredbg',
      },
})

require('dap-python').setup '/home/srp/Code/BibleBot/BibleBot/src/BibleBot.Frontend/venv/bin/python'