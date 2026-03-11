# sealed
compile time method lookups for typed lexicals declared within a :sealed sub

[![CPAN version](https://badge.fury.io/pl/sealed.svg)](https://metacpan.org/pod/sealed) [![Build Status](https://github.com/SunStarSys/sealed/actions/workflows/linter.yml/badge.svg?branch=master)](https://github.com/SunStarSys/sealed/actions?query=branch%3Amaster)

See <https://sunstarsys.com/essays/perl7-sealed-lexicals>.

Also installs B::Delivered and clown, which you can try out post-install by the following:

```shell
% perl -MO=Delivered -e 'sub foo {bar()}'
```
