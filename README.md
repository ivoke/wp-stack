# WP Stack

This is an adaption of [markjaquith's great WordPress-Skeleton](https://github.com/markjaquith/WordPress-Skeleton) for Mittwald hosting environments

* deploy via copy, meaning no ssh tools need to be available on the production shell.
* relative file linking, mittwalds' apache config does not allow absolute linkage.
* (suboptimal) htaccess rewrite of apache root folder to `/html/current` as `/html` is the only folder writable for us
* staging is seen as local/dev platform currently

wp-stack assumes to be living as a submodule inside your wp-skeleton directory under ./cap
