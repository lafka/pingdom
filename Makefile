build-stage:
	sudo lxc-attach -n build -- /bin/su build -c "MIX_ENV=stage ./build.sh"

build-prod:
	sudo lxc-attach -n build -- /bin/su build -c "MIX_ENV=prod ./build.sh"

