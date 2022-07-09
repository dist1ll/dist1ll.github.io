filetype on
filetype plugin on
setlocal ff=unix
set fileformat=unix
set fileformats=unix,dos
syntax on

call plug#begin('~/.vim/plugged')

Plug 'rust-lang/rust.vim'

" Collection of common configurations for the Nvim LSP client
Plug 'neovim/nvim-lspconfig'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'hrsh7th/nvim-cmp'

" Autocompletion framework
Plug 'dcampos/nvim-snippy'
Plug 'dcampos/cmp-snippy'

" Adds extra functionality over rust analyzer
Plug 'simrat39/rust-tools.nvim'


" Debugging
Plug 'nvim-lua/plenary.nvim'

" Fuzzy finder (so much better than fzf)
Plug 'ctrlpvim/ctrlp.vim'

" Make things pretty
Plug 'm2q/onehalf'
Plug 'vim-airline/vim-airline'
Plug 'xiyaowong/nvim-transparent'

call plug#end()

set cursorline
let g:airline_theme='onehalfdark'
colorscheme onehalfdark

lua <<EOF
require("transparent").setup({
  enable = true, -- boolean: enable transparent
  extra_groups = { -- table/string: additional groups that should be clear
    -- In particular, when you set it to 'all', that means all avaliable groups

    -- example of akinsho/nvim-bufferline.lua
    "airline_tabfill",
    "airline_c",
    "BufferLineTabClose",
    "BufferlineBufferSelected",
    "BufferLineFill",
    "BufferLineBackground",
    "BufferLineSeparator",
    "BufferLineIndicatorSelected",
  },
  exclude = {}, -- table: groups you don't want to clear
})
EOF

set completeopt=menuone,noinsert,noselect
set shortmess+=c
lua <<EOF

-- nvim_lsp object
local nvim_lsp = require'lspconfig'
local opts = {
    tools = {
        autoSetHints = true,
        hover_with_actions = true,
        inlay_hints = {
            show_parameter_hints = false,
            parameter_hints_prefix = "",
            other_hints_prefix = "",
        },
    },
    server = {
        settings = {
            ["rust-analyzer"] = {
                checkOnSave = {
                    command = "clippy"
                },
            }
        }
    },
}

require('rust-tools').setup(opts)
EOF

lua <<EOF
local cmp = require'cmp'
cmp.setup({
    snippet = {
      -- REQUIRED - you must specify a snippet engine
      expand = function(args)
        require('snippy').expand_snippet(args.body) 
      end,
    },
  mapping = {
    ['<C-d>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-e>'] = cmp.mapping.close(),
    ['<CR>'] = cmp.mapping.confirm({
      behavior = cmp.ConfirmBehavior.Insert,
      select = true,
    })
  },
  sources = {
    { name = 'nvim_lsp' },
  },
})
EOF

" LSP BINDINGS
" Renaming
nnoremap <Leader>r <cmd>lua vim.lsp.buf.rename()<CR>
nnoremap q <cmd>lua vim.lsp.buf.hover()<CR>

" have a fixed column for the diagnostics to appear in
" this removes the jitter when warnings/errors flow in
set signcolumn=yes

" sensible editing defaults
set backspace=indent,eol,start
set relativenumber
set noerrorbells
set tabstop=4
set shiftwidth=4
set autoindent
set nu
set nowrap
set smartcase
set noswapfile
set nobackup
set incsearch
set ignorecase
set smartcase
set nowrapscan
set termguicolors
set encoding=utf-8
set scrolloff=20
set ttyfast


" Moving
nnoremap # ^
nnoremap f t
nnoremap t f

" Autocomplete
inoremap " ""<left>
inoremap { {}<left>
inoremap [ []<left>
inoremap ( ()<left>
let g:autoclose_on = 0

" Tabs
set path=.,,**

" New File / Buffer
nnoremap <c-n> :enew<CR>

" File Browsing
let g:netrw_banner = 0
let g:netrw_browse_split = 0
let g:netrw_winsize = 25

" Splitting
set splitbelow

" Split bindings
nnoremap <silent> <c-a> :wincmd h<CR>
nnoremap <silent> <c-e> :wincmd l<CR>
nnoremap <Leader>q <c-w>=

nnoremap <silent> <Tab> :bnext<CR>
nnoremap <silent> <S-Tab> :bNext<CR>

" Terminal bindings
nnoremap <silent> <c-t> :terminal<CR>
tnoremap <silent> <c-x> <C-\><C-n>
tnoremap <silent> <c-a> <C-\><C-n> <bar> :wincmd h<CR>
tnoremap <silent> <c-e> <C-\><C-n> <bar> :wincmd l<CR>

" Quick Save
nnoremap <Leader>s :write<CR>

" Fuzzy finding
let g:ctrlp_map = '<c-q>'
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_user_command = ['.git', 'cd %s && git ls-files -co --exclude-standard']

" Format
nnoremap <silent> <Leader>f :lua vim.lsp.buf.formatting_sync(nil, 200)<CR>

" Escape extensions
" Clear highlight 

augroup EditVim
  autocmd!
  autocmd FileType rust inoremap <Esc> <Esc>:update<CR>
augroup END

" Airline
let g:airline_extensions = ['tabline']
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#left_sep = ' '
let g:airline#extensions#tabline#left_alt_sep = '|'
let g:airline#extensions#tabline#formatter = 'unique_tail'
