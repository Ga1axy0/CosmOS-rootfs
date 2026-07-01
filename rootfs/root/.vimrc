set nocompatible
syntax on
filetype plugin indent on
set background=dark
if &term =~# '256color' && &t_Co < 256
  set t_Co=256
endif
colorscheme default