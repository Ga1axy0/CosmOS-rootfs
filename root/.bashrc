export TERM=${TERM:-xterm-256color}
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/root:/mnt/musl:/mnt/glibc:/mnt/musl/ltp/testcases/bin:/mnt/glibc/ltp/testcases/bin
export PS1='root@CosmOS:\w# '
alias ll='ls -l'
alias la='ls -la'

if [ "${TERM}" != "dumb" ]; then
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi
