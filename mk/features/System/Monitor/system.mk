MANAGEMENT += /etc/NetworkManager/conf.d/captive-portal.conf

define NM_CAPTIVE_PORTAL_CONF
[connectivity]
uri=http://nmcheck.gnome.org/check_network_status.txt
response=NetworkManager is online
interval=60
endef

/etc/NetworkManager/conf.d/:
	mkdir -p $@

/etc/NetworkManager/conf.d/captive-portal.conf: | /etc/NetworkManager/conf.d/
	$(file >$@,$(NM_CAPTIVE_PORTAL_CONF))
	@systemctl reload NetworkManager && echo ">>> Captive portal detection enabled"

MANAGEMENT += /etc/systemd/system/sockets.target.wants/cockpit.socket
MACHINE_IP := $(shell hostname -I | awk '{print $$1}')
/etc/systemd/system/sockets.target.wants/cockpit.socket: /usr/bin/cockpit
	@systemctl enable --now cockpit.socket && echo ">>> Cockpit: https://$(MACHINE_IP):9090"

/etc/ssh/sshd_config.d/:
	mkdir -p $@

LAN_SUBNET := $(shell ip route | awk '/proto kernel/ && !/wl|ww|lo|vir|br-|docker/{print $$1; exit}')

define SSH_LAN_PASSWORD_CONF
PasswordAuthentication no

Match Address $(LAN_SUBNET),127.0.0.1
	PasswordAuthentication yes
endef

MANAGEMENT += /etc/ssh/sshd_config.d/lan-password.conf

/etc/ssh/sshd_config.d/lan-password.conf: | /etc/ssh/sshd_config.d/
	$(file >$@,$(SSH_LAN_PASSWORD_CONF))
	@(systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true) && echo ">>> SSH password auth restricted to LAN ($(LAN_SUBNET))"

PRINTER_NAME := hp-laserjet-mfp-2604sdw
PRINTER_PPD  := /etc/cups/ppd/$(PRINTER_NAME).ppd
MANAGEMENT   += $(PRINTER_PPD)
PRINTER_IP   := $(shell avahi-browse -t -r -p _ipp._tcp 2>/dev/null | awk -F';' '/^=/ && /2604sdw/{print $$8; exit}')
PRINTER_URI   = ipp://$(PRINTER_IP)/ipp/print

$(PRINTER_PPD):
	@lpadmin -p $(PRINTER_NAME) -E -v $(PRINTER_URI) -m everywhere && lpoptions -d $(PRINTER_NAME) && echo ">>> Printer $(PRINTER_NAME) added at $(PRINTER_URI)"

$(PROJECTS):
	mkdir -p $@

ST_USER      ?= $(RUN_AS_USER)
ST_PASS      ?= change-me
ST_CONFIG_XML = $(USER_HOME)/.config/syncthing/config.xml
ST_STATE_XML  = $(USER_HOME)/.local/state/syncthing/config.xml

MANAGEMENT += /usr/bin/rclone

ST_GUI_JSON      = {"address":"0.0.0.0:8384","user":"$(ST_USER)","password":"$(ST_PASS)"}
ST_API_KEY       = $(shell grep -rh '<apikey>' $(ST_CONFIG_XML) $(ST_STATE_XML) 2>/dev/null | sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' | head -1)
ST_API_URL       = http://localhost:8384
ST_GUI_REMOTE_OK := $(shell grep -ql '0\.0\.0\.0:8384' $(ST_CONFIG_XML) $(ST_STATE_XML) 2>/dev/null && echo 1)
ST_API_RETRIES   = 30
RUN_AS_UID      := $(shell id -u $(RUN_AS_USER))
$(USER_HOME)/.config/systemd/user/default.target.wants/syncthing.service: /usr/bin/syncthing
	@loginctl enable-linger $(RUN_AS_USER); runuser -u $(RUN_AS_USER) -- env XDG_RUNTIME_DIR=/run/user/$(RUN_AS_UID) systemctl --user enable --now syncthing && echo ">>> Syncthing enabled"
ifeq ($(ST_GUI_REMOTE_OK),)
	@echo ">>> Waiting for Syncthing API..."; for i in $$(seq $(ST_API_RETRIES)); do curl -sf $(ST_API_URL)/rest/noauth/health >/dev/null 2>&1 && break || sleep 1; done; curl -sS -X PATCH $(ST_API_URL)/rest/config/gui -H "X-API-Key: $(ST_API_KEY)" -H "Content-Type: application/json" -d '$(ST_GUI_JSON)' && echo ">>> Syncthing GUI remote enabled"
endif
