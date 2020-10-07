# my-freepbx
Configurations and scripts for setting up freepbx my way.  Eventually to be image-ified.

setup.sh pretty much handles everything right now, with a few exceptions:

1. Still have to set timezone manually (because maybe you don't want to be in America/Los_Angeles, amirite?):
> timedatectl list-timezones | grep $YOUR_TIMEZONE
> timedatectl set-timezone $YOUR_TIMEZONE

2. Gotta make sure you copy over the nftables and fail2ban configs from the included /etc folder.
Automating this is a TODO.
