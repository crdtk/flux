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

MANAGEMENT += \
  /etc/systemd/system/sockets.target.wants/cockpit.socket \
  /etc/ssh/sshd_config.d/lan-password.conf \
  /etc/NetworkManager/conf.d/captive-portal.conf \
  $(PRINTER_PPD) \
  $(if $(ST_GUI_REMOTE_OK),,configure-syncthing-gui) \
  /usr/bin/rclone

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
	runuser -u $(RUN_AS_USER) -- env XDG_RUNTIME_DIR=/run/user/$(RUN_AS_UID) \
		systemctl --user enable --now syncthing
	@echo ">>> Syncthing enabled"
