
" Basic settings
set nocompatible
set encoding=utf-8
set fileencoding=utf-8
set backspace=indent,eol,start

" Swap file and backup settings
set swapfile
set directory=~/.cache/vim/swap//
set backupdir=~/.cache/vim/backup//
set undodir=~/.cache/vim/undo//

" Create cache directories
if !isdirectory(expand("~/.cache/vim/swap"))
    call mkdir(expand("~/.cache/vim/swap"), "p")
endif
if !isdirectory(expand("~/.cache/vim/backup"))
    call mkdir(expand("~/.cache/vim/backup"), "p")
endif
if !isdirectory(expand("~/.cache/vim/undo"))
    call mkdir(expand("~/.cache/vim/undo"), "p")
endif

" Enable syntax highlighting
syntax on

" Undo history
set undofile
set undolevels=1000
set undoreload=10000

" Indentation
set expandtab
set tabstop=2
set shiftwidth=2
set softtabstop=2
set autoindent
set smartindent

" Search
set hlsearch
set incsearch
set ignorecase
set smartcase

" Set clipboard (if available)
set clipboard=unnamedplus

" Set a simple status line
set statusline=%m%f:%l,%c:%c::%r

" Enable quickfix window
set completeopt=menu,menuone

" UI
set showmatch
set matchtime=2
set mouse=a
" set foldmethod=indent

" File handling
set autoread
set autowrite
set hidden

" Key mappings
let mapleader=" "

" Quick save
nnoremap <leader>w :w<CR>
