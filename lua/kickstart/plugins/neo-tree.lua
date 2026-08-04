-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

vim.pack.add {
    { src = 'https://github.com/nvim-neo-tree/neo-tree.nvim', version = vim.version.range '*' },
    'https://github.com/nvim-lua/plenary.nvim',
    'https://github.com/MunifTanjim/nui.nvim',
}

vim.keymap.set('n', '\\', '<Cmd>Neotree reveal<CR>', { desc = 'NeoTree reveal', silent = true })

require('neo-tree').setup {
    filesystem = {
        filtered_items = {
            visible = true, -- This is required to show filtered items
            hide_dotfiles = false,
            hide_gitignored = false, -- Optional: set to false to also show git-ignored files
        },
        window = {
            mappings = {
                ['\\'] = 'close_window',
            },
        },
    },
}

