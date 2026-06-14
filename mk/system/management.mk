PROJECTS    := $(USER_HOME)/Desktop/Projects
RUN_AS_USER := $(or $(SUDO_USER),$(USER))
RUN_AS_UID  := $(shell id -u $(RUN_AS_USER))

PRINTER_NAME := hp-laserjet-mfp-2604sdw
PRINTER_PPD  := /etc/cups/ppd/$(PRINTER_NAME).ppd
PRINTER_IP   := $(shell avahi-browse -t -r -p _ipp._tcp 2>/dev/null | awk -F';' '/^=/ && /2604sdw/{print $$8; exit}')
PRINTER_URI  := ipp://$(PRINTER_IP)/ipp/print

ST_USER          ?= $(RUN_AS_USER)
ST_PASS          ?= change-me
ST_CONFIG_XML     = $(USER_HOME)/.config/syncthing/config.xml
ST_STATE_XML      = $(USER_HOME)/.local/state/syncthing/config.xml
ST_GUI_REMOTE_OK := $(shell grep -ql '0\.0\.0\.0:8384' $(ST_CONFIG_XML) $(ST_STATE_XML) 2>/dev/null && echo 1)

MACHINE_IP := $(shell hostname -I | awk '{print $$1}')
LAN_SUBNET := $(shell ip route | awk '/proto kernel/ && !/wl|ww|lo|vir|br-|docker/{print $$1; exit}')

# DynDNS reaches crucible over IPv6 (IPv4 is carrier-NAT). Publish a stable
# EUI-64 address so the AAAA record matches the FRITZ!Box port forwarding.
WAN_IF      := $(shell ip -o route show default | awk '{print $$5; exit}')
WAN_CON     := $(shell nmcli -t -g GENERAL.CONNECTION device show $(WAN_IF) 2>/dev/null)
DYNV6_TOKEN  = $(shell sed -n 's/^password=//p' $(PROJECTS)/secrets/ddclient.conf | tr -d "'\"")

# Tailscale repo is keyed per Ubuntu release; override if the current codename
# isn't published yet:  sudo make TS_DIST=oracular /usr/bin/tailscale
TS_DIST ?= $(UBUNTU_CODENAME)
TS_CONNECTED := $(shell tailscale status >/dev/null 2>&1 && echo 1)
TS_AUTHKEY    = $(shell cat $(PROJECTS)/secrets/tailscale.authkey 2>/dev/null)

MANAGEMENT += \
  /etc/NetworkManager/conf.d/ipv6-stable.conf \
  /etc/ddclient.conf \
  /usr/bin/tailscale \
  $(if $(wildcard $(PROJECTS)/secrets/tailscale.authkey),$(if $(TS_CONNECTED),,tailscale-up)) \
  /etc/systemd/system/sockets.target.wants/cockpit.socket \
  /etc/ssh/sshd_config.d/lan-password.conf \
  /etc/NetworkManager/conf.d/captive-portal.conf \
  $(PRINTER_PPD) \
  $(if $(ST_GUI_REMOTE_OK),,configure-syncthing-gui) \
  /usr/bin/rclone

define DDCLIENT_CONF
ssl=yes
protocol=dyndns2
server=dynv6.com
login=none
password=$(DYNV6_TOKEN)
usev4=webv4, webv4=https://api.ipify.org/
usev6=ifv6, ifv6=$(WAN_IF)
concise.dynv6.net
endef

# Real file (not a symlink): ddclient refuses a world-readable config, so the
# deployed copy must be root-owned 0600. Token is sourced from the secrets repo.
/etc/ddclient.conf: $(PROJECTS)/secrets/ddclient.conf /usr/bin/ddclient
	systemctl disable --now dynv6-update.timer dynv6-update.service 2>/dev/null || true
	rm -f /etc/systemd/system/dynv6-update.service /etc/systemd/system/dynv6-update.timer
	$(file >$@,$(DDCLIENT_CONF))
	chown root:root $@
	chmod 600 $@
	systemctl enable ddclient
	systemctl restart ddclient
	@echo ">>> ddclient dual-stack configured (IPv4 web, IPv6 $(WAN_IF)), 0600 root"

define NM_IPV6_STABLE
[connection]
ipv6.ip6-privacy=0
ipv6.addr-gen-mode=eui64
endef

# EUI-64 IID makes crucible's global IPv6 stable and predictable, matching the
# suffix the FRITZ!Box forwards 22/8384/80 to. Privacy addresses rotate and break
# inbound. addr-gen-mode applies only on reactivation, so set it on the WAN
# connection and bounce it — briefly drops the link (fine, the box is local).
/etc/NetworkManager/conf.d/ipv6-stable.conf:
	$(file >$@,$(NM_IPV6_STABLE))
	nmcli connection modify "$(WAN_CON)" ipv6.addr-gen-mode eui64 ipv6.ip6-privacy 0
	nmcli connection up "$(WAN_CON)"
	@echo ">>> IPv6 stable EUI-64 applied on $(WAN_IF) ($(WAN_CON))"

