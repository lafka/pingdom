#!/bin/sh

export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/usr/local/sbin

if [ ! -z "$_KERL_ACTIVE_DIR" ]; then
   . "$_KERL_ACTIVE_DIR/activate"
fi

set -ex

vsn=$(mix vsn)
project=$(mix project)
export MIX_ENV=${MIX_ENV:-dev}

mix deps.compile
mix compile
mix release.clean
mix release --env $MIX_ENV
mkdir -p /data/release/${MIX_ENV}
rm -f /data/release/${MIX_ENV}/${vsn}.tar.xz  || true
tar -cJf /data/release/${MIX_ENV}/${vsn}.tar.xz  -C _build/${MIX_ENV}/rel/ ./${project}
