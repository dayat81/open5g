ANSIBLE ?= ansible-playbook
INVENTORY ?= -i inventory/lab5g-dev.yml
TAGS ?=
EXTRA ?=
.PHONY: up down verify lint check render secrets-check
up:
	$(ANSIBLE) $(INVENTORY) site.yml --tags up $(EXTRA)
down:
	$(ANSIBLE) $(INVENTORY) teardown.yml $(EXTRA)
verify:
	$(ANSIBLE) $(INVENTORY) site.yml --tags verify $(EXTRA)
lint:
	yamllint -c .yamllint.yml site.yml teardown.yml requirements.yml group_vars inventory roles host_vars
	ansible-lint -c .ansible-lint site.yml teardown.yml
	$(ANSIBLE) -i inventory/local-dry-run.yml site.yml --syntax-check
render:
	$(ANSIBLE) -i inventory/local-dry-run.yml site.yml --tags base,core,ran --check
	python3 tests/validate_rendered.py
check: lint render secrets-check
secrets-check:
	bash scripts/secret-scan.sh
