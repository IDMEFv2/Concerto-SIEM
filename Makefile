# ============================================================
# Concerto SIEM - Master Makefile
# ============================================================
# Manages the lifecycle of the Concerto SIEM stack using Podman
# and podman-compose.
#
# Quick start:
#   make            Show this help
#   make up         Build and start the SIEM
#   make ps         Show container status
#   make down       Stop the SIEM
#
# The following files are included at the bottom and add
# specialized targets:
#   Makefile.diag     Diagnostic and evidence targets
#   Makefile.syslog   Syslog forwarding targets
#   Makefile.proxy    Reverse proxy targets
#   Makefile.certs    Self-signed certificate targets
#
# For a full list of targets: make help
# ============================================================

# ------------------------------------------------------------
# Help (default goal)
# ------------------------------------------------------------
# Running `make` with no arguments shows this help instead of
# executing an arbitrary target.
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo ""
	@echo "Concerto SIEM - Makefile targets"
	@echo "=================================="
	@echo ""
	@echo "Lifecycle:"
	@echo "  make up                Build and start the SIEM"
	@echo "  make up-build          Rebuild images from scratch and start"
	@echo "  make down              Stop the SIEM"
	@echo "  make ps                Show container status"
	@echo "  make clean             Stop the SIEM and remove all data"
	@echo ""
	@echo "Testing:"
	@echo "  make tests_logs        Send example logs to the SIEM"
	@echo "  make tests_idmefv2     Send example IDMEFv2 alerts"
	@echo "  make up-test           Start the NGINX test webserver"
	@echo "  make down-test         Stop the NGINX test webserver"
	@echo "  make clean-test        Remove the NGINX test webserver"
	@echo ""
	@echo "Syslog forwarding:"
	@echo "  make log-help          List syslog forwarding targets"
	@echo "  make log-status        Show current forwarding status"
	@echo "  make log-start         Enable rsyslog forwarding to the SIEM"
	@echo "  make log-stop          Disable forwarding, keep queued logs"
	@echo "  make log-clear         Disable forwarding, discard queued logs"
	@echo ""
	@echo "Reverse proxy:"
	@echo "  make proxy-help        List reverse proxy targets"
	@echo "  make up-proxy          Start the reverse proxy"
	@echo "  make down-proxy        Stop the reverse proxy"
	@echo "  make proxy-test        Test the proxy from the host"
	@echo ""
	@echo "Diagnostics:"
	@echo "  make diag-help         List all diagnostic targets"
	@echo "  make diag              Run all passive diagnostic checks"
	@echo "  make diag-quick        Quick OK/FAIL health check"
	@echo "  make diag-flow         End-to-end log and alert flow test"
	@echo "  make evidence          Collect diagnostics into evidence.txt"
	@echo ""
	@echo "Certificates:"
	@echo "  make certs-help        List certificate targets"
	@echo "  make certs-init        Generate a self-signed certificate"
	@echo "  make certs-force       Force regenerate the certificate"
	@echo "  make certs-clean       Remove certificate files"
	@echo ""
	@echo "This help:"
	@echo "  make help              Show this message"
	@echo ""

# ============================================================
# System prerequisites
# ============================================================

# Elasticsearch requires vm.max_map_count >= 262144. If the
# current value is lower, this target runs automatically as a
# dependency of `up`, `up-build`, and `up-test`.
.PHONY: max_map_count
max_map_count:
	sudo sysctl -w vm.max_map_count=262144

# Only include max_map_count as a prerequisite if the current
# value is not already sufficient. This avoids an unnecessary
# sudo call on systems that are already configured correctly.
ELASTIC_MMC :=
ifneq ($(shell cat /proc/sys/vm/max_map_count),262144)
	ELASTIC_MMC := max_map_count
endif

# ============================================================
# Data directories
# ============================================================

# The main stack needs these host directories for persistent
# storage. If elasticsearch_data is missing, the stack has never
# been started on this host, so proto_dirs is invoked to create
# the full set.
PROTO_DIRS :=
ifeq ($(wildcard elasticsearch_data),)
	PROTO_DIRS = proto_dirs
endif

PROTO_DIRS_TEST := proto_dirs-test

# Create the persistent data directories for the main stack.
# The chown ensures the containers (which run as UID 1000 for
# Elasticsearch and PostgreSQL) can write to them.
.PHONY: proto_dirs
proto_dirs:
	sudo mkdir -pv elasticsearch_data elasticsearch_logs kafka_logs postgres_data setup_data
	sudo chown -R 1000:0 elasticsearch_data elasticsearch_logs postgres_data setup_data

# Create the persistent data directory for the NGINX test webserver.
.PHONY: proto_dirs-test
proto_dirs-test:
	sudo mkdir -pv nginx_data
	sudo chown -R 1000:0 nginx_data

# ============================================================
# Prerequisite checks
# ============================================================

# Verify that podman and podman-compose are installed, and that
# Podman is version 4 or higher. This target is a prerequisite of
# every target that interacts with the container runtime.
.PHONY: check_bin
check_bin:
ifeq (,$(shell which podman))
		$(error "podman seems to not be installed")
