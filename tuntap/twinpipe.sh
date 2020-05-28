#!/bin/sh

VERSION=1.0.3

cmd1=""
cmd2=""

help=0
error=0
cmdnum=0
delfirst=1
for opt; do
  case "\$opt" in
    --help | -help | -h)
      help=1
      ;;
    -d)
      delfirst=0
      ;;
    -*)
      echo "\$0: Invalid option \`\$opt\'" >&2
      error=1
      ;;
    *)
      if test \$cmdnum = 2; then
        echo "\$0: Can't twinlink more than two processes." >&2
        error=1
      else
        if test \$cmdnum = 1; then
          cmd2="\$opt"
          cmdnum=2
        else
          cmd1="\$opt"
          cmdnum=1
        fi
      fi
      ;;
  esac
done

if test ! \$cmdnum = 2 -a \$help = 0; then
  echo "\$0: You must specify two commands." >&2
  error=1
fi

if test \$help = 1; then
  cat<<EOF
\$0 v\$VERSION - Copyright (C) 1992,2002 Bisqwit (http://iki.fi/bisqwit/)
The sourcecode of this program is available at the author's pages.

Usage: \$0 [-d] <command1> <command2>

This program runs command1 and command2 simultaneously,
so that command1's output is piped to command2 and
command2's output is piped to command1.

\$0 creates a temporary fifo in /tmp directory, and
deletes it as soon as possible, unless you use -d switch, in which
case the fifo is deleted after both the processes have terminated.

Demonstration of usage (not a demonstration of applicability):
  \$0 'echo a;head -n 1 >&2' 'echo b;echo c'

For an example of applicability, you could use this program to create
ppp tunnels via ssh, for example, linking the two ppp programs together.
EOF
else
  if test \$error = 0; then
    uniqid="\$\$`date +%S%M%H%d%m%Y`"

    fifo=/tmp/twinpipe.pipe."\$uniqid"

    if mkfifo "\$fifo"; then
      sh -c "\$cmd1" < "\$fifo" | \
      sh -c "\$cmd2" > "\$fifo" &
      if test \$delfirst = 1; then rm -f "\$fifo"; fi
      wait
      if test \$delfirst = 0; then rm -f "\$fifo"; fi
    else
      echo "\$0: mkfifo failed for \`\$fifo\'" >&2
    fi
  fi
fi
