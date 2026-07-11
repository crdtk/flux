%% net/observability — Prometheus + Grafana for the vLLM bench rig: scrape both
%% bench servers' /metrics (KV usage, queue depth, preemptions, TTFT) and serve
%% the official vLLM dashboard at http://crucible.local:3000 (admin/admin on
%% first login). Prometheus listens on :9095 — Ubuntu's default :9090 is
%% Cockpit's port on this box.

apt_repo(grafana_repo, Check, AddCmd) :-
    Check = "test -f /etc/apt/sources.list.d/grafana.list",
    AddCmd = "mkdir -p /etc/apt/keyrings && curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg && echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list && apt-get update".

binary_pkg('/usr/sbin/grafana-server', 'grafana').
binary_pkg('/usr/bin/prometheus', 'prometheus').
pkg_repo('grafana', grafana_repo).

%% Port move is an invariant of the service being up (XVIII): enabling on :9090
%% would just crash-loop against Cockpit.
service_check(prometheus_port, Check, Fix) :-
    Check = "grep -qs 'web.listen-address=:9095' /etc/default/prometheus",
    Fix = "printf 'ARGS=\"--web.listen-address=:9095\"\\n' > /etc/default/prometheus".
service_check(prometheus_scrapes_vllm, Check, Fix) :-
    Check = "grep -qs 'job_name: vllm' /etc/prometheus/prometheus.yml",
    Fix = "printf '%s\\n' '' '  - job_name: vllm' '    static_configs:' \"      - targets: ['localhost:8000','localhost:8001']\" >> /etc/prometheus/prometheus.yml".
service_check(prometheus_running, Check, Fix) :-
    Check = "systemctl is-enabled --quiet prometheus && systemctl is-active --quiet prometheus",
    Fix = "systemctl enable --now prometheus && systemctl restart prometheus".
service_deps(prometheus_running,
    [service_ready(prometheus_port), service_ready(prometheus_scrapes_vllm)]).

service_check(grafana_prom_datasource, Check, Fix) :-
    Check = "test -f /etc/grafana/provisioning/datasources/prometheus.yaml",
    Fix = "printf '%s\\n' 'apiVersion: 1' 'datasources:' '- name: Prometheus' '  type: prometheus' '  access: proxy' '  url: http://localhost:9095' '  isDefault: true' > /etc/grafana/provisioning/datasources/prometheus.yaml".
%% Official vLLM dashboard, pinned to the installed vllm minor (0.18) so panel
%% metric names match the servers.
service_check(grafana_vllm_dashboard, Check, Fix) :-
    Check = "test -s /var/lib/grafana/dashboards/vllm.json",
    Fix = "mkdir -p /var/lib/grafana/dashboards && curl -fsSL https://raw.githubusercontent.com/vllm-project/vllm/v0.18.0/examples/online_serving/prometheus_grafana/grafana.json -o /var/lib/grafana/dashboards/vllm.json && printf '%s\\n' 'apiVersion: 1' 'providers:' '- name: vllm' \"  folder: ''\" '  type: file' '  options:' '    path: /var/lib/grafana/dashboards' > /etc/grafana/provisioning/dashboards/vllm.yaml && chown -R grafana:grafana /var/lib/grafana/dashboards".
service_check(grafana_running, Check, Fix) :-
    Check = "systemctl is-enabled --quiet grafana-server && systemctl is-active --quiet grafana-server",
    Fix = "systemctl enable --now grafana-server && systemctl restart grafana-server".
service_deps(grafana_running,
    [service_ready(grafana_prom_datasource), service_ready(grafana_vllm_dashboard)]).