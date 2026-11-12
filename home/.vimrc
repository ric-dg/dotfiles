" vim on servers without Neovim. Pushed by dotpush: edit ~/.config/dotpush/files/.vimrc on the laptop, then re-push.
" Same options and <Space> keys as the Neovim config. Everything sits inside `if 1` so a minimal
" vim-tiny ("vi") skips it silently instead of printing errors.
if 1
  set nocompatible encoding=utf-8
  syntax on
  filetype plugin indent on
  set number relativenumber mouse=a ignorecase smartcase hlsearch incsearch
  set expandtab shiftwidth=4 tabstop=4 smartindent backspace=indent,eol,start
  set noswapfile scrolloff=8 updatetime=250 splitright splitbelow
  set laststatus=2 wildmenu ttimeout ttimeoutlen=10
  set list listchars=tab:»\ ,trail:·,nbsp:␣
  set path+=**
  if has('persistent_undo')
    set undofile undodir=~/.vim/undo
    silent! call mkdir(&undodir, 'p')
  endif

  let mapleader = " "
  " Ctrl-L clears search highlight (mapping <Esc> misbehaves in terminal vim)
  nnoremap <silent> <C-l> :nohlsearch<CR><C-l>
  nnoremap <leader>w :write<CR>
  nnoremap <leader>e :Explore<CR>
  nnoremap <leader>f :find **/
  nnoremap <leader>g :silent grep!
  if executable('rg')
    set grepprg=rg\ --vimgrep\ --smart-case grepformat=%f:%l:%c:%m
  endif
endif
