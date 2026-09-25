return {
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    ft = { 'markdown' },
    opts = {
        file_types = { 'markdown' },
    },
    config = function(_, opts)
        require('render-markdown').setup(opts)
        vim.api.nvim_create_autocmd('FileType', {
            pattern = 'markdown',
            callback = function()
                vim.opt_local.conceallevel = 2
            end,
        })
    end,
}
