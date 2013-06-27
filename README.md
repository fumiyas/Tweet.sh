Twitter client implemented in bash/ksh/zsh
======================================================================

  * Copyright (c) 2013 SATOH Fumiyasu @ OSS Technology Corp., Japan
  * License: GNU General Public License version 3
  * Development home: <https://GitHub.com/fumiyas/Tweet.sh>
  * Author's home: <http://fumiyas.github.io/>

What's this?
---------------------------------------------------------------------

A Twitter client implemented in bash/ksh/zsh.

Requirements
---------------------------------------------------------------------

  * `bash`(1), `ksh`(1) or `zsh`(1)
  * `openssl`(1)
  * `sed`(1)
  * `sort`(1)
  * `tr`(1)

How to build and install
---------------------------------------------------------------------

    $ make
    ...
    $ sudo make install
    ...

Usage
---------------------------------------------------------------------

When you invoke `tweet` command for the first time, you can see the
following messages:

    $ /usr/local/bin/tweet 'やっはろー'
    No OAuth access token and/or secret for Twitter access configured.

    I'll open Twitter site by a WWW browser to get OAuth access token
    and secret. Please authorize this application and get a PIN code
    on Twitter site.

    Press Enter key to open Twitter site...

If you press Enter key, `tweet` opens Twitter site on your WWW browser.
Then you must login to Twitter, authorize `tweet` command (shown as
"fumiyas/Tweet.sh" on Twitter site), get a PIN code and return to `tweet`:

    Enter PIN code: <ENTER PIN CODE HERE>

    Saving OAuth consumer key and secret into /home/you/.tweet.conf...
    Saving OAuth access token and secret into /home/you/.tweet.conf...

Finally, you can use `tweet` command without the above procedure.

    $ /usr/local/bin/tweet 'はろーあろーん'

Enjoy!