endif
ifeq (,$(shell which podman-compose))
		$(error "podman-compose seems to not be installed")
endif

PODMAN_VERSION_OK := $(shell podman version --format '{{.Version}}' | awk -F. '$$1 >= 4 {print "yes"}')
ifndef PODMAN_VERSION_OK
	$(error Podman version must be >= 4)
endif

# ============================================================
# Main stack lifecycle
# ============================================================

# Show all containers, including stopped ones.
.PHONY: ps
ps: check_bin
	sudo podman ps -a

# Start the stack. The output is redirected to the `logs` file
# so the terminal stays usable. The stack runs in the background.
.PHONY: up
up: check_bin $(ELASTIC_MMC) $(PROTO_DIRS)
	(sudo podman-compose -p proto -f docker-compose.yml up 1>>logs 2>&1 &)

# Rebuild all images from scratch (no cache), then recreate the
# containers. Use this after changing a Dockerfile or when an
# image is suspected to be stale.
.PHONY: up-build
up-build: check_bin $(ELASTIC_MMC) $(PROTO_DIRS)
	(sudo podman-compose -p proto -f docker-compose.yml build --no-cache 1>>logs 2>&1 && sudo podman-compose -p proto -f docker-compose.yml up --build --force-recreate 1>>logs 2>&1 &)

# Stop and remove the containers of the main stack.
# Data volumes on the host are preserved.
.PHONY: down
down: check_bin
	sudo podman-compose -p proto -f docker-compose.yml down

# Remove the locally built images of the main stack.
.PHONY: clean_podman
clean_podman: check_bin down
	sudo podman rmi localhost/proto_setup localhost/proto_es01 localhost/proto_logstash localhost/proto_kafka1 localhost/proto_zoo1 localhost/proto_kafdrop localhost/proto_gui localhost/proto_postgres localhost/proto_correlator || true

# Full reset: stop the stack, remove images, and delete all
# persistent data. The next `make up` starts from a clean state.
.PHONY: clean
clean: clean_podman check_bin down
	sudo rm -rvf logs
	sudo rm -rvf elasticsearch_data elasticsearch_logs kafka_logs postgres_data

# ============================================================
# NGINX test webserver
# ============================================================
# A separate lightweight stack used to generate test logs
# (HTTP 200, 403, 404, 500 responses) for the SIEM.

# Start the NGINX test webserver.
.PHONY: up-test
up-test: check_bin $(ELASTIC_MMC) $(PROTO_DIRS_TEST)
	(sudo podman-compose -p proto -f docker-compose-test.yml up 1>>logs 2>&1 &)

# Stop the NGINX test webserver.
.PHONY: down-test
down-test: check_bin
	sudo podman-compose -p proto -f docker-compose-test.yml down

# Remove the NGINX test webserver image.
.PHONY: clean_podman-test
clean_podman-test: check_bin down-test
	sudo podman rmi localhost/proto_nginx

# Full reset of the NGINX test webserver, including its data.
.PHONY: clean-test
clean-test: clean_podman-test check_bin down-test
	sudo rm -rvf nginx_data

# ============================================================
# Test data injection
# ============================================================
# These targets send example data to the running SIEM to verify
# that ingestion and detection work end to end.

# Send example syslog lines from tests/example_logs to the SIEM.
# A temporary container is built and run on the proto network.
.PHONY: tests_logs
tests_logs: check_bin
	sudo podman build -t proto_tests -f tests/Dockerfile tests/
	sudo podman run --rm --name=proto_tests_logs -v $(shell pwd)/tests/example_logs:/logs:Z,ro -v $(shell pwd)/tests/entrypoint_tests_logs.sh:/entrypoint.sh:Z,ro --net proto_proto --network-alias tests-logs proto_tests

# Send example IDMEFv2 alerts from tests/example_idmefv2 to the SIEM.
.PHONY: tests_idmefv2
tests_idmefv2: check_bin
	sudo podman build -t proto_tests -f tests/Dockerfile tests/
	sudo podman run --rm --name=proto_tests_idmefv2 -v $(shell pwd)/tests/example_idmefv2:/idmefv2:Z,ro -v $(shell pwd)/tests/entrypoint_tests_idmefv2.py:/entrypoint.sh:Z,ro --net proto_proto --network-alias tests-idmefv2 proto_tests

# ============================================================
# Included Makefiles
# ============================================================
# These files add targets for specific concerns. They are
# included with `-include` so that a missing file does not
# break the build. Each one provides its own *-help target.

# Diagnostic targets: diag, diag-quick, diag-flow, evidence, ...
-include Makefile.diag

# Syslog forwarding targets: log-status, log-start, log-stop, log-clear, ...
-include Makefile.syslog

# Reverse proxy targets: up-proxy, down-proxy, proxy-reload, ...
-include Makefile.proxy

# Self-signed certificate targets: certs-init, certs-force, ...
-include Makefile.certs
