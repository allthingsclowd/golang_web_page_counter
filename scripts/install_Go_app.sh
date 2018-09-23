#!/usr/bin/env bash
set -x

source /usr/local/bootstrap/var.env

# download binary and template file from latest release
curl -s https://api.github.com/repos/allthingsclowd/web_page_counter/releases/latest \
| grep "browser_download_url" \
| cut -d : -f 2,3 \
| tr -d \" | wget -i -

[[ -d /usr/local/bin/templates ]] || mkdir /usr/local/bin/templates

nomad job stop webpagecounter &>/dev/null
killall webcounter &>/dev/null
mv webcounter /usr/local/bin/.
mv *.html /usr/local/bin/templates/.
chmod +x /usr/local/bin/webcounter

cp /usr/local/bootstrap/scripts/consul_goapp_verify.sh /usr/local/bin/.

nomad job run /usr/local/bootstrap/nomad_job.hcl || true