# Keyring path matches Tailscale's official installer (and the self-updating
# tailscale-archive-keyring pkg), so script-install and make-install converge.
# The noarmor.gpg is already dearmored upstream — store it as-is.
/usr/share/keyrings/tailscale-archive-keyring.gpg:
	mkdir -p $(dir $@)
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(TS_DIST).noarmor.gpg > $@

/etc/apt/sources.list.d/tailscale.list: /usr/share/keyrings/tailscale-archive-keyring.gpg
	echo 'deb [signed-by=$<] https://pkgs.tailscale.com/stable/ubuntu $(TS_DIST) main' > $@

# Non-interactive node auth via a reusable key in secrets/ (mirrors the dynv6
# token). Gated in MANAGEMENT like configure-syncthing-gui: only runs when a key
# exists and the node isn't connected, so it's a no-op on every later make.
.PHONY: tailscale-up
tailscale-up: /usr/bin/tailscale
	tailscale up --authkey=$(TS_AUTHKEY) --ssh
	@echo ">>> Tailscale connected — check 'tailscale status'"

$(PROJECTS)/secrets/ddclient.conf: | $(PROJECTS)
	sudo -u $(RUN_AS_USER) git clone git@github.com:crdtk/secrets.git $(PROJECTS)/secrets

$(PROJECTS):
	mkdir -p $@

define NM_CAPTIVE_PORTAL_CONF
[connectivity]
uri=http://nmcheck.gnome.org/check_network_status.txt
response=NetworkManager is online
interval=60
endef

/etc/NetworkManager/conf.d/captive-portal.conf:
	mkdir -p $(dir $@)
	$(file >$@,$(NM_CAPTIVE_PORTAL_CONF))
	systemctl reload NetworkManager
	@echo ">>> Captive portal detection enabled"

/etc/systemd/system/sockets.target.wants/cockpit.socket: /usr/bin/cockpit
	systemctl enable --now cockpit.socket
	@echo ">>> Cockpit: https://$(MACHINE_IP):9090"

define SSH_LAN_PASSWORD_CONF
PasswordAuthentication no

Match Address $(LAN_SUBNET),127.0.0.1
	PasswordAuthentication yes
endef

/etc/ssh/sshd_config.d/:
	mkdir -p $@

/etc/ssh/sshd_config.d/lan-password.conf: | /etc/ssh/sshd_config.d/
	$(file >$@,$(SSH_LAN_PASSWORD_CONF))
	systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
	@echo ">>> SSH password auth restricted to LAN ($(LAN_SUBNET))"

$(PRINTER_PPD):
	lpadmin -p $(PRINTER_NAME) -E -v $(PRINTER_URI) -m everywhere
	lpoptions -d $(PRINTER_NAME)
	@echo ">>> Printer $(PRINTER_NAME) added at $(PRINTER_URI)"

.PHONY: configure-syncthing-gui
ST_API_URL  := http://localhost:8384
ST_GUI_JSON  = {"address":"0.0.0.0:8384","user":"$(ST_USER)","password":"$(ST_PASS)"}
ST_API_KEY   = $(shell grep -rh '<apikey>' $(ST_CONFIG_XML) $(ST_STATE_XML) 2>/dev/null | sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' | head -1)
configure-syncthing-gui: wait-syncthing-api
	@curl -sS -X PATCH $(ST_API_URL)/rest/config/gui \
		-H "X-API-Key: $(ST_API_KEY)" \
		-H "Content-Type: application/json" \
		-d '$(ST_GUI_JSON)'
	@echo ">>> Syncthing GUI remote enabled"

.PHONY: wait-syncthing-api
ST_API_RETRIES := 30
wait-syncthing-api: $(USER_HOME)/.config/systemd/user/default.target.wants/syncthing.service
	@echo ">>> Waiting for Syncthing API..."
	@for i in $(shell seq $(ST_API_RETRIES)); do curl -sf $(ST_API_URL)/rest/noauth/health >/dev/null 2>&1 && break || sleep 1; done

$(USER_HOME)/.config/systemd/user/default.target.wants/syncthing.service: /usr/bin/syncthing
	loginctl enable-linger $(RUN_AS_USER)
	sudo -u $(RUN_AS_USER) env XDG_RUNTIME_DIR=/run/user/$(RUN_AS_UID) \
		systemctl --user enable --now syncthing
	@echo ">>> Syncthing enabled"
